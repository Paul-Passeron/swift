//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@freestanding(declaration, names: arbitrary)
public macro _deriveEquatable(_ infos: String, isResilient: Bool) =
  #externalMacro(module: "SwiftMacros", type: "DeriveEquatableMacro")

@freestanding(declaration, names: arbitrary)
public macro _deriveCaseIterable(_ infos: String, _ witness: String) =
  #externalMacro(module: "SwiftMacros", type: "DeriveCaseIterableMacro")
