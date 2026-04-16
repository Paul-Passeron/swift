import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct EnumCaseInfo {
  let caseName: IdentifierPatternSyntax
  let argLabels: [IdentifierPatternSyntax?]
  let isUnavailable: Bool
}

public enum DerivedNominalKind {
  case aStruct(members: [IdentifierPatternSyntax])
  case anEnum(cases: [EnumCaseInfo])
}

public struct DeriveEquatableMacro {

  static func decodeStructExpansion(arg: LabeledExprSyntax) -> DerivedNominalKind? {
    guard arg.label?.text ?? "" == "members" else { return nil }
    guard let members = arg.expression.as(ArrayExprSyntax.self)?.elements else { return nil }
    let memberNames: [IdentifierPatternSyntax?] = members.map {
      let name = $0.expression.as(StringLiteralExprSyntax.self)
      guard let text = name?.representedLiteralValue else { return nil }
      return IdentifierPatternSyntax(identifier: "\(raw: text)")
    }
    if memberNames.contains(where: { $0 == nil }) {
      return nil
    }
    return DerivedNominalKind.aStruct(members: memberNames.compactMap({ $0 }))
  }

  static func decodeEnumExpansion(arg: LabeledExprSyntax) -> DerivedNominalKind? {
    guard arg.label?.text ?? "" == "cases" else { return nil }
    guard let cases = arg.expression.as(ArrayExprSyntax.self)?.elements else { return nil }
    let caseInfos: [EnumCaseInfo?] = cases.compactMap { theCase in
      guard let theCase = theCase.expression.as(FunctionCallExprSyntax.self) else { return nil }
      let args = theCase.arguments
      var caseName: IdentifierPatternSyntax? = nil
      var argLabels: [IdentifierPatternSyntax?]? = nil
      var isUnavailable: Bool? = nil
      for arg in args {
        switch arg.label?.text {
        case "caseName":
          if caseName != nil { return nil }
          guard
            let strLit = arg.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
          else { return nil }
          caseName = IdentifierPatternSyntax(identifier: "\(raw: strLit)")
        case "argLabels":
          if argLabels != nil { return nil }
          let lbls: [IdentifierPatternSyntax?]? = arg.expression.as(ArrayExprSyntax.self)?.elements
            .map { elem in
              if let lbl = elem.expression.as(StringLiteralExprSyntax.self) {
                guard let text = lbl.representedLiteralValue else { return nil }
                return IdentifierPatternSyntax(identifier: "\(raw: text)")
              }
              // TODO: properly check nil elements
              return nil
            }
          argLabels = lbls
        case "isUnavailable":
          if isUnavailable != nil { return nil }
          guard
            let boolLit = arg.expression.as(BooleanLiteralExprSyntax.self)?.literal.text
          else { return nil }
          isUnavailable = boolLit == "true"
        default: return nil
        }
      }
      guard let caseName = caseName else { return nil }
      guard let argLabels = argLabels else { return nil }
      guard let isUnavailable = isUnavailable else { return nil }

      return EnumCaseInfo(
        caseName: caseName, argLabels: argLabels, isUnavailable: isUnavailable)
    }
    if caseInfos.contains(where: { $0 == nil }) {
      return nil
    }
    return DerivedNominalKind.anEnum(cases: caseInfos.compactMap({ $0 }))
  }

  static func decodeExpansion(expansion: FreestandingMacroExpansionSyntax) -> DerivedNominalKind? {
    guard let arg: LabeledExprSyntax = expansion.arguments.first else { /* TODO: emit diagnostic*/
      return nil
    }
    let argExpr = arg.expression

    switch argExpr.kind {
    case .functionCallExpr:
      guard let argExpr = argExpr.as(FunctionCallExprSyntax.self) else { return nil }
      let called = argExpr.calledExpression
      guard let kind = called.as(MemberAccessExprSyntax.self)?.declName.baseName.text else {
        return nil
      }
      guard let arg = argExpr.arguments.first else { return nil }
      switch kind {
      case "aStruct":
        return decodeStructExpansion(arg: arg)
      case "anEnum":
        return decodeEnumExpansion(arg: arg)
      default: return nil
      }
    default: return nil
    }
  }

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
