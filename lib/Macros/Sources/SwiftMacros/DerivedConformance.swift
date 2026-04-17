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

func decodeStructExpansion(arg: LabeledExprSyntax) -> DerivedNominalKind? {
  guard arg.label?.text ?? "" == "members" else {
    print("Label is not members")
    return nil
  }
  guard let members = arg.expression.as(ArrayExprSyntax.self)?.elements else {
    print("Not an array expression")
    return nil
  }
  let memberNames: [IdentifierPatternSyntax?] = members.map {
    let name = $0.expression.as(StringLiteralExprSyntax.self)
    guard let text = name?.representedLiteralValue else { return nil }
    return IdentifierPatternSyntax(identifier: "\(raw: text)")
  }
  if memberNames.contains(where: { $0 == nil }) {
    print("One member was nil")
    return nil
  }
  return DerivedNominalKind.aStruct(members: memberNames.compactMap({ $0 }))
}

func decodeEnumExpansion(arg: LabeledExprSyntax) -> DerivedNominalKind? {
  guard arg.label?.text ?? "" == "cases" else { return nil }
  guard let cases = arg.expression.as(ArrayExprSyntax.self)?.elements else { return nil }
  let caseInfos: [EnumCaseInfo?] = cases.compactMap { theCase in
    guard let theCase = theCase.expression.as(TupleExprSyntax.self) else { return nil }
    let args = theCase.elements
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

func decodeExpansion(expansion: FreestandingMacroExpansionSyntax) -> DerivedNominalKind? {
  guard let arg: LabeledExprSyntax = expansion.arguments.first else { /* TODO: emit diagnostic*/
    print("No arguments")
    return nil
  }
  let argExpr = arg.expression

  switch argExpr.kind {
  case .functionCallExpr:
    guard let argExpr = argExpr.as(FunctionCallExprSyntax.self) else {
      print("argExpr is not a FunctionCallExprSyntax")
      return nil
    }
    let called = argExpr.calledExpression
    guard let kind = called.as(MemberAccessExprSyntax.self)?.declName.baseName.text else {
      print("called is not a MemberAccessExprSyntax")
      return nil
    }
    guard let arg = argExpr.arguments.first else { return nil }
    switch kind {
    case "aStruct":
      return decodeStructExpansion(arg: arg)
    case "anEnum":
      return decodeEnumExpansion(arg: arg)
    default:
      print("Unknown kind: \(kind)")
      return nil
    }
  default:
    print("argExpr is not a FunctionCallExprSyntax")
    return nil
  }
}
