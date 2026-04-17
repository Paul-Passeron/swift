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
