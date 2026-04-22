import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct EnumCaseInfo {
  let caseName: IdentifierPatternSyntax
  let argLabels: [IdentifierPatternSyntax?]
  let isUnavailable: Bool
}

// TODO: make isUnsafe member/case-wise so there are no unnecessary unsafes used
// leading to warnings

public enum DerivedNominalKind {
  case aStruct(members: [IdentifierPatternSyntax], isUnsafe: Bool)
  case anEnum(cases: [EnumCaseInfo], isObjC: Bool, isUnsafe: Bool)
}

func decodeStructExpansion(args: [LabeledExprSyntax]) -> DerivedNominalKind? {
  var members: [StringLiteralExprSyntax]? = nil
  var isUnsafeOpt: Bool? = nil

  for arg in args {
    switch arg.label?.text {
    case "members":
      guard members == nil else { return nil }
      guard let membersOpt = arg.expression.as(ArrayExprSyntax.self)?.elements else {
        return nil
      }
      members = membersOpt.map { $0.expression.as(StringLiteralExprSyntax.self)! }
    case "isUnsafe":
      guard isUnsafeOpt == nil else {
        return nil
      }
      isUnsafeOpt =
        (arg.expression.as(BooleanLiteralExprSyntax.self)?.literal.text ?? "false") == "true"
    default: return nil
    }
  }
  guard let members = members else { return nil }
  let memberNames: [IdentifierPatternSyntax?] = members.map {
    guard let text = $0.representedLiteralValue else { return nil }
    return IdentifierPatternSyntax(identifier: "\(raw: text)")
  }
  if memberNames.contains(where: { $0 == nil }) { return nil }
  let isUnsafe = isUnsafeOpt ?? false
  return DerivedNominalKind.aStruct(members: memberNames.compactMap { $0 }, isUnsafe: isUnsafe)
}

func decodeEnumExpansion(args: [LabeledExprSyntax]) -> DerivedNominalKind? {
  var cases: [ExprSyntax]? = nil
  var isObjCopt: Bool? = nil
  var isUnsafeOpt: Bool? = nil
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
      isObjCopt =
        (arg.expression.as(BooleanLiteralExprSyntax.self)?.literal.text ?? "false") == "true"
    case "isUnsafe":
      guard isUnsafeOpt == nil else {
        return nil
      }
      isUnsafeOpt =
        (arg.expression.as(BooleanLiteralExprSyntax.self)?.literal.text ?? "false") == "true"
    default: return nil
    }
  }
  guard let cases = cases else { return nil }
  let isObjC = isObjCopt ?? false
  let isUnsafe = isUnsafeOpt ?? false

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
  return
    DerivedNominalKind
    .anEnum(
      cases: caseInfos.compactMap {
        $0
      },
      isObjC: isObjC,
      isUnsafe: isUnsafe)
}

func decodeExpansionArg(arg: ExprSyntax) -> DerivedNominalKind? {
  switch arg.kind {
  case .functionCallExpr:
    guard let argExpr = arg.as(FunctionCallExprSyntax.self) else { return nil }
    let called = argExpr.calledExpression
    guard let kind = called.as(MemberAccessExprSyntax.self)?.declName.baseName.text else {
      return nil
    }
    let args = argExpr.arguments
    switch kind {
    case "aStruct": return decodeStructExpansion(args: args.map { $0 })
    case "anEnum": return decodeEnumExpansion(args: args.map { $0 })
    default: return nil
    }
  default: return nil
  }
}

func decodeExpansion(expansion: FreestandingMacroExpansionSyntax) -> DerivedNominalKind? {
  guard let arg: LabeledExprSyntax = expansion.arguments.first else {
    /* TODO: emit diagnostic*/
    return nil
  }
  return decodeExpansionArg(arg: arg.expression)
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
    case .aStruct(let members, let isUnsafe):
      return
        """
        .aStruct(members: [
        \(raw: members.map { member in
          "    \"\(member)\""}.joined(separator: ",\n"))
        ], isUnsafe: \(raw: isUnsafe))
        """
    case .anEnum(let cases, let isObjC, let isUnsafe):
      return
        """
        .anEnum(cases: [
          \(raw: cases.map {$0.asExprSyntax().description}.joined(separator: ",\n  "))
        ], isObjC: \(raw: isObjC) , isUnsafe: \(raw: isUnsafe))
        """
    }
  }
}

func hasNoAssociatedValues(cases: [EnumCaseInfo]) -> Bool {
  return cases.allSatisfy { $0.argLabels.isEmpty }
}

func hasUnavailableValues(cases: [EnumCaseInfo]) -> Bool {
  return cases.contains { $0.isUnavailable }
}
