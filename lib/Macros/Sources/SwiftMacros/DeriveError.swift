import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DeriveErrorNSErrorDomainMacro: DeclarationMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    return if node.arguments.isEmpty {
      [
        """
        static var _nsErrorDomain: String {
          return String(reflecting: self)
        }
        """
      ]
    } else if node.arguments.count == 1 {
      [
        """
        static var _nsErrorDomain: String {
          return \(node.arguments.first!.expression)
        }
        """
      ]
    } else {
      fatalError("Invalid args")
    }
  }
}
