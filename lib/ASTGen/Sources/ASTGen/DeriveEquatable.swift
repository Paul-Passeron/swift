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

func getEnumCasePat(
  varPrefix: String,
  caseName: String,
  argLabels: [String?]
) -> PatternSyntax {
  if argLabels.isEmpty {
    return ".\(raw: caseName)"
  }
  let cases: [String] = argLabels.enumerated().map { (i, label) in
    if let label = label {
      "\(label): let \(varPrefix)\(i)"
    } else {
      "let \(varPrefix)\(i)"
    }
  }
  return
    """
    .\(raw: caseName)(\(raw: cases.joined(separator: ", ")))
    """
}

func hasNoAssociatedValues(_ cases: [(caseName: String, argLabels: [String?], isUnavailable: Bool)]) -> Bool {
  if cases.isEmpty { return false }
  for the_case in cases {
    if !the_case.argLabels.isEmpty { return false }
  }
  return true
}

func createDiscrSwitch(
  cases: [(caseName: String, argLabels: [String?], isUnavailable: Bool)],
  name: String
) -> SwitchExprSyntax {
  let casesSyntaxes: [SwitchCaseSyntax] = cases.enumerated().compactMap {
    (i, the_case) in
    if the_case.isUnavailable { return nil }
    let pat: PatternSyntax = ".\(raw: the_case.caseName)"
    return
      """
      case \(pat): \(raw: i)

      """
  }

  return SwitchExprSyntax(
    subject: "(\(raw: name))" as ExprSyntax,
    cases: SwitchCaseListSyntax {
      for c in casesSyntaxes { c }
    }
  )
}

func expandEquatableEnumMacroNoAssociatedValuesBody(
  cases: [(caseName: String, argLabels: [String?], isUnavailable: Bool)],
  lhsName lhs: String = "a",
  rhsName rhs: String = "b"
)
  -> CodeBlockSyntax
{
  let lhsVarName = "\(lhs)_discr";
  let rhsVarName = "\(rhs)_discr";

  let lhsSwitch = createDiscrSwitch(cases: cases, name: lhs)
  let rhsSwitch = createDiscrSwitch(cases: cases, name: rhs)

  return CodeBlockSyntax {
    """
    let \(raw: lhsVarName) = \(lhsSwitch)
    let \(raw: rhsVarName) = \(rhsSwitch)
    return \(raw: lhsVarName) == \(raw: rhsVarName)
    """
  }
}

func expandEquatableEnumMacroBody(
  cases: [(caseName: String, argLabels: [String?], isUnavailable: Bool)],
  lhsName lhs: String = "a",
  rhsName rhs: String = "b"
)
  -> CodeBlockSyntax
{
  if cases.isEmpty {
    return CodeBlockSyntax { "return true" }
  }

  if hasNoAssociatedValues(cases) {
    return expandEquatableEnumMacroNoAssociatedValuesBody(cases: cases, lhsName: lhs, rhsName: rhs)
  }

  let casesSyntaxes: [SwitchCaseSyntax] = cases.map { (caseName, argLabels, isUnavailable) in
    let lhsPat = getEnumCasePat(varPrefix: "l", caseName: caseName, argLabels: argLabels)
    let rhsPat = getEnumCasePat(varPrefix: "r", caseName: caseName, argLabels: argLabels)
    if isUnavailable {
      let casePat = getEnumCasePat(varPrefix: "l", caseName: caseName, argLabels: [])
      return """
        case (\(raw: casePat), _), (_, \(raw: casePat)):
          fatalError("unavailable code reached")
        """ as SwitchCaseSyntax
    }
    let guards: String = argLabels.enumerated().map { (i, _) in
      "l\(i) == r\(i)"
    }.joined(separator: " && ")

    let returnExpr: String = guards.isEmpty ? "true" : guards

    return "case (\(raw: lhsPat), \(raw: rhsPat)): return \(raw: returnExpr)\n"
  }

  let switchExpr = SwitchExprSyntax(
    subject: "(\(raw: lhs), \(raw: rhs))" as ExprSyntax,
    cases: SwitchCaseListSyntax {
      for c in casesSyntaxes { c }
      if casesSyntaxes.count > 1 {
        "default: return false\n" as SwitchCaseSyntax
      }
    }
  )

  return CodeBlockSyntax {
    switchExpr
  }
}
