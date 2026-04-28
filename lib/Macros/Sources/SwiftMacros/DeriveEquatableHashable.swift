import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DeriveEquatableMacro {

  static func expandStructDecl(
    members: [IdentifierPatternSyntax],
    desc: DerivedNominalKind
  )
    -> DeclSyntax
  {
    """
    @_implements(Equatable, ==(_:_:))
    @deriveEquatableBody(\(desc.asExprSyntax()))
    static func __derived_equals(_ a: Self, _ b: Self) -> Bool
    """
  }

  static func expandEnumDecl(cases: [EnumCaseInfo]) -> DeclSyntax {
    """
    @_implements(Equatable, ==(_:_:))
    @EquatableEnumMacro
    static func __derived_equals(_ a: Self, _ b: Self) -> Bool
    """
  }

  static func expandDecl(derived: DerivedNominalKind) -> DeclSyntax {
    switch derived {
    case .aStruct(let members, isUnsafe: _):
      return expandStructDecl(members: members, desc: derived)
    case .anEnum(let cases, isObjC: _, isUnsafe: _):
      return expandEnumDecl(cases: cases)
    }
  }
}

extension DeriveEquatableMacro: DeclarationMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let arg = decodeExpansion(expansion: node) else {
      fatalError("Could not decode expansion")
    }
    return [expandDecl(derived: arg)]
  }
}

public struct DeriveHashableHashValueMacro {}

extension DeriveHashableHashValueMacro: DeclarationMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let arg = decodeExpansion(expansion: node) else {
      fatalError("Could not decode expansion")
    }
    switch arg {
    case .aStruct(members: _, let isUnsafe) where isUnsafe,
      .anEnum(cases: _, isObjC: _, let isUnsafe)
    where isUnsafe:
      let hashValue: DeclSyntax =
        """
        var  hashValue: Int {
          return unsafe _hashValue(for: self)
        }
        """
      return [hashValue]
    default:
      let hashValue: DeclSyntax =
        """
        var  hashValue: Int {
          return _hashValue(for: self)
        }
        """
      return [hashValue]
    }

  }
}

func expandHashableHashStructBody(
  members: [IdentifierPatternSyntax],
  isUnsafe: Bool
) -> [CodeBlockItemSyntax] {
  let unsafePrologue =
    if isUnsafe {
      "unsafe "
    } else {
      ""
    }
  return members.map { member in
    """
    \(raw: unsafePrologue)hasher.combine(self.\(raw: member.description))
    """
  }
}

func expandHashableHashEnumBody(
  isObjC: Bool,
  cases: [EnumCaseInfo],
  isUnsafe: Bool
) -> [CodeBlockItemSyntax] {
  if isObjC {
    return [
      """
      hasher.combine(self.rawValue)
      """
    ]
  }

  return
    [
      """
      switch (self) {
      \(raw: cases.enumerated().map {
        "\($0.1.getCaseForHashableValue(idx: $0.0, isUnsafe: isUnsafe))"
      }.joined(separator: "\n"))
      }
      """
    ]

}
//
//func expandHashableHashStructDecl(
//  members: [IdentifierPatternSyntax],
//  isUnsafe: Bool
//) -> DeclSyntax {
//  """
//  func hash(into hasher: inout Hasher) {
//  \(raw: members.map { member in
//    if isUnsafe {
//      return "    unsafe hasher.combine(self.\(member.description))"
//    } else {
//      return "    hasher.combine(self.\(member.description))"
//    }
//  }.joined(separator: "\n"))
//  }
//  """
//}
//
//func expandHashableHashEnumDecl(
//  isObjC: Bool,
//  cases: [EnumCaseInfo],
//  isUnsafe: Bool
//) -> DeclSyntax {
//  if isObjC {
//    return
//      """
//      func hash(into hasher: inout Hasher) {
//        hasher.combine(self.rawValue)
//      }
//      """
//  }
//  return
//    """
//    func hash(into hasher: inout Hasher) {
//      switch (self) {
//      \(raw: cases.enumerated().map { (i, theCase) in
//        "\(theCase.getCaseForHashableValue(idx: i, isUnsafe: isUnsafe))"
//      }.joined(separator: "\n  "))
//      }
//    }
//    """
//}

public struct DeriveHashableHashMacro {
  static func expandDecl(derived: DerivedNominalKind) -> DeclSyntax {
    //    switch derived {
    //    case .aStruct(let members, let isUnsafe):
    //      return expandHashableHashStructDecl(members: members, isUnsafe: isUnsafe)
    //    case .anEnum(let cases, let isObjC, let isUnsafe):
    //      return expandHashableHashEnumDecl(
    //        isObjC: isObjC,
    //        cases: cases,
    //        isUnsafe: isUnsafe
    //      )
    //    }

    return
      """
      @deriveHashableHashBody(\(derived.asExprSyntax()))
      func hash(into hasher: inout Hasher)
      """
  }
}

extension EnumCaseInfo {
  func getCasePattern() -> String {
    let args = argLabels.enumerated().map { (i, lbl) in
      let varDecl = "let x\(i)"
      if let lbl = lbl {
        return "\(lbl): \(varDecl)"
      } else {
        return varDecl
      }
    }.joined(separator: ", ")
    return
      """
      .\(caseName)(\(args))
      """
  }

