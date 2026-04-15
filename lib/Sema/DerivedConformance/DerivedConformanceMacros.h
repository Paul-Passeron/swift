//===--- DerivedConformanceMacros.h -----------------------------*- C++ -*-===//
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
//  This file declares the interface for evaluating built-in macros that
//  synthesize compiler-derived protocol conformances.
//
//===----------------------------------------------------------------------===//

#ifndef SWIFT_SEMA_DERIVEDCONFORMANCE_DERIVEDCONFORMANCEMACRO_H
#define SWIFT_SEMA_DERIVEDCONFORMANCE_DERIVEDCONFORMANCEMACRO_H

#include "swift/AST/Decl.h"
namespace swift {

bool isAstGenMacro(MacroDecl *macro);

std::unique_ptr<llvm::MemoryBuffer> evaluateASTGenMacroBuffer(ASTContext &ctx,
                                                              MacroDecl *macro,
                                                              Decl *decl,
                                                              CustomAttr *attr);
std::unique_ptr<llvm::MemoryBuffer>
getBufferForAstGenMacro(const char *outBuffer, size_t outLen);
// std::unique_ptr<llvm::MemoryBuffer>
// getBufferForAstGenMacro(ASTContext &ctx, AbstractFunctionDecl *fn,
//                         MacroDecl *macro, CustomAttr *attr,
//                         const char *outBuffer, size_t outLen);

// std::unique_ptr<llvm::MemoryBuffer> getBufferForAstGenFreestandingMacro(
//     ASTContext &ctx, NominalTypeDecl *ty, MacroDecl *macro,
//     MacroExpansionDecl *expansion, const char *outBuffer, size_t outLen);

// ==== Equatable =============================================================

std::unique_ptr<llvm::MemoryBuffer>
evaluateEquatableStructMacroBuffer(ASTContext &ctx, AbstractFunctionDecl *fn,
                                   MacroDecl *macro, CustomAttr *attr);

std::unique_ptr<llvm::MemoryBuffer>
evaluateEquatableEnumMacroBuffer(ASTContext &ctx, AbstractFunctionDecl *fn,
                                 MacroDecl *macro, CustomAttr *attr);

std::unique_ptr<llvm::MemoryBuffer>
evaluateEquatableDeclMacroBuffer(ASTContext &ctx, TypeDecl *ty,
                                 MacroExpansionDecl *expansion,
                                 MacroDecl *macro);

const char *cloneString(llvm::BumpPtrAllocator &allocator, StringRef str);

extern "C" bool
swift_ASTGen_expandEquatableStructMacro(const char *const *propertyNames,
                                        size_t count, char **outBuffer,
                                        size_t *outLen);

extern "C" bool swift_ASTGen_expandEquatableEnumMacro(void *caseInfos,
                                                      size_t caseCount,
                                                      char **outBufferPtr,
                                                      size_t *outBufferLen);

extern "C" bool
swift_ASTGen_expandEquatableDeclMacro(bool isEnum, // False means is struct
                                      char **outBufferPtr,
                                      size_t *outBufferLen);

struct EnumCaseInfo {
  const char *caseName;
  const char *const *argLabels;
  size_t argCount;
  bool isUnavailable;
};
// ==== /Equatable ============================================================

} // namespace swift

#endif
