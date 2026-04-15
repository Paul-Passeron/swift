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
#include "swift/AST/Decl.h"
#include "swift/AST/DeclContext.h"
#include "swift/AST/LayoutConstraint.h"
#include "swift/AST/MacroDefinition.h"
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

static std::unique_ptr<llvm::MemoryBuffer>
evaluateASTGenMacroBufferImpl(ASTContext &ctx, MacroDecl *macro, Decl *decl,
                              CustomAttr *attr) {
  if (auto *fn = dyn_cast<AbstractFunctionDecl>(decl)) {

    if (macro->getBaseName() == "EquatableStructMacro") {
      return evaluateEquatableStructMacroBuffer(ctx, fn, macro, attr);
    }
    if (macro->getBaseName() == "EquatableEnumMacro") {
      return evaluateEquatableEnumMacroBuffer(ctx, fn, macro, attr);
    }
  } else if (auto *expansion = dyn_cast<MacroExpansionDecl>(decl)) {
    auto *ty =
        dyn_cast<NominalTypeDecl>(expansion->getDeclContext()->getAsDecl());
    ty->dump(llvm::errs());
    if (macro->getBaseName() == "EquatableDeclMacro") {
      return evaluateEquatableDeclMacroBuffer(ctx, ty, expansion, macro);
    }
  }
  return nullptr;
}

std::unique_ptr<llvm::MemoryBuffer>
swift::evaluateASTGenMacroBuffer(ASTContext &ctx, MacroDecl *macro, Decl *decl,
                                 CustomAttr *attr) {
  auto res = evaluateASTGenMacroBufferImpl(ctx, macro, decl, attr);
  llvm::errs() << "\n\n\n" << res->getBuffer().str() << "\n\n\n";
  return res;
}

SourceFile *swift::evaluateASTGenMacro(ASTContext &ctx, MacroDecl *macro,
                                       Decl *decl, CustomAttr *attr) {
  // Maybe use X Macros when there will be a lot of cases
  if (auto *fn = dyn_cast<AbstractFunctionDecl>(decl)) {

    if (macro->getBaseName() == "EquatableStructMacro") {
      return evaluateEquatableStructMacro(ctx, fn, macro, attr);
    }
    if (macro->getBaseName() == "EquatableEnumMacro") {
      return evaluateEquatableEnumMacro(ctx, fn, macro, attr);
    }
  } else if (auto *expansion = dyn_cast<MacroExpansionDecl>(decl)) {
    auto *ty =
        dyn_cast<NominalTypeDecl>(expansion->getDeclContext()->getAsDecl());
    ty->dump(llvm::errs());
    if (macro->getBaseName() == "EquatableDeclMacro") {
      return evaluateEquatableDeclMacro(ctx, ty, expansion, macro);
    }
  }
  return nullptr;
}

static std::string getUniqueASTGenBufferName() {
  static int counter = 0;
  return "__ast_gen_macro_expansion__" + std::to_string(counter++);
}

std::unique_ptr<llvm::MemoryBuffer>
swift::getBufferForAstGenMacro(ASTContext &ctx, AbstractFunctionDecl *fn,
                               MacroDecl *macro, CustomAttr *attr,
                               const char *outBuffer, size_t outLen) {
  return llvm::MemoryBuffer::getMemBufferCopy(StringRef(outBuffer, outLen),
                                              getUniqueASTGenBufferName());
}

