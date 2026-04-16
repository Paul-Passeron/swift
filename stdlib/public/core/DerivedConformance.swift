@attached(body)
public macro EquatableStructMacro() = Builtin.DerivedConformanceMacro

@attached(body)
public macro EquatableEnumMacro() = Builtin.DerivedConformanceMacro

@attached(member, names: arbitrary)
public macro EquatableDeclMacroOld() = Builtin.DerivedConformanceMacro

@freestanding(declaration, names: named(__derived_equals))
public macro EquatableDeclMacro() = Builtin.DerivedConformanceMacro

@frozen public struct EnumCaseInfo {
  let caseName: String
  let argLabels: [String?]
  let isUnavailable: Bool
}

extension EnumCaseInfo {
  public static func new(caseName: String, argLabels: [String?] = [], isUnavailable: Bool = false)
    -> Self
  {
    Self(caseName: caseName, argLabels: argLabels, isUnavailable: isUnavailable)
  }

}

@frozen public enum DerivedNominalKind {
  case aStruct(members: [String])
  case anEnum(cases: [EnumCaseInfo])
}

@freestanding(declaration, names: named(__derived_equals))
public macro deriveEquatable(_ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveEquatableMacro")
