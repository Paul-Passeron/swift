//
//  DeriveEquatable.swift
//  Swift
//
//  Created by Paul Passeron on 10/04/2026.
//

import SwiftSyntax

func expandEquatableStructMacroBody(propertyNames: [String], lhsName lhs: String = "a", rhsName rhs: String = "b")
  -> CodeBlockSyntax
{
  let guards: [CodeBlockItemSyntax] = propertyNames.map {
    name in
    """
    guard \(raw: lhs).\(raw: name) == \(raw: rhs).\(raw: name) else { return false; }
    """
  }
  return CodeBlockSyntax {
    for g in guards { g }
    "return true;"
  }
}
//
//func expandEquatableEnumNoCaseMacroBody(
//  lhsName lhs: String = "a",
//  rhsName rhs: String = "b"
//)
//  -> CodeBlockSyntax
//{
//  return CodeBlockSyntax {
//    "switch (a, b) {}"
//    "return true;"
//  }
//}
//
//func expandEquatableEnumNoAssociatedValuesMacroBody(
//  _ caseNames: [String],
//  lhsName lhs: String = "a",
//  rhsName rhs: String = "b"
//)
//  -> CodeBlockSyntax
//{
//  let cases: [SwitchCaseSyntax] =
//    caseNames.map { caseName in
//      """
//      case (.\(raw: caseName), .\(raw: caseName)): return true
//      """
//    } + ["default: return false"]
//
//  let caseList = SwitchCaseListSyntax {
//    for c in cases { c }
//  }
//
//  let switchExpr: SwitchExprSyntax = SwitchExprSyntax(
//    subject: "(\(raw: lhs), \(raw: rhs))" as ExprSyntax,
//    cases: caseList
//  )
//
//  return CodeBlockSyntax {
//    ExpressionStmtSyntax(expression: switchExpr)
//  }
//}

func expandEquatableEnumMacroBody(
  cases: [(caseName: String, argLabels: [String?])],
  lhsName lhs: String = "a",
  rhsName rhs: String = "b"
)
  -> CodeBlockSyntax
{
  fatalError("TODO")
}
