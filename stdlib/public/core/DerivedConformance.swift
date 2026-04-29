@frozen public enum DerivedNominalKind {
  case aStruct(members: [String], isUnsafe: Bool = false)
  case anEnum(
    cases: [(caseName: String, argLabels: [String?], isUnavailable: Bool)],
    isObjC: Bool = false,
    isUnsafe: Bool = false)
}

@freestanding(declaration, names: named(hashValue))
public macro deriveHashableHashValue(_ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveHashableHashValueMacro")

@freestanding(declaration, names: named(hash))
public macro deriveHashableHash(_ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveHashableHashMacro")

@attached(body)
public macro deriveHashableHashBody(_ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveHashableHashBodyMacro")

@freestanding(declaration, names: named(__derived_equals), named(__derived_enum_less_than))
public macro deriveComparison(_ comparison: String, _ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveComparisonMacro")

@attached(body)
public macro deriveComparisonBody(_ comparison: String, _ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveComparisonBodyMacro")

@freestanding(declaration, names: named(allCases))
public macro deriveCaseIterable(_ kind: DerivedNominalKind) =
  #externalMacro(module: "SwiftMacros", type: "DeriveCaseIterableMacro")
