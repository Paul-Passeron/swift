import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DeriveCaseIterableMacro: DeclarationMacro {

  static func generateAllCases(cases: [String]) -> String {
    let caseVals = cases.map { "Self.\($0)" }.joined(separator: ",\n   ")
    return
      """
      static var allCases: [Self] {
        [\(caseVals)]
      }
      """
  }

  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let arg = decodeExpansion(expansion: node) else { return [] }
    switch arg {
    case .anEnum(let cases, isObjC: _, let isUnsafe):
      if isUnsafe || !hasNoAssociatedValues(cases: cases) || hasUnavailableValues(cases: cases) {
        return []
      }
      let cases = cases.map { $0.caseName.description }
      let decl: DeclSyntax =
        """
        \(raw: generateAllCases(cases: cases))
        """
      return [decl]
    default: return []
    }
  }

}
