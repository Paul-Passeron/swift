//===--- DerivedConformanceError.cpp ----------------------------*- C++ -*-===//
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
//  This file implements implicit derivation of the Error
//  protocol.
//
//===----------------------------------------------------------------------===//

#include "CodeSynthesis.h"
#include "DerivedConformance.h"
#include "DerivedConformanceMacros.h"
#include "TypeChecker.h"
#include "swift/AST/Decl.h"
#include "swift/AST/Expr.h"
#include "swift/AST/Module.h"
#include "swift/AST/Stmt.h"
#include "swift/AST/SwiftNameTranslation.h"
#include "swift/AST/Types.h"
#include "llvm/Support/ErrorHandling.h"

using namespace swift;
using namespace swift::objc_translation;

static std::pair<BraceStmt *, bool>
deriveBodyBridgedNSError_enum_nsErrorDomain(AbstractFunctionDecl *domainDecl,
                                            void *) {
  // enum SomeEnum {
  //   @derived
  //   static var _nsErrorDomain: String {
  //     return String(reflecting: self)
  //   }
  // }

  auto M = domainDecl->getParentModule();
  auto &C = M->getASTContext();
  auto self = domainDecl->getImplicitSelfDecl();

  auto selfRef = new (C) DeclRefExpr(self, DeclNameLoc(), /*implicit*/ true);
  auto stringType = TypeExpr::createImplicitForDecl(
      DeclNameLoc(), C.getStringDecl(), domainDecl,
      C.getStringDecl()->getInterfaceType());
  auto *argList = ArgumentList::forImplicitSingle(
      C, C.getIdentifier("reflecting"), selfRef);
  auto *initReflectingCall = CallExpr::createImplicit(C, stringType, argList);
  auto *ret = ReturnStmt::createImplicit(C, initReflectingCall);

  auto body = BraceStmt::create(C, SourceLoc(), ASTNode(ret), SourceLoc());
  return { body, /*isTypeChecked=*/false };
}

static std::pair<BraceStmt *, bool>
deriveBodyBridgedNSError_printAsObjCEnum_nsErrorDomain(
                    AbstractFunctionDecl *domainDecl, void *) {
  // enum SomeEnum {
  //   @derived
  //   static var _nsErrorDomain: String {
  //     return "ModuleName.SomeEnum"
  //   }
  // }

  auto M = domainDecl->getParentModule();
  auto &C = M->getASTContext();
  auto TC = domainDecl->getInnermostTypeContext();
  auto ED = TC->getSelfEnumDecl();

  StringRef value(C.AllocateCopy(getErrorDomainStringForObjC(ED)));

  auto string = new (C) StringLiteralExpr(value, SourceRange(), /*implicit*/ true);
  auto *ret = ReturnStmt::createImplicit(C, SourceLoc(), string);
  auto body = BraceStmt::create(C, SourceLoc(),
                                ASTNode(ret),
                                SourceLoc());
  return { body, /*isTypeChecked=*/false };
}

static ValueDecl *
deriveBridgedNSError_enum_nsErrorDomain(
    DerivedConformance &derived,
    std::pair<BraceStmt *, bool> (*synthesizer)(AbstractFunctionDecl *, void*)) {
  // enum SomeEnum {
  //   @derived
  //   static var _nsErrorDomain: String {
  //     ...
  //   }
  // }

  auto stringTy = derived.Context.getStringType();

  // Define the property.
  VarDecl *propDecl;
  PatternBindingDecl *pbDecl;
  std::tie(propDecl, pbDecl) = derived.declareDerivedProperty(
      DerivedConformance::SynthesizedIntroducer::Var,
      derived.Context.Id_nsErrorDomain, stringTy, /*isStatic=*/true,
      /*isFinal=*/true);
  addNonIsolatedToSynthesized(derived.Nominal, propDecl);

  // Define the getter.
  auto getterDecl = derived.addGetterToReadOnlyDerivedProperty(propDecl);
  getterDecl->setBodySynthesizer(synthesizer);

  derived.addMembersToConformanceContext({propDecl, pbDecl});

  return propDecl;
}

