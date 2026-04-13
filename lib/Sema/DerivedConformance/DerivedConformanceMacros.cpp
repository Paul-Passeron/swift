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
#include "swift/AST/ASTContext.h"
#include "swift/AST/MacroDefinition.h"

using namespace swift;

bool swift::isAstGenMacro(MacroDecl *macro) {
  auto macroDef = macro->getDefinition();
  if (macroDef.kind != MacroDefinition::Kind::Builtin) {
    return false;
  }
  auto builtinKind = macroDef.getBuiltinKind();
  return builtinKind == BuiltinMacroKind::DerivedConformanceMacro;
}

SourceFile *swift::evaluateASTGenMacro(ASTContext &ctx, MacroDecl *macro,
                                       AbstractFunctionDecl *fn,
                                       CustomAttr *attr) {
  // Maybe use X Macros when there will be a lot of cases
  if (macro->getBaseName() == "EquatableStructMacro") {
    return evaluateEquatableStructMacro(ctx, fn, macro, attr);
  }
  if (macro->getBaseName() == "EquatableEnumMacro") {
    return evaluateEquatableEnumMacro(ctx, fn, macro, attr);
  }
  return nullptr;
}

SourceFile *
swift::getSourceFileForAstGenMacro(ASTContext &ctx, AbstractFunctionDecl *fn,
                                   MacroDecl *macro, CustomAttr *attr,
                                   const char *outBuffer, size_t outLen) {
  auto bufferID = ctx.SourceMgr.addMemBufferCopy(StringRef(outBuffer, outLen),
                                                 "__ast_gen_macro_expansion__");

  auto *sd = fn->getDeclContext()->getSelfNominalTypeDecl();
  GeneratedSourceInfo sourceInfo;
  auto startLoc = sd->getStartLoc();
  sourceInfo.originalSourceRange =
      CharSourceRange(ctx.SourceMgr, startLoc, startLoc);
  sourceInfo.kind = GeneratedSourceInfo::BodyMacroExpansion;
  auto bufferStart = ctx.SourceMgr.getLocForBufferStart(bufferID);
  sourceInfo.generatedSourceRange = CharSourceRange(bufferStart, outLen);
  sourceInfo.astNode = ASTNode(fn).getOpaqueValue();
  sourceInfo.declContext = fn;
  sourceInfo.attachedMacroCustomAttr = attr;
  sourceInfo.macroName = macro->getName().getBaseName().userFacingName().str();
  auto *SF = new (ctx) SourceFile(*fn->getParentModule(),
                                  SourceFileKind::MacroExpansion, bufferID);
  ctx.SourceMgr.setGeneratedSourceInfo(bufferID, sourceInfo);
  return SF;
}

const char *swift::cloneString(llvm::BumpPtrAllocator &allocator,
                               StringRef str) {
  auto len = str.size() + 1;
  auto *buf = allocator.Allocate<char>(len);
  memcpy(buf, str.data(), len);
  return buf;
}


SourceFile *swift::evaluateEquatableEnumMacro(ASTContext &ctx,
                                              AbstractFunctionDecl *fn,
                                              MacroDecl *macro,
                                              CustomAttr *attr) {
  auto *parent = fn->getParent();
  assert(parent && "Should have a parent context");

  auto *enum_decl = parent->getSelfEnumDecl();
  assert(parent && "Self should be a enum type");

  llvm::BumpPtrAllocator alloc; // Bump allocator for strings
  SmallVector<EnumCaseInfo, 6> cases;

  for (const auto *the_case : enum_decl->getAllCases()) {
    // TODO: Handle unavailable cases
    for (const auto *elt : the_case->getElements()) {
      SmallVector<const char *, 6> *argLabels =
          new (alloc) SmallVector<const char *, 6>();
      const char *name =
          cloneString(alloc, elt->getBaseIdentifier().str().data());
      if (elt->hasAssociatedValues()) {
        auto payloadType = elt->getPayloadInterfaceType();
        if (auto tupleType = payloadType->getAs<TupleType>()) {
          for (auto tupleElement : tupleType->getElements()) {
            if (tupleElement.hasName()) {
              argLabels->emplace_back(
                  cloneString(alloc, tupleElement.getName().str().data()));
            } else {
              argLabels->emplace_back(nullptr);
            }
          }
        } else {
          // TODO: is this right ?
          argLabels->emplace_back(nullptr);
        }
      }
      bool isUnavailable = elt->isUnreachableAtRuntime() &&
                           !elt->getParentEnum()->isUnreachableAtRuntime() &&
                           ctx.getDiagnoseUnavailableCodeReached() != nullptr;
      cases.emplace_back((EnumCaseInfo){.caseName = name,
                                        .argLabels = argLabels->data(),
                                        .argCount = argLabels->size(),
                                        .isUnavailable = isUnavailable});
    }
  }

  char *outBuffer;
  size_t outLen;
  if (!swift_ASTGen_expandEquatableEnumMacro(cases.data(), cases.size(),
                                             &outBuffer, &outLen)) {
    return nullptr;
  }
  auto *SF =
      getSourceFileForAstGenMacro(ctx, fn, macro, attr, outBuffer, outLen);

  // TODO: Do we want to do this ?
  if (outBuffer) {
    std::free(outBuffer);
  }

  return SF;
}
