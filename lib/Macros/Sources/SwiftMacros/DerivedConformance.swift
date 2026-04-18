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
  case anEnum(cases: [EnumCaseInfo], isObjC: Bool)
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

func decodeEnumExpansion(args: [LabeledExprSyntax]) -> DerivedNominalKind? {
  var cases: [ExprSyntax]? = nil
  var isObjCopt: Bool? = nil
  for arg in args {
    switch arg.label?.text {
    case "cases":
      guard cases == nil else {
        return nil
      }
      cases = arg.expression.as(ArrayExprSyntax.self)?.elements.map { $0.expression }

    case "isObjC":
      guard isObjCopt == nil else {
        return nil
      }
      isObjCopt = (arg.expression.as(BooleanLiteralExprSyntax.self)?.literal.text ?? "false") == "true"
    default: return nil
    }
  }
  guard let cases = cases else { return nil }
  let isObjC = isObjCopt ?? false
  let caseInfos: [EnumCaseInfo?] = cases.compactMap { theCase in
    guard let theCase = theCase.as(TupleExprSyntax.self) else { return nil }
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
  return DerivedNominalKind
    .anEnum(cases: caseInfos.compactMap{ $0 }, isObjC: isObjC)
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
    let args = argExpr.arguments
    switch kind {
    case "aStruct":
      guard let first = args.first else { return nil }
      guard args.count == 1 else { return nil }
      return decodeStructExpansion(arg: first)
    case "anEnum":
      return decodeEnumExpansion(args: args.map {$0})

    default:
      print("Unknown kind: \(kind)")
      return nil
    }
  default:
    print("argExpr is not a FunctionCallExprSyntax")
    return nil
  }
}

func argLabelAsStr(lbl: IdentifierPatternSyntax?) -> String {
  if let lbl = lbl { return "\"\(lbl)\"" } else { return "nil" }
}

extension EnumCaseInfo {
  func asExprSyntax() -> ExprSyntax {
    let commaSep = ", "
    let argLabelsAsStr = "[\(self.argLabels.map(argLabelAsStr).joined(separator: commaSep))]"
    return
      """
      (caseName: \(self.caseName), argLabels: \(raw: argLabelsAsStr), isUnavailable: \(raw: self.isUnavailable))
      """
  }
}

extension DerivedNominalKind {
  func asExprSyntax() -> ExprSyntax {
    switch self {
    case .aStruct(let members):
      return
        """
        .aStruct(members: [
        \(raw: members.map { member in
          "    \"\(member)\""}.joined(separator: ",\n"))
        ])
        """
    case .anEnum(let cases, let isObjC):
      return
        """
        .anEnum(cases: [
          \(raw: cases.map {$0.asExprSyntax().description}.joined(separator: ",\n  "))
        ], isObjC: \(raw: isObjC)
        """
    }
  }
}
