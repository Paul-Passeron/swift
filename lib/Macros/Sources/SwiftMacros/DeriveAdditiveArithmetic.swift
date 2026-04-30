import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// +(_:_:)
// -(_:_:)
// zero

enum Requirement {
  case add
  case sub
  case zero
}

extension Requirement {
  var operatorName: String {
    switch self {
    case .add: return "+"
    case .sub: return "-"
    case .zero: return "zero"
    }
  }

  init?(stringValue: String) {
    switch stringValue {
    case "+": self = .add
    case "-": self = .sub
    case "zero": self = .zero
    default: return nil
    }
  }

  func getInitializerForMember(member: String) -> String {
    switch self {
    case .add, .sub:
      return "a.\(member) \(operatorName) b.\(member)"
    case .zero: return ".zero"
    }
  }
}

struct ArithmeticDerive {
  let req: Requirement
  let properties: [String]
}

extension ArithmeticDerive {
  func deriveRequirementDecl() -> String {
    switch req {
    case .add, .sub:
      return "static func \(req.operatorName)(_ a: Self, _ b: Self) -> Self"
    case .zero:
      return "static var zero: Self"
    }
  }

  func deriveRequirementBody() -> String {
    return
      """
      Self.init(\(properties.map { prop in "\(prop): \(req.getInitializerForMember(member: prop))"}.joined(separator: ", ")))
      """
  }

  func derive() -> String {
    let decl = deriveRequirementDecl()
    let prologue = ""
    let body =
      switch req {
      case .add, .sub:
        """
        {
          \(deriveRequirementBody())
        }
        """
      case .zero:
        """
        {
          get {
            \(deriveRequirementBody())
          }
        }
        """
      }
    return
      """
      \(prologue)
      \(decl)
      \(body)
      """
  }
}

public struct DeriveAdditiveArithmeticMacro: DeclarationMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    let args = node.arguments.map { $0 }
    guard args.count == 2 else { fatalError("Expected 2 arguments") }
    guard
      let strLitVal = args[0].expression.as(StringLiteralExprSyntax.self)?
        .representedLiteralValue,
      let req = Requirement(
        stringValue: strLitVal
      )
    else { fatalError("Expected strlit +, - or zero as first arg") }
    guard
      let properties = args[1].expression.as(ArrayExprSyntax.self)?.elements
        .map({
          elem in
          elem.expression.as(StringLiteralExprSyntax.self)?
            .representedLiteralValue ?? ""
        })
    else {
      fatalError("Could not parse properties list")
    }
    if properties.contains("") {
      fatalError("Invalid property")
    }
    let der = ArithmeticDerive(req: req, properties: properties)
    let d: DeclSyntax = "\(raw: der.derive())"
    return [d]
  }

}
