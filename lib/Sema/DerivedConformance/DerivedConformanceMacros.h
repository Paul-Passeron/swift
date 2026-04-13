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

#include "swift/AST/SourceFile.h"
namespace swift {

bool isAstGenMacro(MacroDecl *macro);

SourceFile *evaluateASTGenMacro(ASTContext &ctx, MacroDecl *macro,
                                AbstractFunctionDecl *fn, CustomAttr *attr);
SourceFile *getSourceFileForAstGenMacro(ASTContext &ctx,
                                        AbstractFunctionDecl *fn,
                                        MacroDecl *macro, CustomAttr *attr,
                                        const char *outBuffer, size_t outLen);

// ==== Equatable =============================================================
SourceFile *evaluateEquatableStructMacro(ASTContext &ctx,
                                         AbstractFunctionDecl *fn,
                                         MacroDecl *macro, CustomAttr *attr);

SourceFile *evaluateEquatableEnumMacro(ASTContext &ctx,
                                       AbstractFunctionDecl *fn,
                                       MacroDecl *macro, CustomAttr *attr);

const char *cloneString(llvm::BumpPtrAllocator &allocator, StringRef str);

extern "C" bool swift_ASTGen_expandEquatableStructMacro(
    const char * const *propertyNames,
    size_t count,
    char **outBuffer,
    size_t *outLen);

extern "C" bool swift_ASTGen_expandEquatableEnumMacro(
  void *caseInfos,
  size_t caseCount,
  char **outBufferPtr,
  size_t *outBufferLen
);

struct EnumCaseInfo {
  const char *caseName;
  const char *const *argLabels;
  size_t argCount;
  bool isUnavailable;
};
// ==== /Equatable ============================================================


} // namespace swift

#endif
