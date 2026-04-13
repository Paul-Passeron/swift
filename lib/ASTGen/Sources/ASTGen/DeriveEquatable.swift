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

  let casesJoined = cases.joined(separator: ", ")

  return
    """
    .\(raw: caseName)(\(raw: casesJoined))
    """
}

func expandEquatableEnumMacroBody(
  cases: [(caseName: String, argLabels: [String?], isUnavailable: Bool)],
  lhsName lhs: String = "a",
  rhsName rhs: String = "b"
)
  -> CodeBlockSyntax
{
  if cases.isEmpty {
    return CodeBlockSyntax {}
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
