import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct StoredProperty {

  public enum Introducer {
    case `var`
    case `let`

    var asString: String {
      switch self {
      case .var: "var"
      case .let: "let"
      }
    }
  }

  public var name: String = ""
  public var typeName: String = ""
  public var conformances: [String] = []
  public var introducer: Introducer = .var
  public var isStatic: Bool = true
}

public struct DiffTypeInfo {
  let storedProperties: [StoredProperty]
  let conformances: [String]
}

func getStatic(_ isStatic: Bool) -> String {
  if isStatic { "static " } else { "" }
}

func deriveTangentVector(properties: [StoredProperty], conformances: [String])
  -> String
{
  let prologue =
    """
    struct TangentVector: \(conformances.joined(separator: ", ")) {
    	typealias TangentVector = Self
    """
  let epilogue =
    """
    }
    """
  let body = properties.map { prop in
    """
    \(getStatic(prop.isStatic))\(prop.introducer.asString) \(prop.name): \(prop.typeName)
    """
  }.joined(separator: "\n")
  return
    """
    \(prologue)
    	\(body)
    \(epilogue)
    """
}

extension Sequence {
  @inlinable public func tryMap<T>(_ transform: (Element) throws -> T?) rethrows -> [T]? {
    var res: [T] = []
    for elem in self {
      guard let val = (try transform(elem)) else { return nil }
      res.append(val)
    }
    return res
  }
}

public struct ArgParser {
  public static func parse(properties: ExprSyntax, conformances: ExprSyntax) -> DiffTypeInfo? {
    guard let props = properties.as(ArrayExprSyntax.self) else { return nil }
    let elems = props.elements.map { $0.expression }
    guard let parsed_props = (elems.tryMap { Self.parse_property(prop: $0) }) else {
      print("parsed props error")
      return nil
    }
    guard let confs = conformances.as(ArrayExprSyntax.self) else {
      print("confs as error")
      return nil
    }
    guard
      let parsed_confs = confs.elements.map({ $0.expression }).tryMap({
        $0.as(StringLiteralExprSyntax.self)?.representedLiteralValue
      })
    else {
      print("parsed_confs error")
      return nil
    }

    return DiffTypeInfo(storedProperties: parsed_props, conformances: parsed_confs)
  }

  static func parse_property(prop: ExprSyntax) -> StoredProperty? {
    guard let fcall = prop.as(FunctionCallExprSyntax.self) else {
      print("Not a funcall")
      return nil
    }
    guard fcall.calledExpression.trimmedDescription == "StoredProperty" else {
      print("Not stored property")
      return nil
    }
    var seen: Set<String> = []
    let expected: Set<String> = [
      "name",
      "typeName",
      "introducer",
      "isStatic",
    ]

    var res = StoredProperty()
    for arg in fcall.arguments {
      guard let name = arg.label?.text else { return nil }
      guard seen.insert(name).inserted else {
        print("duplicate name \(name)")
        return nil
      }
      switch name {
      case "name":
        guard let strlit = arg.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        else {

          return nil
        }
        res.name = strlit
      case "typeName":
        guard let strlit = arg.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        else { return nil }
        res.typeName = strlit
      case "introducer":
        switch arg.expression.description {
        case ".var", ".`var`":
          res.introducer = .var
        case ".let", ".`let`":
          res.introducer = .let

        default: return nil
        }
      case "isStatic":
        guard let boollit = arg.expression.as(BooleanLiteralExprSyntax.self) else { return nil }
        res.isStatic = boollit.description == "true"
      default:
        print("Bad arg: \(arg.description)")
        return nil
      }
    }

    guard expected == seen else {
      print("expected != seen")
      print("expected: \(expected)")
      print("seen: \(seen)")
      return nil
    }

    return res
  }
}

func deriveMove(properties: [StoredProperty], mutating: Bool) -> String {
  let body = properties.map {
    "\($0.name).move(by: offset.\($0.name))"
  }.joined(separator: "\n")
  return
    """
    \(mutating ? "mutating " : "")func move(by offset: TangentVector) {
      \(body)
    }
    """
}

public struct DeriveDifferentiableMacro: DeclarationMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard node.arguments.count == 3 else { fatalError() }
    let args = node.arguments.map { $0 }
    guard
      let requirement = args[0].expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
    else {
      fatalError("Invalid requirement `\(args[0].expression)`")
    }
    guard
      let parsed = ArgParser.parse(properties: args[1].expression, conformances: args[2].expression)
    else {
      fatalError("ParseError")
    }
    switch requirement {
    case "TangentVector":
      let code = deriveTangentVector(
        properties: parsed.storedProperties,
        conformances: parsed.conformances)

      return
        [
          """
          \(raw: code)
          """
        ]
    case "mutating move":
      return [
        """
        \(raw: deriveMove(properties: parsed.storedProperties, mutating: true))
        """
      ]
    case "move":
      return [
        """
        \(raw: deriveMove(properties: parsed.storedProperties, mutating: false))
        """
      ]
    default: fatalError("Unsupported requirement `\(requirement)`")
    }
  }
}