SourceFile *
swift::getSourceFileForAstGenMacro(ASTContext &ctx, AbstractFunctionDecl *fn,
                                   MacroDecl *macro, CustomAttr *attr,
                                   const char *outBuffer, size_t outLen) {
  auto bufferID = ctx.SourceMgr.addMemBufferCopy(StringRef(outBuffer, outLen),
                                                 getUniqueASTGenBufferName());

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

static SourceFile *getSourceFileForAstGenFreestandingMacro(
    ASTContext &ctx, NominalTypeDecl *ty, MacroDecl *macro,
    MacroExpansionDecl *expansion, const char *outBuffer, size_t outLen) {
  auto bufferID = ctx.SourceMgr.addMemBufferCopy(StringRef(outBuffer, outLen),
                                                 getUniqueASTGenBufferName());
  GeneratedSourceInfo sourceInfo;
  auto startLoc = ty->getStartLoc();
  sourceInfo.originalSourceRange =
      CharSourceRange(ctx.SourceMgr, startLoc, startLoc);
  sourceInfo.kind = GeneratedSourceInfo::DeclarationMacroExpansion;
  auto bufferStart = ctx.SourceMgr.getLocForBufferStart(bufferID);
  sourceInfo.generatedSourceRange = CharSourceRange(bufferStart, outLen);
  sourceInfo.astNode = ASTNode(expansion).getOpaqueValue();
  sourceInfo.declContext = dyn_cast<DeclContext>(ty);
  sourceInfo.macroName = macro->getName().getBaseName().userFacingName().str();
  auto *SF = new (ctx) SourceFile(*ty->getModuleContext(),
                                  SourceFileKind::MacroExpansion, bufferID);
  ctx.SourceMgr.setGeneratedSourceInfo(bufferID, sourceInfo);
  return SF;
}

std::unique_ptr<llvm::MemoryBuffer> swift::getBufferForAstGenFreestandingMacro(
    ASTContext &ctx, NominalTypeDecl *ty, MacroDecl *macro,
    MacroExpansionDecl *expansion, const char *outBuffer, size_t outLen) {
  return llvm::MemoryBuffer::getMemBufferCopy(StringRef(outBuffer, outLen),
                                              getUniqueASTGenBufferName());
}

const char *swift::cloneString(llvm::BumpPtrAllocator &allocator,
                               StringRef str) {
  auto len = str.size() + 1;
  auto *buf = allocator.Allocate<char>(len);
  memcpy(buf, str.data(), len);
  return buf;
}
std::unique_ptr<llvm::MemoryBuffer> swift::evaluateEquatableEnumMacroBuffer(
    ASTContext &ctx,
    AbstractFunctionDecl *fn, // Can be null if not a body macro
    MacroDecl *macro, CustomAttr *attr) {
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

  return getBufferForAstGenMacro(ctx, fn, macro, attr, outBuffer, outLen);
}

SourceFile *swift::evaluateEquatableEnumMacro(
    ASTContext &ctx,
    AbstractFunctionDecl *fn, // Can be null if not a body macro
    MacroDecl *macro, CustomAttr *attr) {
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

SourceFile *swift::evaluateEquatableDeclMacro(ASTContext &ctx,
                                              NominalTypeDecl *ty,
                                              MacroExpansionDecl *expansion,
                                              MacroDecl *macro) {
  macro->dump(llvm::errs());
  assert(ty && "equatable decl macro must be attached to a type declaration");
  llvm::errs() << "Evaluating equatable decl macro for: " << ty->getName()
               << "\n";
  char *outBuffer;
  size_t outLen;
  if (!swift_ASTGen_expandEquatableDeclMacro(isa<EnumDecl>(ty), &outBuffer,
                                             &outLen)) {
    return nullptr;
  }
  auto *SF = getSourceFileForAstGenFreestandingMacro(ctx, ty, macro, expansion,
                                                     outBuffer, outLen);

  llvm::errs() << "Generated source for equatable decl macro: "
               << SF->getBuffer().str() << "\n";

  // TODO: Do we want to do this ?
  if (outBuffer) {
    std::free(outBuffer);
  }

  auto buffer = SF->getBuffer().str();
  return SF;
}

std::unique_ptr<llvm::MemoryBuffer>
swift::evaluateEquatableDeclMacroBuffer(ASTContext &ctx, NominalTypeDecl *ty,
                                        MacroExpansionDecl *expansion,
                                        MacroDecl *macro) {
  macro->dump(llvm::errs());
  assert(ty && "equatable decl macro must be attached to a type declaration");
  llvm::errs() << "Evaluating equatable decl macro for: " << ty->getName()
               << "\n";
  char *outBuffer;
  size_t outLen;
  if (!swift_ASTGen_expandEquatableDeclMacro(isa<EnumDecl>(ty), &outBuffer,
                                             &outLen)) {
    return nullptr;
  }
  return getBufferForAstGenFreestandingMacro(ctx, ty, macro, expansion,
                                             outBuffer, outLen);
}

std::unique_ptr<llvm::MemoryBuffer>
swift::evaluateEquatableStructMacroBuffer(ASTContext &ctx,
                                          AbstractFunctionDecl *fn,
                                          MacroDecl *macro, CustomAttr *attr) {
  auto *parent = fn->getParent();
  assert(parent && "Should have a parent context");

  auto *struct_decl = parent->getSelfStructDecl();
  assert(parent && "Self should be a struct type");

  SmallVector<const char *, 6> fieldNames;
  auto alloc = llvm::BumpPtrAllocator();
  for (auto propertyDecl : struct_decl->getStoredProperties()) {
    if (!propertyDecl->isUserAccessible())
      continue;
    fieldNames.emplace_back(
        cloneString(alloc, propertyDecl->getNameStr().str().c_str()));
  }

  char *outBuffer;
  size_t outLen;
  const char *const *propertyNames = fieldNames.data();
  if (!swift_ASTGen_expandEquatableStructMacro(propertyNames, fieldNames.size(),
                                               &outBuffer, &outLen)) {
    return nullptr;
  }
  return getBufferForAstGenMacro(ctx, fn, macro, attr, outBuffer, outLen);
}
