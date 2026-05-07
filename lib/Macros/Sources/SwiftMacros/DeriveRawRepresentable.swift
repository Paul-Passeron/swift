import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct RawReprEnumInfo {
  public var rawType: String = ""
  public var isObjC: Bool = false
  public var isString: Bool = false  // Might be redondant but avoids bad suprises with shadowing i reckon
  public var cases: [RawReprCaseInfo] = []
}

public struct RawReprCaseInfo {
  public var name: String = ""
  public var rawValue: String = ""
  public var availability: RuntimeVersionCheck? = nil
}

public struct RuntimeVersionCheck {
  public var platform: String = ""  // PlatformKind in C++
  public var version: String = ""  // llvm::VersionTuple in C++
}

extension RawReprCaseInfo {
  public static func parse(expr: ExprSyntax) -> Self? {
    guard let fcall = expr.as(FunctionCallExprSyntax.self) else { return nil }
    guard fcall.calledExpression.trimmedDescription == "RawReprCaseInfo" else {
      return nil
    }
    var seen: Set<String> = []
    let expected: Set<String> = [
      "name", "rawValue", "availability",
    ]
    var res = Self()
    for arg in fcall.arguments {
      guard let name = arg.label?.text else { return nil }
      guard seen.insert(name).inserted else { return nil }
      switch name {
      case "name":
        guard let strlit = arg.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        else { return nil }
        res.name = strlit
      case "rawValue":
        guard let strlit = arg.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        else { return nil }
        res.rawValue = strlit
      case "availability":
        if arg.expression.as(NilLiteralExprSyntax.self) != nil {
          res.availability = nil
        } else {
          guard let availability = RuntimeVersionCheck.parse(expr: arg.expression) else {
            return nil
          }
          res.availability = availability
        }
      default: return nil
      }
    }

    guard seen == expected else { return nil }
    return res
  }
}

extension RuntimeVersionCheck {
  public func getEarlyReturnStmt() -> StmtSyntax {
    return
      """
      guard #availability(\(raw: platform) \(raw: version), *)
      """
  }

  public static func parse(expr: ExprSyntax) -> Self? {
    guard let fcall = expr.as(FunctionCallExprSyntax.self) else { return nil }
    guard fcall.calledExpression.trimmedDescription == "RawReprEnumInfo" else { return nil }
    var seen: Set<String> = []
    let expected: Set<String> = [
      "platform", "version",
    ]
    var res = Self()
    for arg in fcall.arguments {
      guard let name = arg.label?.text else { return nil }
      guard seen.insert(name).inserted else { return nil }
      switch name {
      case "platform":
        guard let strlit = arg.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        else { return nil }
        res.platform = strlit
      case "version":
        guard let strlit = arg.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        else { return nil }
        res.version = strlit
      default: return nil
      }
    }

    guard seen == expected else { return nil }
    return res
  }
}

extension RawReprEnumInfo {
  public static func parse(expr: ExprSyntax) -> Self? {
    guard let fcall = expr.as(FunctionCallExprSyntax.self) else { return nil }
    guard fcall.calledExpression.trimmedDescription == "RawReprEnumInfo" else { return nil }
    var seen: Set<String> = []
    let expected: Set<String> = [
      "rawType", "isString", "isObjC", "cases",
    ]
    var res = Self()

    for arg in fcall.arguments {
      guard let name = arg.label?.text else { return nil }
      guard seen.insert(name).inserted else { return nil }
      switch name {
      case "rawType":
        guard let strlit = arg.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        else { return nil }
        res.rawType = strlit
      case "isString":
        guard let boollit = arg.expression.as(BooleanLiteralExprSyntax.self) else { return nil }
        res.isString = boollit.description == "true"
      case "isObjC":
        guard let boollit = arg.expression.as(BooleanLiteralExprSyntax.self) else { return nil }
        res.isObjC = boollit.description == "true"
      case "cases":
        guard
          let cases =
            (arg.expression.as(ArrayExprSyntax.self)?.elements.tryMap {
              RawReprCaseInfo.parse(expr: $0.expression)
            })
        else {
          return nil
        }
        res.cases = cases
      default: return nil
      }
    }

    guard seen == expected else { return nil }
    return res
  }
}

func deriveInit(_ info: RawReprEnumInfo) -> String {
  fatalError()
}

func deriveRawValue(_ info: RawReprEnumInfo) -> String {
  fatalError()
}

public struct DeriveRawRepresentableMacro: DeclarationMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    let args = node.arguments.map { $0 }
    guard args.count == 2 else { fatalError("Expected 2 arguments") }
    guard let role = args[0].expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
    else { fatalError() }
    guard let info = RawReprEnumInfo.parse(expr: args[1].expression) else { fatalError() }

    let code =
      switch role {
      case "init":
        deriveInit(info)
      case "rawValue":
        deriveRawValue(info)
      default: fatalError()
      }

    return [
      """
      \(raw: code)
      """
    ]
  }
}
