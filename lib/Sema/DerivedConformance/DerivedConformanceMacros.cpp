//===--- DerivedConformanceMacros.cpp - Macro-based derivation ------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
//  This file implements the evaluation of built-in macros used to synthesize
//  compiler-derived protocol conformances (Equatable, Hashable, etc.).
//
//===----------------------------------------------------------------------===//

#include "DerivedConformanceMacros.h"
#include "CodeSynthesis.h"
#include "DerivedConformance/DerivedConformance.h"
#include "swift/AST/ASTContext.h"
#include "swift/AST/Decl.h"
#include "swift/AST/DeclContext.h"
#include "swift/AST/DeclNameLoc.h"
#include "swift/AST/Import.h"
#include "swift/AST/LayoutConstraint.h"
#include "swift/AST/MacroDefinition.h"
#include "swift/AST/NameLookup.h"
#include "swift/AST/SourceFile.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"

using namespace swift;

bool swift::isAstGenMacro(MacroDecl *macro) {
  auto macroDef = macro->getDefinition();
  if (macroDef.kind != MacroDefinition::Kind::Builtin) {
    return false;
  }
  auto builtinKind = macroDef.getBuiltinKind();
  return builtinKind == BuiltinMacroKind::DerivedConformanceMacro;
}

std::string swift::getUniqueASTGenBufferName() {
  static int counter = 0;
  return "__ast_gen_macro_expansion__" + std::to_string(counter++);
}

std::unique_ptr<llvm::MemoryBuffer>
swift::getBufferForAstGenMacro(char *outBuffer, size_t outLen) {
  auto buffer = llvm::MemoryBuffer::getMemBufferCopy(
      StringRef(outBuffer, outLen), getUniqueASTGenBufferName());
  if (outBuffer)
    std::free(outBuffer);
  return buffer;
}

const char *swift::cloneString(llvm::BumpPtrAllocator &allocator,
                               StringRef str) {
  auto len = str.size() + 1;
  auto *buf = allocator.Allocate<char>(len);
  memcpy(buf, str.data(), len);
  return buf;
}

unsigned swift::registerSynthesizedMacroBuffer(ASTContext &ctx, StringRef code,
                                               DeclContext *parentDc,
                                               SourceLoc atLoc,
                                               DerivedConformance &der) {
  auto buffer =
      llvm::MemoryBuffer::getMemBufferCopy(code, getUniqueASTGenBufferName());
  auto bufferID = ctx.SourceMgr.addNewSourceBuffer(std::move(buffer));
  GeneratedSourceInfo info;
  info.kind = GeneratedSourceInfo::Kind::DeclarationMacroExpansion;
  info.originalSourceRange = CharSourceRange(atLoc, 0);
  info.generatedSourceRange = ctx.SourceMgr.getRangeForBuffer(bufferID);
  info.astNode = ASTNode(der.ConformanceDecl).getOpaqueValue();
  info.declContext = parentDc;
  ctx.SourceMgr.setGeneratedSourceInfo(bufferID, info);
  return bufferID;
}

MacroExpansionDecl *swift::parseSynthesizedMacroDecl(ASTContext &ctx,
                                                     ModuleDecl *module,
                                                     unsigned bufferID,
                                                     DeclContext *parentDc,
                                                     ModuleDecl *otherModule) {
  auto *SF =
      new (ctx) SourceFile(*module, SourceFileKind::MacroExpansion, bufferID);
  SF->setImports({});
  auto decls = SF->getTopLevelDecls();
  assert(decls.size() == 1);
  auto *decl = decls[0];
  decl->setImplicit(true);
  auto *free = dyn_cast<MacroExpansionDecl>(decl);
  assert(free && "Expected a MacroExpansionDecl");
  return free;
}

SourceLoc swift::getValidSourceLocForImplicit(DerivedConformance &derived) {
  auto atLoc = derived.ConformanceDecl->getEndLoc();
  assert(atLoc.isValid() && "Conformance loc is invalid");
  return atLoc;
}

