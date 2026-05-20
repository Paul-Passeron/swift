//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

extension CodeBlockItemSyntax {
  public static func placeholderItem() -> Self {
    """
    // no-op
    """
  }
}

public struct DeriveEquatableBodyMacro: BodyMacro {

   static func compareIndicesSwitchBody(from info: EnumTypeInfo) -> String {
      info.cases.enumerated().map { (index, caseInfo) in
       return "case .\(caseInfo.name): \(index)"
     }.joined(separator: "\n")
   }

  // static func compareIndices(from info: EnumTypeInfo) -> [CodeBlockItemSyntax] {
  //   if info.cases.isEmpty {
  //     return [.placeholderItem()]
  //   }
  //
  // }

  static func deriveEnum(from info: EnumTypeInfo) -> [CodeBlockItemSyntax] {
    if info.cases.isEmpty {
      return [.placeholderItem()]
    }
    if !info.hasAssociatedValues() {
      let theSwitch = compareIndicesSwitchBody(from: info)
      return [
           """
           let a_discr = switch a {
           \(raw: theSwitch)
           }
           """,
           """
           let b_discr = switch b {
           \(raw: theSwitch)
           }
           """,
           """
           return a_discr == b_discr
           """,
      ]
    }
    let defaultCase =
    if info.cases.count > 1 {
      """
      default: return false
      """
    } else {
      ""
    }

    return [
      """
      switch (a, b) {
      \(raw: info.cases.map {
        theCase in
        """
        case (\(theCase.asPattern(varPrefix: "l").trimmedDescription), \(theCase.asPattern(varPrefix: "r").trimmedDescription)):
        \(theCase.associatedValues.enumerated().map { idx, c in
        """
        guard l\(idx) == r\(idx) else { return false }
        """
        }.joined(separator: "\n"))
        return true
        """
        }.joined(separator: "\n"))
      \(raw: defaultCase)
      }
      """ ]
  }

  static func deriveStruct(from info: StructTypeInfo) -> [CodeBlockItemSyntax] {
    info.properties.map { prop in
      return
        """
        guard a.\(raw: prop.name) == b.\(raw: prop.name) else { return false }
        """
    }
      + CollectionOfOne(
        """
        return true
        """)
  }

  public static func expansion(
    of node: AttributeSyntax,
    providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
    in context: some MacroExpansionContext
  ) throws -> [CodeBlockItemSyntax] {

    guard let args = (node.arguments?.as(LabeledExprListSyntax.self)?.map { $0 }) else {
      fatalError("Expected arguments")
    }
    guard args.count == 1, let arg = args.first else {
      fatalError("Expected one argument")
    }
    guard let strlit = arg.expression.as(StringLiteralExprSyntax.self) else {
      fatalError("Expected a string literal")
    }
    guard let info = NominalTypeInfo.from(stringLiteral: strlit) else {
      fatalError("type info argument parse error")
    }
    switch info.kind {
    case .structLike(let info):
      return deriveStruct(from: info)
    case .enumLike(let info):
      return deriveEnum(from: info)
    }
  }
}

public struct DeriveEquatableMacro: DeclarationMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    return [
      """
      @_implements(Equatable, ==(_:_:))
      @_deriveEquatableBody(\(node.arguments.first!))
      static func __derived_equals(_ a: Self, _ b: Self) -> Bool
      """
    ]
  }
}

extension CaseInfo {
  public func asPattern(varPrefix: String) -> PatternSyntax {
    if associatedValues.isEmpty {
      return
        """
        .\(raw: name)
        """
    }
    let values = associatedValues.enumerated().map {
      idx, lbl in
      if let lbl = lbl {
        return
          """
          \(lbl): let \(varPrefix)\(idx)
          """
      }
      return
        """
        let \(varPrefix)\(idx)
        """
    }.joined(separator: ", ")
    return
      """
      .\(raw: name)(\(raw: values))
      """
  }

}
