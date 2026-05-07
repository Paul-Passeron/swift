@frozen public enum DerivedNominalKind {
  case aStruct(members: [String], isUnsafe: Bool = false)
  case anEnum(
    cases: [(caseName: String, argLabels: [String?], isUnavailable: Bool)],
    isObjC: Bool = false,
    isUnsafe: Bool = false)
}

public struct StoredProperty {
  public enum Introducer {
    case `var`
    case `let`

    var asString: String {
      switch self {
      case .`var`: "var"
      case .`let`: "let"
      }
    }
  }

  public let name: String
  public let typeName: String
  public let introducer: Introducer
  public let isStatic: Bool

  public init(
    name: String, typeName: String, introducer: Introducer, isStatic: Bool
  ) {
    self.name = name
    self.typeName = typeName
    self.introducer = introducer
    self.isStatic = isStatic
  }
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

@freestanding(declaration, names: named(_nsErrorDomain))
public macro deriveErrorNSErrorDomain(_ asObjCEnum: String? = nil) =
  #externalMacro(module: "SwiftMacros", type: "DeriveErrorNSErrorDomainMacro")

@freestanding(declaration, names: named(+), named(-), named(zero))
public macro deriveAdditiveArithmetic(_ req: String, _ properties: [String]) =
  #externalMacro(module: "SwiftMacros", type: "DeriveAdditiveArithmeticMacro")

@freestanding(declaration, names: named(TangentVector), named(move))
public macro deriveDifferentiable(
  _ requirement: String,
  _ properties: [StoredProperty], _ conformances: [String]
) =
  #externalMacro(module: "SwiftMacros", type: "DeriveDifferentiableMacro")
