import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public enum ComparisonKind {
  case equal
  case notEqual
  case lessThan
  case lessThanOrEqual
  case greaterThan
  case greaterThanOrEqual
}

extension ComparisonKind {
  func not() -> Self {
    switch self {
    case .equal: .notEqual
    case .greaterThan: .lessThanOrEqual
    case .greaterThanOrEqual: .lessThan
    case .lessThan: .greaterThanOrEqual
    case .lessThanOrEqual: .greaterThan
    case .notEqual: .equal
    }
  }

  func symbol() -> String {
    switch self {
    case .equal: "=="
    case .notEqual: "!="
    case .lessThan: "<"
    case .lessThanOrEqual: "<="
    case .greaterThan: ">"
    case .greaterThanOrEqual: ">="
    }
  }

  func resilientName() -> String? {
    switch self {
    case .equal: "__derived_equals"
    case .lessThan: "__derived_enum_less_than"
    default: nil
    }
  }

  func protocolName() -> String? {
    switch self {
    case .equal: "Equatable"
    case .lessThan: "Comparable"
    default: nil
    }
  }

  func functionPrototype(lhsName: String = "a", rhsName: String = "b", isResilient: Bool = false)
    -> String?
  {
    guard let resilientName = resilientName() else { return nil }
    guard let protocolName = protocolName() else { return nil }
    let symb = symbol()
    let prologue =
      if isResilient {
        symb
      } else {
        """
        @_implements(\(protocolName), \(symb)(_:_:))
        static func \(resilientName)
        """
      }
    return
      """
      \(prologue)(_ \(lhsName): Self, _ \(rhsName): Self) -> Bool
      """
  }
}

public struct DeriveComparableConfig {
  public let kind: ComparisonKind
  public let lhsName: String = "a"
  public let rhsName: String = "b"
  public let nominalKind: DerivedNominalKind

  public init(nominalKind: DerivedNominalKind, comparison: ComparisonKind) {
    self.kind = comparison
    self.nominalKind = nominalKind
  }
}

extension DeriveComparableConfig {

  func generateCompareIndicesSwitchBody(cases: [EnumCaseInfo]) -> String {
    let cases: [String] = cases.enumerated().map { (idx, theCase) in
      return "case .\(theCase.caseName): \(idx)"
    }
    return
      """
      \(cases.joined(separator: "\n"))
      """
  }

  func generateCompareIndices(cases: [EnumCaseInfo]) -> String {
    if cases.isEmpty { return "" }
    let lhsVar = "\(lhsName)_discr"
    let rhsVar = "\(rhsName)_discr"
    let theSwitch = generateCompareIndicesSwitchBody(cases: cases)
    return
      """
      let \(lhsVar) = switch \(lhsName) {
      \(theSwitch)
      }
      let \(rhsVar) = switch \(rhsName) {
      \(theSwitch)
      }
      return \(lhsVar) < \(rhsVar)
      """
  }

  static func hasNoAssociatedValues(cases: [EnumCaseInfo]) -> Bool {
    return cases.allSatisfy { $0.argLabels.isEmpty }
  }

  static func generateRegularSwitchCaseOneSide(name: String, theCase: EnumCaseInfo) -> String {
    if theCase.argLabels.isEmpty {
      return ".\(theCase.caseName)"
    }
    let pattern = theCase.argLabels.enumerated().map { (idx, lbl) in
      let letDecl = "let \(name)\(idx)"
      return if let lbl = lbl {
        "\(letDecl): \(lbl)"
      } else {
        letDecl
      }
    }.joined(separator: ", ")
    return ".\(theCase.caseName)(\(pattern))"
  }

  static func generateRegularSwitchGuards(theCase: EnumCaseInfo) -> String {
    if theCase.isUnavailable {
      return
        """
        fatalError("unavailable case")
        """
    }
    return """
      \(theCase.argLabels.enumerated().map { (idx, _) in
      let lhsVar = "l\(idx)"
      let rhsVar = "r\(idx)"
      return "guard \(lhsVar) >= \(rhsVar) else { return true }"
      }.joined(separator: "\n"))
      return false
      """
  }

  static func generateRegularSwitchCase(_ theCase: EnumCaseInfo) -> String {
    let lhsPat = generateRegularSwitchCaseOneSide(name: "l", theCase: theCase)
    let rhsPat = generateRegularSwitchCaseOneSide(name: "r", theCase: theCase)
    return
      """
      case (\(lhsPat), \(rhsPat)):
      \(generateRegularSwitchGuards(theCase: theCase))
      """
  }

  static func generateRegularSwitchCases(cases: [EnumCaseInfo]) -> String {
    cases.map { Self.generateRegularSwitchCase($0) }.joined(separator: "\n")
  }

  func generateLessThanBody(cases: [EnumCaseInfo], isObjC: Bool, isUnsafe: Bool) -> String {
    if cases.isEmpty { return "" }
    if Self.hasNoAssociatedValues(cases: cases) {
      return generateCompareIndices(cases: cases)
    }
    let defaultCase =
      if cases.count > 1 {
        """
        default:
          \(generateCompareIndices(cases: cases))
        """
      } else { "" }
    return
      """
      switch (\(lhsName), \(rhsName)) {
      \(Self.generateRegularSwitchCases(cases: cases))
      \(defaultCase)
      }
      """
  }

  func expansionText() -> String? {
    guard let prototype = self.kind.functionPrototype(lhsName: lhsName, rhsName: rhsName) else {
      return nil
    }

    if self.kind == .equal {
      return switch self.nominalKind {
      case .aStruct:
        """
        @EquatableStructMacro
        \(prototype)
        """
      case .anEnum:
        """
        @EquatableEnumMacro
        \(prototype)
        """
      }

    }

    switch self.nominalKind {
    case .anEnum(let cases, let isObjC, let isUnsafe):
      let body = generateLessThanBody(
        cases: cases, isObjC: isObjC, isUnsafe: isUnsafe)
      return
        """
        \(prototype) {
          \(body)
        }
        """
    default:
      return nil
    }
  }
}

public struct DeriveComparisonMacro: DeclarationMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let decl = driver(of: node) else { fatalError("Bad arguments") }
    return [decl]
  }
}

extension DeriveComparisonMacro {
  static func driver(of node: some FreestandingMacroExpansionSyntax) -> DeclSyntax? {
    let args = node.arguments.map { $0 }
    guard
      let comparison: ComparisonKind =
        switch args[0].expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
        case "<": .lessThan
        case "==": .equal
        default: nil
        }
    else { return nil }
    guard let arg = decodeExpansionArg(arg: args[1].expression) else { return nil }
    let config = DeriveComparableConfig(nominalKind: arg, comparison: comparison)
    guard let expanded = config.expansionText() else { return nil }
    return
      """
      \(raw: expanded)
      """
  }
}
