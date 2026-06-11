//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DeriveEquatableMacro: DeclarationMacro {

  var infos: NominalTypeInfo
  var isResilient: Bool
  var reachability: [Bool]?

  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    let (typeInfo, isResilient, reachability) = try node.arguments.expect(
      .typeInfoFromString(),
      .boolArg("isResilient"),
      .boolArg("reachability").toArr().toOpt()
    )
    return [
      Self(infos: typeInfo, isResilient: isResilient, reachability: reachability).deriveEquatable()
    ]
  }

  func deriveEquatable() -> DeclSyntax {
    return
      """
      \(getAttributes())
      static func \(getFunctionName())(_ a: Self, _ b: Self) -> Bool {
        \(getBody())
      }
      """
  }

  func getAttributes() -> AttributeListSyntax {
    if isResilient {
      return ""
    } else {
      let semantics: String
      switch infos.kind {
      case .enumLike(_):
        semantics = "@_semantics(\"derived_enum_equals\")"
      default:
        semantics = ""
      }
      return
        """
        \(raw: semantics)
        @_implements(Equatable, ==(_:_:))
        """
    }
  }

  func getFunctionName() -> TokenSyntax {
    if isResilient {
      return "=="
    }
    switch infos.kind {
    case .enumLike(_):
      return "__derived_enum_equals"
    case .structLike(_):
      return "__derived_struct_equals"
    }
  }

  func getBody() -> CodeBlockItemListSyntax {
    switch infos.kind {
    case .enumLike(let enumInfos):
      Self.getEnumBody(enumInfos, self.reachability!)
    case .structLike(let structInfos):
      Self.getStructBody(structInfos)
    }
  }

  static func getStructBody(_ structInfos: StructTypeInfo)
    -> CodeBlockItemListSyntax
  {

    let guards: [CodeBlockItemSyntax] = structInfos.properties.map {
      property in
      """
      guard a.\(raw: property.name) == b.\(raw: property.name) else {
        return false
      }
      """
    }

    return .init(guards + ["\nreturn true"])
  }

  static func getEnumBody(_ enumInfos: EnumTypeInfo, _ reachable: [Bool]) -> CodeBlockItemListSyntax
  {
    if enumInfos.isUninhabited() {
      return getUninhabitedBody()
    }
    if enumInfos.hasNoAssociatedValues() {
      return getNoAssociatedValuesBody(enumInfos, reachable)
    }
    return getHasAssociatedValuesBody(enumInfos, reachable)
  }

  static func getUninhabitedBody() -> CodeBlockItemListSyntax {
    """
    """
  }

  static func getUnreachableStatement() -> CodeBlockItemSyntax {
    """
    fatalError("Unavailable code reached")
    """
  }

  static func getDiscriminant(
    _ enumInfos: EnumTypeInfo,
    _ reachable: [Bool],
    scrutinee: String,
    discrName: String
  )
    -> CodeBlockItemListSyntax
  {
    /// TODO: handle unavailable cases
    let cases: [String] = enumInfos.cases.enumerated().map {
      i,
      infos in
      if reachable[i] {
        """
        case .\(infos.name): 
          \(discrName) = \(i)
        """
      } else {
        """
        case .\(infos.name):
          \(getUnreachableStatement())
        """
      }
    }

    return
      """
      var \(raw: discrName): Int
      switch \(raw: scrutinee) {
      \(raw: cases.joined(separator: "\n"))
      }
      """
  }

  static func getNoAssociatedValuesBody(
    _ enumInfos: EnumTypeInfo,
    _ reachable: [Bool]
  ) -> CodeBlockItemListSyntax {
    var items = getDiscriminant(enumInfos, reachable, scrutinee: "a", discrName: "index_a")
    items += getDiscriminant(enumInfos, reachable, scrutinee: "b", discrName: "index_b")
    items += ["return index_a == index_b"]
    return items
  }

  static func getEnumElementPayloadPattern(
    _ elt: CaseInfo,
    varPrefix: String,
    _ reachable: Bool
  ) -> PatternSyntax {
    if elt.associatedValues.isEmpty || !reachable {
      return ".\(raw: elt.name)"
    }

    let vars: [String] = elt.associatedValues.enumerated().map {
      i,
      name in
      let prefix =
        if let name = name {
          "\(name): "
        } else { "" }
      return "\(prefix)let \(varPrefix)\(i)"
    }

    return ".\(raw: elt.name)(\(raw: vars.joined(separator: ", ")))"

  }

  static func getHasAssociatedValuesBody(
    _ enumInfos: EnumTypeInfo,
    _ reachable: [Bool]
  ) -> CodeBlockItemListSyntax {

    var cases: [SwitchCaseSyntax] = []
    for (idx, elt) in enumInfos.cases.enumerated() {
      var stmtsInCase: [CodeBlockItemSyntax] = []

      if reachable[idx] {

        for i in 0..<elt.associatedValues.count {
          stmtsInCase.append(
            """
            guard l\(raw: i) == r\(raw: i) else {
              return false
            }
            """
          )
        }

        stmtsInCase.append("return true")
      } else {
        stmtsInCase.append(getUnreachableStatement())
      }
      let lPat = getEnumElementPayloadPattern(elt, varPrefix: "l", reachable[idx])
      let rPat = getEnumElementPayloadPattern(elt, varPrefix: "r", reachable[idx])

      let thisCase: SwitchCaseSyntax =
        """
        case (\(lPat), \(rPat)): 
          \(CodeBlockItemListSyntax(stmtsInCase))
        """
      cases.append(thisCase)
    }

    if enumInfos.cases.count > 1 {
      cases.append(
        """
        default: return false
        """
      )
    }

    return
      """
      switch (a, b) {
      \(raw: cases.map { $0.trimmedDescription }.joined(separator: "\n"))
      }
      """
  }
}

extension EnumTypeInfo {
  func hasNoAssociatedValues() -> Bool {
    cases.allSatisfy(\.associatedValues.isEmpty)
  }

  func isUninhabited() -> Bool {
    cases.isEmpty
  }
}
