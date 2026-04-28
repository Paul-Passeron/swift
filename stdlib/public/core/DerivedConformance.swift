@attached(body)
public macro EquatableStructMacro() = Builtin.DerivedConformanceMacro

@attached(body)
public macro EquatableEnumMacro() = Builtin.DerivedConformanceMacro

@attached(member, names: arbitrary)
public macro EquatableDeclMacroOld() = Builtin.DerivedConformanceMacro

@freestanding(declaration, names: named(__derived_equals))
public macro EquatableDeclMacro() = Builtin.DerivedConformanceMacro

@frozen public enum DerivedNominalKind {
  case aStruct(members: [String], isUnsafe: Bool = false)
  case anEnum(
    cases: [(caseName: String, argLabels: [String?], isUnavailable: Bool)],
    isObjC: Bool = false,
    isUnsafe: Bool = false)
}

@freestanding(declaration, names: named(__derived_equals))
public macro deriveEquatable(_ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveEquatableMacro")

@attached(body)
public macro deriveEquatableBody(_ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveEquatableBodyMacro")

@freestanding(declaration, names: named(hashValue))
public macro deriveHashableHashValue(_ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveHashableHashValueMacro")

@freestanding(declaration, names: named(hash))
public macro deriveHashableHash(_ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveHashableHashMacro")

@freestanding(declaration, names: named(__derived_equals), named(__derived_enum_less_than))
public macro deriveComparison(_ comparison: String, _ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveComparisonMacro")

@attached(body)
public macro deriveComparisonBody(_ comparison: String, _ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveComparisonBodyMacro")

@freestanding(declaration, names: named(allCases))
public macro deriveCaseIterable(_ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveCaseIterableMacro")
