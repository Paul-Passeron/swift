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

#include "swift/AST/ASTBridging.h"
#include "swift/AST/Decl.h"
#include "swift/AST/DiagnosticEngine.h"
#include "swift/Basic/BasicBridging.h"
namespace swift {

bool isAstGenMacro(MacroDecl *macro);

std::unique_ptr<llvm::MemoryBuffer> evaluateASTGenMacroBuffer(ASTContext &ctx,
                                                              MacroDecl *macro,
                                                              Decl *decl,
                                                              CustomAttr *attr);
std::unique_ptr<llvm::MemoryBuffer> getBufferForAstGenMacro(char *outBuffer,
                                                            size_t outLen);

const char *cloneString(llvm::BumpPtrAllocator &allocator, StringRef str);
std::string getUniqueASTGenBufferName();
// ==== Equatable =============================================================

struct EnumCaseInfo {
  const char *caseName;
  const char *const *argLabels;
  size_t argCount;
  bool isUnavailable;
};

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

extern "C" bool
swift_ASTGen_expandEquatableStructMacro(const char *const *propertyNames,
                                        size_t count, char **outBuffer,
                                        size_t *outLen);

extern "C" bool swift_ASTGen_expandEquatableEnumMacro(void *caseInfos,
                                                      size_t caseCount,
                                                      char **outBufferPtr,
                                                      size_t *outBufferLen);

extern "C" bool swift_ASTGen_expandEquatableDeclMacro(
    bool isEnum, // False means the type is a struct
    char **outBufferPtr, size_t *outBufferLen);

extern "C" bool swift_Macros_expandFreestandingMacroSynthetic(
    BridgedASTContext cContext, const void *macroPtr, const char *discriminator,
    uint8_t rawMacroRole, BridgedStringRef macroNameText,
    BridgedStringRef argumentListText, BridgedStringRef *expandedSourceOutPtr);

// ==== /Equatable ============================================================

} // namespace swift

#endif
