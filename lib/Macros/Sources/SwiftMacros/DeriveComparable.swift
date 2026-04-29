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

  func functionPrototype(
    lhsName: String = "a",
    rhsName: String = "b",
    isResilient: Bool = false
  )
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

  func generateCompareIndices(cases: [EnumCaseInfo]) -> [CodeBlockItemSyntax] {
    if cases.isEmpty { return [] }
    let lhsVar = "\(lhsName)_discr"
    let rhsVar = "\(rhsName)_discr"
    let theSwitch = generateCompareIndicesSwitchBody(cases: cases)
    return
      [
        """
        let \(raw: lhsVar) = switch \(raw: lhsName) {
        \(raw: theSwitch)
        }
        """,
        """
        let \(raw: rhsVar) = switch \(raw: rhsName) {
        \(raw: theSwitch)
        }
        """,
        """
        return \(raw: lhsVar) < \(raw: rhsVar)
        """,
      ]
  }

  static func generateRegularSwitchCaseOneSide(
    name: String,
    theCase: EnumCaseInfo
  ) -> String {
    if theCase.argLabels.isEmpty {
      return ".\(theCase.caseName)"
    }
    let pattern = theCase.argLabels.enumerated().map { (idx, lbl) in
      let letDecl = "let \(name)\(idx)"
      return if let lbl = lbl {
        "\(lbl): \(letDecl)"
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

  func generateLessThanBody(cases: [EnumCaseInfo], isObjC: Bool, isUnsafe: Bool)
    -> [CodeBlockItemSyntax]
  {
    if cases.isEmpty { return [] }
    if hasNoAssociatedValues(cases: cases) {
      return generateCompareIndices(cases: cases)
    }
    let defaultCase =
      if cases.count > 1 {
        """
        default:
          \(generateCompareIndices(cases: cases).map { $0.description}.joined(separator: "\n"))
        """
      } else { "" }
    return [
      """
      switch (\(raw: lhsName), \(raw: rhsName)) {
      \(raw: Self.generateRegularSwitchCases(cases: cases))
      \(raw: defaultCase)
      }
      """
    ]
  }

  func expandBody() -> [CodeBlockItemSyntax]? {
    switch self.kind {
    case .equal:
      return deriveEquatableBody(self.nominalKind)
    case .lessThan:
      switch self.nominalKind {
      case .anEnum(let cases, let isObjC, let isUnsafe):
        return generateLessThanBody(
          cases: cases,
          isObjC: isObjC,
          isUnsafe: isUnsafe
        )
      default:
        return nil
      }
    default: return nil
    }

  }

  func expansionText() -> String? {
    guard
      let prototype = self.kind.functionPrototype(
        lhsName: lhsName,
        rhsName: rhsName
      )
    else {
      return nil
    }

    if self.kind == .equal {
      return
        """
        @deriveComparisonBody("==", \(self.nominalKind.asExprSyntax()))
        \(prototype)
        """
    }

    return switch self.nominalKind {
    case .anEnum:
      """
      @deriveComparisonBody("<", \(self.nominalKind.asExprSyntax()))
      \(prototype)
      """
    default: nil
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
  static func driver(of node: some FreestandingMacroExpansionSyntax)
    -> DeclSyntax?
  {
    let args = node.arguments.map { $0 }
    guard
      let comparison: ComparisonKind =
        switch args[0].expression.as(StringLiteralExprSyntax.self)?
          .representedLiteralValue
        {
        case "<": .lessThan
        case "==": .equal
        default: nil
        }
    else { return nil }
    guard let arg = decodeExpansionArg(arg: args[1].expression) else {
      return nil
    }
    let config = DeriveComparableConfig(
      nominalKind: arg,
      comparison: comparison
    )
    guard let expanded = config.expansionText() else { return nil }
    return
      """
      \(raw: expanded)
      """
  }
}

public struct DeriveComparisonBodyMacro: BodyMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingBodyFor declaration: some DeclSyntaxProtocol
      & WithOptionalCodeBlockSyntax,
    in context: some MacroExpansionContext
  ) throws -> [CodeBlockItemSyntax] {
    guard let body = driver(of: node) else { fatalError("Bad arguments") }
    return body
  }
}

extension DeriveComparisonBodyMacro {
  static func driver(of node: AttributeSyntax) -> [CodeBlockItemSyntax]? {
    guard let args = node.arguments else { return nil }
    guard
      let args =
        switch args {
        case .argumentList(let lst):
          lst.map({ $0 })
        default: nil
        }
    else { return nil }
    guard
      let comparison: ComparisonKind =
        switch args[0].expression.as(StringLiteralExprSyntax.self)?
          .representedLiteralValue
        {
        case "<": .lessThan
        case "==": .equal
        default: nil
        }
    else { return nil }
    guard let arg = decodeExpansionArg(arg: args[1].expression) else {
      return nil
    }
    let config = DeriveComparableConfig(
      nominalKind: arg,
      comparison: comparison
    )
    return config.expandBody()
  }
}

func deriveEquatableBody(_ arg: DerivedNominalKind) -> [CodeBlockItemSyntax] {
  let body =
    switch arg {
    case .aStruct(let members, isUnsafe: _):
      deriveEquatableStructBody(members.map { $0.description })
    case .anEnum(let cases, let isObjC, isUnsafe: _):
      deriveEquatableEnumBody(cases: cases, isObjC: isObjC)
    }
  return body
}

func deriveEquatableStructBody(_ members: [String]) -> [CodeBlockItemSyntax] {
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

func getDiscriminator(
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

func deriveEquatableEnumBody(cases: [EnumCaseInfo], isObjC: Bool)
  -> [CodeBlockItemSyntax]
{
  if cases.isEmpty { return [] }
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