  func getCombineCalls(_ idx: Int, _ isUnsafe: Bool) -> String {
    if isUnsafe {
      return
        """
            hasher.combine(\(idx))\(
              argLabels.enumerated().map {(i, _) in
              "\n    unsafe hasher.combine(x\(i))"
            }.joined(separator: ""))
        """
    } else {
      return
        """
            hasher.combine(\(idx))\(
              argLabels.enumerated().map {(i, _) in
              "\n    hasher.combine(x\(i))"
            }.joined(separator: ""))
        """
    }
  }

  func getCaseForHashableValue(idx: Int, isUnsafe: Bool) -> String {
    if argLabels.isEmpty {
      return "case .\(caseName):\n    hasher.combine(\(idx))"
    }
    if isUnavailable {
      return
        """
          case .\(caseName):
            fatalError("unreachable")
        """
    }
    return
      """
      case \(getCasePattern()):
      \(getCombineCalls(idx, isUnsafe))
      """
  }
}

extension DeriveHashableHashMacro: DeclarationMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let arg = decodeExpansion(expansion: node) else {
      fatalError("Could not decode expansion")
    }
    let res = Self.expandDecl(derived: arg)
    return [res]
  }
}

public struct DeriveEquatableBodyMacro: BodyMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingBodyFor declaration: some DeclSyntaxProtocol
      & WithOptionalCodeBlockSyntax,
    in context: some MacroExpansionContext
  ) throws -> [CodeBlockItemSyntax] {
    guard let args = node.arguments else {
      fatalError("Internal error: Should have been arguments there !")
    }
    let arg: ExprSyntax =
      """
      \(args)
      """
    guard let arg = decodeExpansionArg(arg: arg) else {
      fatalError(
        "Internal error: Could not decode expansion arg:\n\(arg.description)\n\n\(arg)"
      )
    }
    return deriveBody(arg)
  }
}

extension DeriveEquatableBodyMacro {
  static func deriveBody(_ arg: DerivedNominalKind) -> [CodeBlockItemSyntax] {
    let body =
      switch arg {
      case .aStruct(let members, isUnsafe: _):
        deriveStructBody(members.map { $0.description })
      case .anEnum(let cases, let isObjC, isUnsafe: _):
        deriveEnumBody(cases: cases, isObjC: isObjC)
      }
    return body
  }

  static func deriveStructBody(_ members: [String]) -> [CodeBlockItemSyntax] {
    members.map {
      """
      guard a.\(raw: $0) == b.\(raw: $0) else { return false }
      """
    } + [
      """
      return true
      """
    ]
  }

  static func getDiscriminator(
    varName: String,
    scrutinee: String,
    caseNames: [String]
  )
    -> CodeBlockItemSyntax
  {
    return
      """
      let \(raw: varName) = switch \(raw: scrutinee) {
      \(raw: caseNames.enumerated().map { idx, caseName in "case .\(caseName): \(idx)" }.joined(separator: "\n"))
      }
      """
  }

  static func deriveEnumBody(cases: [EnumCaseInfo], isObjC: Bool)
    -> [CodeBlockItemSyntax]
  {
    let hasNoAssociatedValues = cases.allSatisfy { $0.argLabels.isEmpty }
    if hasNoAssociatedValues {
      let caseNames = cases.map { $0.caseName.description }
      return [
        getDiscriminator(
          varName: "__a_discr",
          scrutinee: "a",
          caseNames: caseNames
        ),
        getDiscriminator(
          varName: "__b_discr",
          scrutinee: "b",
          caseNames: caseNames
        ),
        """
        return __a_discr == __b_discr
        """,
      ]
    } else {
      let defaultCase =
        if cases.count > 1 {
          """
          default: return false
          """
        } else {
          ""
        }
      let switchStmt = """
        switch (a, b) {
        \(raw: cases.map {
        theCase in
        """
        case (\(theCase.asPattern(varPrefix: "l")), \(theCase.asPattern(varPrefix: "r"))):
        \(theCase.argLabels.enumerated().map { idx, c in
        """
        guard l\(idx) == r\(idx) else { return false }
        """
        }.joined(separator: "\n"))
        return true
        """
        }.joined(separator: "\n"))
        \(raw: defaultCase)
        }
        """ as CodeBlockItemSyntax
      return [switchStmt]
    }
  }
}

extension EnumCaseInfo {
  func asPattern(varPrefix: String) -> String {
    if argLabels.isEmpty {
      return ".\(caseName.description)"
    } else {
      let elems = argLabels.enumerated().map {
        idx,
        lbl in
        if let lbl = lbl {
          return "\(lbl): let \(varPrefix)\(idx)"
        } else {
          return "let \(varPrefix)\(idx)"
        }
      }.joined(separator: ", ")
      return ".\(caseName.description)(\(elems))"
    }
  }
}

public struct DeriveHashableHashBodyMacro: BodyMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingBodyFor declaration: some DeclSyntaxProtocol
      & WithOptionalCodeBlockSyntax,
    in context: some MacroExpansionContext
  ) throws -> [CodeBlockItemSyntax] {
    guard let args = node.arguments else {
      fatalError("Internal error: Should have been arguments there !")
    }
    let arg: ExprSyntax =
      """
      \(args)
      """
    guard let arg = decodeExpansionArg(arg: arg) else {
      fatalError(
        "Internal error: Could not decode expansion arg:\n\(arg.description)\n\n\(arg)"
      )
    }
    switch arg {
    case .aStruct(let members, let isUnsafe):
      return expandHashableHashStructBody(members: members, isUnsafe: isUnsafe)
    case .anEnum(let cases, let isObjC, let isUnsafe):
      return expandHashableHashEnumBody(
        isObjC: isObjC,
        cases: cases,
        isUnsafe: isUnsafe
      )
    }
  }
}