ValueDecl *swift::handleDerivedNode(DerivedConformance &der, ASTContext &ctx,
                                    ASTNode node) {
  auto *decl = node.dyn_cast<Decl *>();
  auto thisBuffer = ctx.SourceMgr.findBufferContainingLoc(decl->getStartLoc());
  auto *SF = ctx.SourceMgr.getSourceFilesForBufferID(thisBuffer)[0];
  auto scope = SF->getScope();
  scope.buildFullyExpandedTree();

  decl->setDeclContext(der.getConformanceContext());
  decl->setImplicit(true);

  if (isa<PatternBindingDecl>(decl)) {
    return nullptr;
  }
  auto vdecl = dyn_cast<ValueDecl>(decl);
  assert(vdecl);
  if (!vdecl->hasAccess()) {
    vdecl->copyFormalAccessFrom(der.Nominal,
                                /*sourceIsParentContext=*/true);
  } else {
    vdecl->overwriteAccess(der.Nominal->getFormalAccess());
  }

  if (auto fdecl = dyn_cast<AbstractFunctionDecl>(decl)) {
    addNonIsolatedToSynthesized(der, fdecl);
    // TODO: figure out why this line is needed,
    // the body should be expanded as needed
    // but this creates linking errors in some cases
    // (the stdlib build, not easy to reproduce)
    (void)fdecl->getMacroExpandedBody();
  }
  if (auto *vdecl = dyn_cast<VarDecl>(decl)) {
    vdecl->setImplInfo(StorageImplInfo::getImmutableComputed());
    if (auto *getter = vdecl->getAccessor(AccessorKind::Get)) {
      getter->setImplicit();
      getter->setSynthesized();
      if (!getter->hasAccess()) {
        getter->copyFormalAccessFrom(der.Nominal,
                                     /*sourceIsParentContext=*/true);
      } else {
        getter->overwriteAccess(der.Nominal->getFormalAccess());
      }
    }
  }
  return vdecl;
}

TypeDecl *swift::handleTypeDeclDerivedNode(DerivedConformance &der,
                                           ASTContext &ctx, ASTNode node) {
  auto *decl = node.dyn_cast<Decl *>();
  assert(decl);
  auto tdecl = dyn_cast<TypeDecl>(decl);
  assert(tdecl);
  return tdecl;
}

MacroExpansionDecl *swift::createMacroExpansionForConformanceDerivation(
    DerivedConformance &der, ModuleDecl *module, StringRef code, bool forType) {
  auto *parentDc = der.getConformanceContext();
  auto &ctx = parentDc->getASTContext();
  auto atLoc = getValidSourceLocForImplicit(der);
  auto bufferID =
      registerSynthesizedMacroBuffer(ctx, code, parentDc, atLoc, der);
  auto *free =
      parseSynthesizedMacroDecl(ctx, der.getParentModule(), bufferID, parentDc, module);
  auto *eInfo = free->getExpansionInfo();
  eInfo->SigilLoc = atLoc;
  eInfo->MacroNameLoc = DeclNameLoc(atLoc);
  der.addMemberToConformanceContext(free, nullptr);
  return free;
}

TypeDecl *swift::deriveTypeRequirementViaMacro(DerivedConformance &der,
                                               ModuleDecl *module,
                                               StringRef code) {
  auto *parentDc = der.getConformanceContext();
  auto &ctx = parentDc->getASTContext();
  auto *free =
      createMacroExpansionForConformanceDerivation(der, module, code, true);
  TypeDecl *decl = nullptr;
  free->forEachExpandedNode([&](ASTNode node) {
    if (auto tdecl = handleTypeDeclDerivedNode(der, ctx, node)) {
      decl = tdecl;
    }
  });
  return decl;
}

ValueDecl *swift::deriveRequirementViaMacro(DerivedConformance &der,
                                            ModuleDecl *module,
                                            StringRef code) {
  auto *parentDc = der.getConformanceContext();
  auto &ctx = parentDc->getASTContext();
  auto *free =
      createMacroExpansionForConformanceDerivation(der, module, code, false);
  ValueDecl *val = nullptr;
  free->forEachExpandedNode([&](ASTNode node) {
    if (auto vdecl = handleDerivedNode(der, ctx, node)) {
      val = vdecl;
    }
  });
  return val;
}

bool swift::isMacroDerivationEnabled(const ASTContext &C) {
  return C.LangOpts.hasFeature(Feature::DeriveConformancesViaMacros);
}