static ValueDecl *deriveBridgedNSErrorViaMacros(DerivedConformance &der,
                                                ValueDecl *requirement) {
  auto *parentDc = der.getConformanceContext();
  auto &C = parentDc->getASTContext();
  auto atLoc = getValidSourceLocForImplicit(der, requirement);
  std::string code = "#deriveErrorNSErrorDomain";
  auto scope =
      der.Nominal->getFormalAccessScope(der.Nominal->getModuleScopeContext());
  if (scope.isPublic() || scope.isInternal()) {
    // TODO: is using Nominal instead of domainDecl right ?
    auto M = der.Nominal->getParentModule();
    auto &C = M->getASTContext();
    auto TC = der.Nominal->getInnermostTypeContext();
    auto ED = TC->getSelfEnumDecl();

    StringRef value(C.AllocateCopy(getErrorDomainStringForObjC(ED)));
    code += "(\"";
    code += value;
    code += "\")";
  }

  auto bufferID = registerSynthesizedMacroBuffer(C, code, parentDc, atLoc, der);
  auto *free = parseSynthesizedMacroDecl(C, requirement->getModuleContext(),
                                         bufferID, parentDc);

  auto *eInfo = const_cast<MacroExpansionInfo *>(free->getExpansionInfo());
  eInfo->SigilLoc = atLoc;
  eInfo->MacroNameLoc = DeclNameLoc(atLoc);

  der.addMemberToConformanceContext(free, nullptr);
  ValueDecl *val = nullptr;
  free->forEachExpandedNode([&](ASTNode node) {
    auto *decl = node.dyn_cast<Decl *>();
    auto thisBuffer =
        C.SourceMgr.findBufferContainingLoc(decl->getStartLoc());
    auto *SF = C.SourceMgr.getSourceFilesForBufferID(thisBuffer)[0];
    auto scope = SF->getScope();
    scope.buildFullyExpandedTree();

    decl->setDeclContext(der.getConformanceContext());
    decl->setImplicit(true);

    if (isa<PatternBindingDecl>(decl)) {
      return;
    }
    auto vdecl = dyn_cast<ValueDecl>(decl);
    assert(vdecl);
    vdecl->setSynthesized();
    if (!vdecl->hasAccess()) {
      vdecl->copyFormalAccessFrom(der.Nominal,
                                  /*sourceIsParentContext=*/true);
    } else {
      vdecl->overwriteAccess(der.Nominal->getFormalAccess());
    }
    val = vdecl;
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
        getter->setIsTransparent(false);
      }
      val = vdecl;
    }
  });
  assert(val && "Macro expansion did not produce a witness");
  return val;
}

ValueDecl *DerivedConformance::deriveBridgedNSError(ValueDecl *requirement) {
  if (!isa<EnumDecl>(Nominal))
    return nullptr;

  if (requirement->getBaseName() != Context.Id_nsErrorDomain) {
    Context.Diags.diagnose(requirement->getLoc(),
                           diag::broken_errortype_requirement);
    return nullptr;
  }

  auto *parentDc = getConformanceContext();
  auto &C = parentDc->getASTContext();

  if (C.LangOpts.hasFeature(Feature::DeriveConformancesViaMacros)) {
    return deriveBridgedNSErrorViaMacros(*this, requirement);
  }
  auto synthesizer = deriveBodyBridgedNSError_enum_nsErrorDomain;

  auto scope = Nominal->getFormalAccessScope(Nominal->getModuleScopeContext());
  if (scope.isPublic() || scope.isInternal())
    // PrintAsClang may print this domain, so we should make sure we use the
    // same string it will.
    synthesizer = deriveBodyBridgedNSError_printAsObjCEnum_nsErrorDomain;

  return deriveBridgedNSError_enum_nsErrorDomain(*this, synthesizer);
}
