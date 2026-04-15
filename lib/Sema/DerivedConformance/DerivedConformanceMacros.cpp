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

std::unique_ptr<llvm::MemoryBuffer>
swift::evaluateASTGenMacroBuffer(ASTContext &ctx, MacroDecl *macro, Decl *decl,
                                 CustomAttr *attr) {
  if (auto *fn = dyn_cast<AbstractFunctionDecl>(decl)) {

    if (macro->getBaseName() == "EquatableStructMacro") {
      return evaluateEquatableStructMacroBuffer(ctx, fn, macro, attr);
    }
    if (macro->getBaseName() == "EquatableEnumMacro") {
      return evaluateEquatableEnumMacroBuffer(ctx, fn, macro, attr);
    }
  } else if (auto *expansion = dyn_cast<MacroExpansionDecl>(decl)) {
    if (macro->getBaseName() == "EquatableDeclMacro") {
      return evaluateEquatableDeclMacroBuffer(
          ctx, expansion->getDeclContext()->getSelfNominalTypeDecl(), expansion,
          macro);
    }
  }
  return nullptr;
}

static std::string getUniqueASTGenBufferName() {
  static int counter = 0;
  return "__ast_gen_macro_expansion__" + std::to_string(counter++);
}

std::unique_ptr<llvm::MemoryBuffer>
swift::getBufferForAstGenMacro(const char *outBuffer, size_t outLen) {
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

  return getBufferForAstGenMacro(outBuffer, outLen);
}

std::unique_ptr<llvm::MemoryBuffer>
swift::evaluateEquatableDeclMacroBuffer(ASTContext &ctx, TypeDecl *ty,
                                        MacroExpansionDecl *expansion,
                                        MacroDecl *macro) {
  char *outBuffer;
  size_t outLen;
  if (!swift_ASTGen_expandEquatableDeclMacro(isa<EnumDecl>(ty), &outBuffer,
                                             &outLen)) {
    return nullptr;
  }
  return getBufferForAstGenMacro(outBuffer, outLen);
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
  return getBufferForAstGenMacro(outBuffer, outLen);
}
