import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DeriveEquatableMacro {

  static func expandStructDecl(members: [IdentifierPatternSyntax]) -> DeclSyntax {
    """
    @_implements(Equatable, ==(_:_:))
    @EquatableStructMacro
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
    case .aStruct(let members):
      return expandStructDecl(members: members)
    case .anEnum(let cases):
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
    let hashValue: DeclSyntax =
        """
        var  hashValue: Int {
          return _hashValue(for: self)
        }
        """
    return [hashValue]
  }
}

public struct DeriveHashableHashMacro {
  static func expandDecl(derived: DerivedNominalKind) -> DeclSyntax {
    switch derived {
    case .aStruct(let members):
      return Self.expandStructDecl(members: members)
    case .anEnum(let cases):
      return Self.expandEnumDecl(isObjC: /*TODO*/ false, cases: cases)
    }
  }

  static func expandStructDecl(members: [IdentifierPatternSyntax]) -> DeclSyntax {
    """
    func hash(into hasher: inout Hasher) {
    \(raw: members.map { member in
      "    hasher.combine(self.\(member.description))"
    }.joined(separator: "\n"))
    }
    """
  }

  static func expandEnumDecl(isObjC: Bool, cases: [EnumCaseInfo]) -> DeclSyntax {
    if isObjC {
      return
        """
        func hash(into hasher: inout Hasher) {
          hasher.combine(self.rawValue)
        }
        """
    }
    return
      """
      func hash(into hasher: inout Hasher) {
        switch (self) {
        \(raw: cases.enumerated().map { (i, theCase) in
        "\(theCase.getCaseForHashableValue(idx: i))"
        }.joined(separator: "\n  "))
        }
      }
      """
  }
}

extension EnumCaseInfo {
  func getCasePattern() -> String {
    let args = argLabels.enumerated().map {(i, lbl) in
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

  func getCombineCalls(_ idx: Int) -> String {
    """
        hasher.combine(\(idx))\(
        argLabels.enumerated().map {(i, _) in
        "\n    hasher.combine(x\(i))"
      }.joined(separator: ""))
    """
  }

  func getCaseForHashableValue(idx: Int) -> String {
    if (argLabels.isEmpty) {
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
      \(getCombineCalls(idx))
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
    print(res)
    return [res]
  }
}
