// RUN: %target-swift-frontend -print-ast %s | %FileCheck %s --check-prefix=CHECK --check-prefix=CHECK-NO-MACROS
// RUN: %target-swift-frontend -load-plugin-library %swift-plugin-dir/libSwiftMacros.dylib -enable-experimental-feature DeriveConformancesViaMacros -print-ast %s | %FileCheck %s --check-prefix=CHECK --check-prefix=CHECK-MACROS

// CHECK-LABEL: internal enum Simple : Hashable
enum Simple: Hashable {
  // CHECK:        case a
  case a
  // CHECK:        case b
  case b

  // CHECK-NO-MACROS:     @_implements(Equatable, ==(_:_:)) internal static func __derived_enum_equals(_ a: Simple, _ b: Simple) -> Bool {
  // CHECK-MACROS:        @_implements(Equatable, ==(_:_:)) internal static func __derived_enum_equals(_ a: `Self`, _ b: `Self`) -> Bool {
  // CHECK-NEXT:     var index_a: Int
  // CHECK-MACROS-EMPTY:
  // CHECK-NEXT:     switch a {
  // CHECK-NEXT:     case .a:
  // CHECK-NEXT:       index_a = 0
  // CHECK-NEXT:     case .b:
  // CHECK-NEXT:       index_a = 1
  // CHECK-NEXT:     }
  // CHECK-NEXT:     var index_b: Int
  // CHECK-MACROS-EMPTY:
  // CHECK-NEXT:     switch b {
  // CHECK-NEXT:     case .a:
  // CHECK-NEXT:       index_b = 0
  // CHECK-NEXT:     case .b:
  // CHECK-NEXT:       index_b = 1
  // CHECK-NEXT:     }
  // CHECK-NEXT:     return index_a == index_b
  // CHECK-NEXT:   }

  // CHECK:        internal func hash(into hasher: inout Hasher) {
  // CHECK-NEXT:     var discriminator: Int
  // CHECK-NEXT:     switch self {
  // CHECK-NEXT:     case .a:
  // CHECK-NEXT:       discriminator = 0
  // CHECK-NEXT:     case .b:
  // CHECK-NEXT:       discriminator = 1
  // CHECK-NEXT:     }
  // CHECK-NEXT:     hasher.combine(discriminator)
  // CHECK-NEXT:   }

  // CHECK:        internal var hashValue: Int {
  // CHECK-NEXT:     get {
  // CHECK-NEXT:       return _hashValue(for: self)
  // CHECK-NEXT:     }
  // CHECK-NEXT:   }
}

// CHECK-LABEL: internal enum HasAssociatedValues : Hashable
enum HasAssociatedValues: Hashable {
  // CHECK:        case a(Int)
  case a(Int)
  // CHECK:        case b(String)
  case b(String)
  // CHECK:        case c
  case c

  // CHECK-NO-MACROS:     @_implements(Equatable, ==(_:_:)) internal static func __derived_enum_equals(_ a: HasAssociatedValues, _ b: HasAssociatedValues) -> Bool {
  // CHECK-MACROS:        @_implements(Equatable, ==(_:_:)) internal static func __derived_enum_equals(_ a: `Self`, _ b: `Self`) -> Bool {
  // CHECK-NEXT:     switch (a, b) {
  // CHECK-NEXT:     case (.a(let l0), .a(let r0)):
  // CHECK-NEXT:       guard l0 == r0 else {
  // CHECK-NEXT:         return false
  // CHECK-NEXT:       }
  // CHECK-NEXT:       return true
  // CHECK-NEXT:     case (.b(let l0), .b(let r0)):
  // CHECK-NEXT:       guard l0 == r0 else {
  // CHECK-NEXT:         return false
  // CHECK-NEXT:       }
  // CHECK-NEXT:       return true
  // CHECK-NEXT:     case (.c, .c):
  // CHECK-NEXT:       return true
  // CHECK-NEXT:     default:
  // CHECK-NEXT:       return false
  // CHECK-NEXT:     }
  // CHECK-NEXT:   }

