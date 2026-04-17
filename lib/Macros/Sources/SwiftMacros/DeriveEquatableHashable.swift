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

public struct DeriveHashableMacro {
  static func expandDecl(derived: DerivedNominalKind) -> DeclSyntax {
    switch derived {
    case .aStruct(let members):
      return expandStructDecl(members: members)
    case .anEnum(let cases):
      return expandEnumDecl(cases: cases)
    }
  }

  static func expandStructDecl(members: [IdentifierPatternSyntax]) -> DeclSyntax {
    fatalError("TODO: DeriveHashableMacro.expandStructDecl")
  }

  static func expandEnumDecl(cases: [EnumCaseInfo]) -> DeclSyntax {
    fatalError("TODO: DeriveHashableMacro.expandEnumDecl")
  }
}

extension DeriveHashableMacro: DeclarationMacro {
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
