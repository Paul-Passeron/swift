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
//  This file declares the interface for evaluating synthesized macros that
//  synthesize compiler-derived protocol conformances.
//
//===----------------------------------------------------------------------===//

#ifndef SWIFT_SEMA_DERIVEDCONFORMANCE_DERIVEDCONFORMANCEMACRO_H
#define SWIFT_SEMA_DERIVEDCONFORMANCE_DERIVEDCONFORMANCEMACRO_H

#include "DerivedConformance/DerivedConformance.h"
#include "swift/AST/ASTBridging.h"
#include "swift/AST/Decl.h"
#include "swift/Basic/BasicBridging.h"

namespace swift {

bool isAstGenMacro(MacroDecl *macro);

std::unique_ptr<llvm::MemoryBuffer> getBufferForAstGenMacro(char *outBuffer,
                                                            size_t outLen);

const char *cloneString(llvm::BumpPtrAllocator &allocator, StringRef str);
std::string getUniqueASTGenBufferName();

unsigned registerSynthesizedMacroBuffer(ASTContext &ctx, StringRef code,
                                        DeclContext *parentDc, SourceLoc atLoc,
                                        DerivedConformance &der);

MacroExpansionDecl *parseSynthesizedMacroDecl(ASTContext &ctx,
                                              ModuleDecl *module,
                                              unsigned bufferID,
                                              DeclContext *parentDc,
                                              ModuleDecl *otherModule);

SourceLoc getValidSourceLocForImplicit(DerivedConformance &derived);

ValueDecl *handleDerivedNode(DerivedConformance &der, ASTContext &ctx,
                             ASTNode node);
TypeDecl *handleTypeDeclDerivedNode(DerivedConformance &der, ASTContext &ctx,
                                    ASTNode node);

MacroExpansionDecl *
createMacroExpansionForConformanceDerivation(DerivedConformance &der,
                                             ModuleDecl *module, StringRef code,
                                             bool forType);

ValueDecl *deriveRequirementViaMacro(DerivedConformance &der,
                                     ModuleDecl *module, StringRef code);

TypeDecl *deriveTypeRequirementViaMacro(DerivedConformance &der,
                                        ModuleDecl *module, StringRef code);

bool isMacroDerivationEnabled(const ASTContext &C);

} // namespace swift

#endif