  // CHECK:        internal func hash(into hasher: inout Hasher) {
  // CHECK-NEXT:     switch self {
  // CHECK-NEXT:     case .a(let a0):
  // CHECK-NEXT:       hasher.combine(0)
  // CHECK-NEXT:       hasher.combine(a0)
  // CHECK-NEXT:     case .b(let a0):
  // CHECK-NEXT:       hasher.combine(1)
  // CHECK-NEXT:       hasher.combine(a0)
  // CHECK-NEXT:     case .c:
  // CHECK-NEXT:       hasher.combine(2)
  // CHECK-NEXT:     }
  // CHECK-NEXT:   }

  // CHECK:        internal var hashValue: Int {
  // CHECK-NEXT:     get {
  // CHECK-NEXT:       return _hashValue(for: self)
  // CHECK-NEXT:     }
  // CHECK-NEXT:   }
}

// CHECK-LABEL: internal enum HasUnavailableElement : Hashable
enum HasUnavailableElement: Hashable {
  // CHECK:       case a
  case a
  // CHECK:       @available(*, unavailable)
  // CHECK-NEXT:  case b
  @available(*, unavailable)
  case b

  // CHECK-NO-MACROS:    @_implements(Equatable, ==(_:_:)) internal static func __derived_enum_equals(_ a: HasUnavailableElement, _ b: HasUnavailableElement) -> Bool {
  // CHECK-MACROS:       @_implements(Equatable, ==(_:_:)) internal static func __derived_enum_equals(_ a: `Self`, _ b: `Self`) -> Bool {
  // CHECK-NEXT:    var index_a: Int
  // CHECK-MACROS-EMPTY:
  // CHECK-NEXT:    switch a {
  // CHECK-NEXT:    case .a:
  // CHECK-NEXT:      index_a = 0
  // CHECK-NEXT:    case .b:
  // CHECK-NO-MACROS-NEXT:   _diagnoseUnavailableCodeReached{{.*}}()
  // CHECK-MACROS-NEXT:      fatalError({{.*}})
  // CHECK-NEXT:    }
  // CHECK-NEXT:    var index_b: Int
  // CHECK-MACROS-EMPTY:
  // CHECK-NEXT:    switch b {
  // CHECK-NEXT:    case .a:
  // CHECK-NEXT:      index_b = 0
  // CHECK-NEXT:    case .b:
  // CHECK-NO-MACROS-NEXT:   _diagnoseUnavailableCodeReached{{.*}}()
  // CHECK-MACROS-NEXT:      fatalError({{.*}})  
  // CHECK-NEXT:    }
  // CHECK-NEXT:    return index_a == index_b
  // CHECK-NEXT:  }

  // CHECK:       internal func hash(into hasher: inout Hasher) {
  // CHECK-NEXT:    var discriminator: Int
  // CHECK-NEXT:    switch self {
  // CHECK-NEXT:    case .a:
  // CHECK-NEXT:      discriminator = 0
  // CHECK-NEXT:    case .b:
  // CHECK-NEXT:      _diagnoseUnavailableCodeReached{{.*}}()
  // CHECK-NEXT:    }
  // CHECK-NEXT:    hasher.combine(discriminator)
  // CHECK-NEXT:  }

  // CHECK:       internal var hashValue: Int {
  // CHECK-NEXT:    get {
  // CHECK-NEXT:      return _hashValue(for: self)
  // CHECK-NEXT:    }
  // CHECK-NEXT:  }
}

// CHECK-LABEL: internal enum HasAssociatedValuesAndUnavailableElement : Hashable
enum HasAssociatedValuesAndUnavailableElement: Hashable {
  // CHECK:        case a(Int)
  case a(Int)
  // CHECK:       @available(*, unavailable)
  // CHECK-NEXT:  case b(String)
  @available(*, unavailable)
  case b(String)

