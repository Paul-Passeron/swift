@attached(body)
public macro EquatableStructMacro() = Builtin.DerivedConformanceMacro

@attached(body)
public macro EquatableEnumMacro() = Builtin.DerivedConformanceMacro

@attached(member, names: arbitrary)
public macro EquatableDeclMacroOld() = Builtin.DerivedConformanceMacro

@freestanding(declaration, names: named(__derived_equals))
public macro EquatableDeclMacro() = Builtin.DerivedConformanceMacro

@frozen public enum DerivedNominalKind {
  case aStruct(members: [String])
  case anEnum(cases: [(caseName: String, argLabels: [String?], isUnavailable: Bool)], )
}

@freestanding(declaration, names: named(__derived_equals))
public macro deriveEquatable(_ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveEquatableMacro")
