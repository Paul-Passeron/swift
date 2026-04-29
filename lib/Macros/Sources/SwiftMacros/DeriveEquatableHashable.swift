import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DeriveHashableHashValueMacro: DeclarationMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let arg = decodeExpansion(expansion: node) else {
      fatalError("Could not decode expansion")
    }
    switch arg {
    case .aStruct(members: _, let isUnsafe) where isUnsafe,
      .anEnum(cases: _, isObjC: _, let isUnsafe)
    where isUnsafe:
      let hashValue: DeclSyntax =
        """
        var  hashValue: Int {
          return unsafe _hashValue(for: self)
        }
        """
      return [hashValue]
    default:
      let hashValue: DeclSyntax =
        """
        var  hashValue: Int {
          return _hashValue(for: self)
        }
        """
      return [hashValue]
    }

  }
}

func expandHashableHashStructBody(
  members: [IdentifierPatternSyntax],
  isUnsafe: Bool
) -> [CodeBlockItemSyntax] {
  if members.isEmpty {
    return [.placeholderItem()]
  }
  let unsafePrologue =
    if isUnsafe {
      "unsafe "
    } else {
      ""
    }
  return members.map { member in
    """
    \(raw: unsafePrologue)hasher.combine(self.\(raw: member.description))
    """
  }
}

func expandHashableHashEnumBody(
  isObjC: Bool,
  cases: [EnumCaseInfo],
  isUnsafe: Bool
) -> [CodeBlockItemSyntax] {
  if isObjC {
    return [
      """
      hasher.combine(self.rawValue)
      """
    ]
  }
  if cases.isEmpty {
    return [.placeholderItem()]
  }

  return
    [
      """
      switch (self) {
      \(raw: cases.enumerated().map {
        "\($0.1.getCaseForHashableValue(idx: $0.0, isUnsafe: isUnsafe))"
      }.joined(separator: "\n"))
      }
      """
    ]

}

public struct DeriveHashableHashMacro {
  static func expandDecl(derived: DerivedNominalKind) -> DeclSyntax {
    return
      """
      @deriveHashableHashBody(\(derived.asExprSyntax()))
      func hash(into hasher: inout Hasher)
      """
  }
}

extension EnumCaseInfo {
  func getCasePattern() -> String {
    let args = argLabels.enumerated().map { (i, lbl) in
      let varDecl = "let x\(i)"
      if let lbl = lbl {
        return "\(lbl): \(varDecl)"
      } else {
        return varDecl
      }
    }.joined(separator: ", ")
    return
      """
      .\(caseName)(\(args))
      """
  }

  func getCombineCalls(_ idx: Int, _ isUnsafe: Bool) -> String {
    if isUnsafe {
      return
        """
            hasher.combine(\(idx))\(
              argLabels.enumerated().map {(i, _) in
              "\n    unsafe hasher.combine(x\(i))"
            }.joined(separator: ""))
        """
    } else {
      return
        """
            hasher.combine(\(idx))\(
              argLabels.enumerated().map {(i, _) in
              "\n    hasher.combine(x\(i))"
            }.joined(separator: ""))
        """
    }
  }

  func getCaseForHashableValue(idx: Int, isUnsafe: Bool) -> String {
    if argLabels.isEmpty {
      return "case .\(caseName):\n    hasher.combine(\(idx))"
    }
    if isUnavailable {
      return
        """
          case .\(caseName):
            fatalError("unreachable")
        """
    }
    return
      """
      case \(getCasePattern()):
      \(getCombineCalls(idx, isUnsafe))
      """
  }
}

extension DeriveHashableHashMacro: DeclarationMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    [
      """
      @deriveHashableHashBody(\(node.arguments))
      func hash(into hasher: inout Hasher)
      """
    ]
  }
}

public struct DeriveHashableHashBodyMacro: BodyMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingBodyFor declaration: some DeclSyntaxProtocol
      & WithOptionalCodeBlockSyntax,
    in context: some MacroExpansionContext
  ) throws -> [CodeBlockItemSyntax] {
    let args =
      switch node.arguments {
      case .argumentList(let args):
        args.map { $0.expression }
      default: fatalError("Bad args")
      }
    guard args.count == 1, let arg = args.first else {
      fatalError("Bad args")
    }
    guard let arg = decodeExpansionArg(arg: arg) else {
      fatalError(
        "Internal error: Could not decode expansion arg:\n\(arg.description)\n\n\(arg)"
      )
    }
    switch arg {
    case .aStruct(let members, let isUnsafe):
      return expandHashableHashStructBody(members: members, isUnsafe: isUnsafe)
    case .anEnum(let cases, let isObjC, let isUnsafe):
      return expandHashableHashEnumBody(
        isObjC: isObjC,
        cases: cases,
        isUnsafe: isUnsafe
      )
    }
  }
}