  // CHECK-NO-MACROS:    @_implements(Equatable, ==(_:_:)) internal static func __derived_enum_equals(_ a: HasAssociatedValuesAndUnavailableElement, _ b: HasAssociatedValuesAndUnavailableElement) -> Bool {
  // CHECK-MACROS:       @_implements(Equatable, ==(_:_:)) internal static func __derived_enum_equals(_ a: `Self`, _ b: `Self`) -> Bool {
  // CHECK-NEXT:    switch (a, b) {
  // CHECK-NEXT:    case (.a(let l0), .a(let r0)):
  // CHECK-NEXT:      guard l0 == r0 else {
  // CHECK-NEXT:        return false
  // CHECK-NEXT:      }
  // CHECK-NEXT:      return true
  // CHECK-NO-MACROS-NEXT: case (.b, .b):
  // CHECK-MACROS-NEXT:    case (.b(_), .b(_)):
  // CHECK-NO-MACROS-NEXT:   _diagnoseUnavailableCodeReached{{.*}}()
  // CHECK-MACROS-NEXT:      fatalError({{.*}})
  // CHECK-NEXT:    default:
  // CHECK-NEXT:      return false
  // CHECK-NEXT:    }
  // CHECK-NEXT:  }


  // CHECK:       internal func hash(into hasher: inout Hasher) {
  // CHECK-NEXT:    switch self {
  // CHECK-NEXT:    case .a(let a0):
  // CHECK-NEXT:      hasher.combine(0)
  // CHECK-NEXT:      hasher.combine(a0)
  // CHECK-NEXT:    case .b:
  // CHECK-NEXT:      _diagnoseUnavailableCodeReached{{.*}}()
  // CHECK-NEXT:    }
  // CHECK-NEXT:  }

  // CHECK:       internal var hashValue: Int {
  // CHECK-NEXT:    get {
  // CHECK-NEXT:      return _hashValue(for: self)
  // CHECK-NEXT:    }
  // CHECK-NEXT:  }
}

// CHECK-LABEL: internal enum UnavailableEnum : Hashable
@available(*, unavailable)
enum UnavailableEnum: Hashable {
  // CHECK:        case a
  case a
  // CHECK:        case b
  case b

  // CHECK-NO-MACROS:     @_implements(Equatable, ==(_:_:)) internal static func __derived_enum_equals(_ a: UnavailableEnum, _ b: UnavailableEnum) -> Bool {
  // CHECK-MACROS:        @_implements(Equatable, ==(_:_:)) internal static func __derived_enum_equals(_ a: `Self`, _ b: `Self`) -> Bool {
  // CHECK-NEXT:     var index_a: Int
  // CHECK-MACROS-EMPTY:
  // CHECK-NEXT:     switch a {
  // CHECK-NEXT:     case .a:
  // CHECK-NEXT:       index_a = 0
  // CHECK-NEXT:     case .b:
  // CHECK-NEXT:       index_a = 1
  // CHECK-NEXT:     }
  // CHECK-NEXT:     var index_b: Int
  // CHECK-MACROS-EMPTY:
  // CHECK-NEXT:     switch b {
  // CHECK-NEXT:     case .a:
  // CHECK-NEXT:       index_b = 0
  // CHECK-NEXT:     case .b:
  // CHECK-NEXT:       index_b = 1
  // CHECK-NEXT:     }
  // CHECK-NEXT:     return index_a == index_b
  // CHECK-NEXT:   }

  // CHECK:        internal func hash(into hasher: inout Hasher) {
  // CHECK-NEXT:     var discriminator: Int
  // CHECK-NEXT:     switch self {
  // CHECK-NEXT:     case .a:
  // CHECK-NEXT:       discriminator = 0
  // CHECK-NEXT:     case .b:
  // CHECK-NEXT:       discriminator = 1
  // CHECK-NEXT:     }
  // CHECK-NEXT:     hasher.combine(discriminator)
  // CHECK-NEXT:   }

  // CHECK:        internal var hashValue: Int {
  // CHECK-NEXT:     get {
  // CHECK-NEXT:       return _hashValue(for: self)
  // CHECK-NEXT:     }
  // CHECK-NEXT:   }

}
