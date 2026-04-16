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
    return CodeBlockSyntax {}
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

func expandEquatableDeclMacroBody(isNotStruct isEnum: Bool) -> FunctionDeclSyntax {
  let signature = FunctionSignatureSyntax(
    parameterClause: FunctionParameterClauseSyntax {
      "_ a: Self, _ b: Self"
    },
    returnClause: ReturnClauseSyntax(type: IdentifierTypeSyntax(name: "Bool"))
  )
  let equatable_attr =
    if isEnum {
      "@EquatableEnumMacro\n" as AttributeSyntax
    } else {
      "@EquatableStructMacro\n" as AttributeSyntax
    }
  let attributes: [AttributeSyntax] = [
    "@_implements(Equatable, ==(_:_:))\n" as AttributeSyntax,
    equatable_attr,
  ]
  return FunctionDeclSyntax(
    attributes: AttributeListSyntax {
      for a in attributes { a }
    },
    modifiers: DeclModifierListSyntax { [DeclModifierSyntax(name: .identifier(" static "))] },
    name: .identifier(" __derived_equals"),
    signature: signature,
  )
}

func stringToBuffer(
  _ str: String,
  outBufferPtr: UnsafeMutablePointer<UnsafePointer<CChar>?>,
  outBufferLen: UnsafeMutablePointer<Int>
) {
  let buffer = UnsafeMutableRawPointer.allocate(byteCount: str.utf8.count + 1, alignment: 8)
  str.withCString({
    buffer.copyMemory(from: $0, byteCount: str.utf8.count + 1)
  })
  outBufferPtr.initialize(to: UnsafeRawPointer(buffer).assumingMemoryBound(to: CChar.self))
  outBufferLen.initialize(to: str.utf8.count)
}

@_cdecl("swift_ASTGen_expandEquatableStructMacro")
public func expandEquatableStructMacro(
  propertyNamesPtr: UnsafePointer<UnsafePointer<CChar>?>,
  count: Int,
  outBufferPtr: UnsafeMutablePointer<UnsafePointer<CChar>?>,
  outBufferLen: UnsafeMutablePointer<Int>
) -> Bool {
  let names = (0..<count).compactMap {
    propertyNamesPtr[$0].map { String(cString: $0) }
  }
  let syntax = expandEquatableStructMacroBody(propertyNames: names)
  let text = syntax.description
  stringToBuffer(text, outBufferPtr: outBufferPtr, outBufferLen: outBufferLen)
  return true
}

public struct EnumCaseInfo {
  let caseName: UnsafePointer<CChar>
  let argLabels: UnsafePointer<UnsafePointer<CChar>?>
  let argCount: Int
  let isUnavailable: Bool
}

@_cdecl("swift_ASTGen_expandEquatableEnumMacro")
public func expandEquatableEnumMacro(
  caseInfos: UnsafeRawPointer,
  caseCount: Int,
  outBufferPtr: UnsafeMutablePointer<UnsafePointer<CChar>?>,
  outBufferLen: UnsafeMutablePointer<Int>
) -> Bool {
  let caseInfos = caseInfos.assumingMemoryBound(to: EnumCaseInfo.self)
  let cases = (0..<caseCount).map { idx in
    let infos = caseInfos[idx]
    let labels: [String?] = (0..<Int(infos.argCount)).map { lblIdx in
      let lbl = infos.argLabels[lblIdx]
      return lbl.map { String.init(cString: $0) }
    }
    return (caseName: String(cString: infos.caseName), argLabels: labels, isUnavailable: infos.isUnavailable)
  }
  let syntax = expandEquatableEnumMacroBody(cases: cases)
  let text = syntax.description
  stringToBuffer(text, outBufferPtr: outBufferPtr, outBufferLen: outBufferLen)
  return true
}

@_cdecl("swift_ASTGen_expandEquatableDeclMacro")
public func expandEquatableDeclMacro(
  isNotStruct isEnum: Bool,
  outBufferPtr: UnsafeMutablePointer<UnsafePointer<CChar>?>,
  outBufferLen: UnsafeMutablePointer<Int>
) -> Bool {
  let syntax = expandEquatableDeclMacroBody(isNotStruct: isEnum)
  let text = syntax.description
  stringToBuffer(text, outBufferPtr: outBufferPtr, outBufferLen: outBufferLen)
  return true
}
