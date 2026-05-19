//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import SwiftSyntax
import SwiftSyntaxBuilder

extension Sequence {
  /// Helper method that fails on the first None value transformation in a
  /// sequence.
  @inlinable public func tryMap<T>(_ transform: (Element) throws -> T?) rethrows -> [T]? {
    var res: [T] = []
    for elem in self {
      guard let val = (try transform(elem)) else {
        return nil
      }
      res.append(val)
    }
    return res
  }
}

public struct NominalTypeInfo: Equatable {
  public let name: String
  public let kind: TypeKind
  public let isUnsafe: Bool
}

public struct StructTypeInfo: Equatable {
  public let properties: [StoredProperty]
}

public struct StoredProperty: Equatable {
  public let name: String
  public let typeName: String
  public let isVar: Bool
  public let isStatic: Bool
}
public struct EnumTypeInfo: Equatable {
  public let rawType: RawTypeKind?
  public let isObjC: Bool
  public let cases: [CaseInfo]
}

public enum TypeKind: Equatable {
  case structLike(StructTypeInfo)
  case enumLike(EnumTypeInfo)
}

public enum RawTypeKind: Equatable {
  case str
  case other(String)
}

public struct CaseInfo: Equatable {
  public let name: String
  public let rawValueExpr: String?
  public let availability: RuntimeVersionCheck?
}

public struct RuntimeVersionCheck: Equatable {
  public let platform: String
  public let version: String
}

struct NominalTypeInfoParser {

  /// Parses a string literal and returns its contents or nil in case of
  /// failure.
  static func parseString(expr node: ExprSyntax) -> String? {
    node.as(StringLiteralExprSyntax.self)?.representedLiteralValue
  }

  /// Parses a bool literal and returns its value or nil in case of failure.
  static func parseBool(expr node: ExprSyntax) -> Bool? {
    node.as(BooleanLiteralExprSyntax.self)?.trimmedDescription ?? "" == "true"
  }

  /// Parses an array literal of `T`s with parsing function `of` from `expr`.
  static func parseArrayOf<T>(expr node: ExprSyntax, of f: (_: ExprSyntax) -> T?) -> [T]? {
    guard let arr = node.as(ArrayExprSyntax.self) else {
      return nil
    }
    return arr.elements.tryMap({ f($0.expression) })
  }

  /// Parses an optional value of `T` with parsing function `of` from `expr`.
  /// - returns `nil` in case of failure
  /// - returns `some(nil)` if the parsed value is nil
  /// - returns `some(some(<T>))` if the parsed value isn't nil
  static func parseOptOf<T>(expr node: ExprSyntax, of f: (_: ExprSyntax) -> T?) -> T?? {
    if node.is(NilLiteralExprSyntax.self) {
      return Optional.some(nil)
    }
    guard let value = f(node) else {
      return nil
    }
    return value
  }

  /// Parses a NominalTypeInfo from an expression syntax node, returns nil in
  /// case of failure
  static func parseFromExprSyntax(expr node: ExprSyntax) -> NominalTypeInfo? {

    // Expected:
    // NominalTypeInfo(name: <string>, kind: <type kind>, isUnsafe: <bool>)

    guard let fcall = node.as(FunctionCallExprSyntax.self) else {
      return nil
    }

    guard fcall.calledExpression.trimmedDescription == "NominalTypeInfo" else {
      return nil
    }

    let args: [LabeledExprSyntax] = fcall.arguments.map { $0 }
    guard args.count == 3 else {
      return nil
    }

    let nameArg = args[0]
    let kindArg = args[1]
    let isUnsafeArg = args[2]

    guard nameArg.label?.trimmedDescription ?? "" == "name" else {
      return nil
    }
    guard kindArg.label?.trimmedDescription ?? "" == "kind" else {
      return nil
    }
    guard isUnsafeArg.label?.trimmedDescription ?? "" == "isUnsafe" else {
      return nil
    }

    guard let name = Self.parseString(expr: nameArg.expression) else {
      return nil
    }
    guard let kind = Self.parseKind(expr: kindArg.expression) else {
      return nil
    }
    guard let isUnsafe = Self.parseBool(expr: isUnsafeArg.expression) else {
      return nil
    }

    return NominalTypeInfo(name: name, kind: kind, isUnsafe: isUnsafe)
  }

  /// Parses a TypeKind from an expression syntax node, returns nil in
  /// case of failure.
  static func parseKind(expr node: ExprSyntax) -> TypeKind? {

    // Expected:
    // structLike(<struct type info>)
    // or
    // enumLike(<enum type info>)

    guard let fcall = node.as(FunctionCallExprSyntax.self) else {
      return nil
    }

    let args = fcall.arguments.map { $0 }
    guard args.count == 1 else {
      return nil
    }
    let arg = args[0]
    guard arg.label == nil else {
      return nil
    }

    switch fcall.calledExpression.trimmedDescription {

    case "structLike":
      guard let structInfo = Self.parseStructTypeInfo(expr: arg.expression) else {
        return nil
      }
      return TypeKind.structLike(structInfo)

    case "enumLike":
      guard let enumInfo = Self.parseEnumTypeInfo(expr: arg.expression) else {
        return nil
      }
      return TypeKind.enumLike(enumInfo)
    default:
      return nil
    }
  }

  /// Parses a StructTypeInfo from an expression syntax node, returns nil in
  /// case of failure.
  static func parseStructTypeInfo(expr node: ExprSyntax) -> StructTypeInfo? {

    // Expected:
    // StructTypeInfos(properties: [<stored property>, ...])

    guard let fcall = node.as(FunctionCallExprSyntax.self) else {
      return nil
    }

    guard fcall.calledExpression.trimmedDescription == "StructTypeInfo" else {
      print(fcall.calledExpression.trimmedDescription)
      return nil
    }

    let args = fcall.arguments.map { $0 }
    guard args.count == 1 else {
      return nil
    }
    let arg = args[0]
    guard arg.label?.trimmedDescription ?? "" == "properties" else {
      return nil
    }
    guard let properties = Self.parseArrayOf(expr: arg.expression, of: Self.parseStoredProperty)
    else {
      return nil
    }

    return StructTypeInfo(properties: properties)
  }

  /// Parses an EnumTypeInfo from an expression syntax node, returns nil in
  /// case of failure.
  static func parseEnumTypeInfo(expr node: ExprSyntax) -> EnumTypeInfo? {

    // Expected:
    // EnumTypeInfo(
    //    rawType: <raw type kind>,
    //    isObjC: <bool>,
    //    cases: [<case info>, ...])

    guard let fcall = node.as(FunctionCallExprSyntax.self) else {
      return nil
    }
    guard fcall.calledExpression.trimmedDescription == "EnumTypeInfo" else {
      return nil
    }

    let args: [LabeledExprSyntax] = fcall.arguments.map { $0 }
    guard args.count == 3 else {
      return nil
    }

    let rawTypeArg = args[0]
    let isObjCArg = args[1]
    let casesArg = args[2]

    guard rawTypeArg.label?.trimmedDescription ?? "" == "rawType" else {
      return nil
    }
    guard isObjCArg.label?.trimmedDescription ?? "" == "isObjC" else {
      return nil
    }
    guard casesArg.label?.trimmedDescription ?? "" == "cases" else {
      return nil
    }

    guard let rawType = Self.parseOptOf(expr: rawTypeArg.expression, of: Self.parseRawTypeKind)
    else {
      return nil
    }
    guard let isObjC = Self.parseBool(expr: isObjCArg.expression) else {
      return nil
    }
    guard let cases = Self.parseArrayOf(expr: casesArg.expression, of: Self.parseCaseInfo)
    else {
      return nil
    }

    return EnumTypeInfo(rawType: rawType, isObjC: isObjC, cases: cases)
  }

  /// Parses the raw type kind from an expression syntax node, returns nil in
  /// case of failure.
  /// We either expect
  /// - the identifier `str` when we have a
  /// `String`, as it is a special case and the name of the type itself can be
  /// shadowed by a local type also named `String`.
  /// - a string literal containing the type name.
  static func parseRawTypeKind(expr node: ExprSyntax) -> RawTypeKind? {

    // Expected:
    // str
    // or
    // <string>

    if node.is(StringLiteralExprSyntax.self) {
      guard let val = Self.parseString(expr: node) else {
        return nil
      }
      return RawTypeKind.other(val)
    }
    if node.trimmedDescription == "str" {
      return RawTypeKind.str
    }
    return nil
  }

  /// Parses a CaseInfo from an expression syntax nodes, returns nil in case of
  /// failure.
  static func parseCaseInfo(expr node: ExprSyntax) -> CaseInfo? {

    // Expected:
    // CaseInfo(
    //     name: <string>,
    //     rawValueExpr: <nil | string>,
    //     availability: <nil | runtime version check>)

    guard let fcall = node.as(FunctionCallExprSyntax.self) else {
      return nil
    }
    guard fcall.calledExpression.trimmedDescription == "CaseInfo" else {
      return nil
    }

    let args: [LabeledExprSyntax] = fcall.arguments.map { $0 }
    guard args.count == 3 else {
      return nil
    }

    let nameArg = args[0]
    let rawValueExprArg = args[1]
    let availabilityArg = args[2]

    guard nameArg.label?.trimmedDescription ?? "" == "name" else {
      return nil
    }
    guard rawValueExprArg.label?.trimmedDescription ?? "" == "rawValueExpr" else {
      return nil
    }
    guard availabilityArg.label?.trimmedDescription ?? "" == "availability" else {
      return nil
    }

    guard let name = Self.parseString(expr: nameArg.expression) else {
      return nil
    }
    guard
      let rawValueExpr = Self.parseOptOf(
        expr: rawValueExprArg.expression, of: Self.parseString)
    else {
      return nil
    }
    guard
      let availability = Self.parseOptOf(
        expr: availabilityArg.expression, of: Self.parseRuntimeVersionCheck)
    else {
      return nil
    }

    return CaseInfo(name: name, rawValueExpr: rawValueExpr, availability: availability)
  }

  /// Parses a RuntimeVersionCheck from an expression syntax node, returns nil
  /// in case of failure.
  static func parseRuntimeVersionCheck(expr node: ExprSyntax) -> RuntimeVersionCheck? {

    // Expected:
    // RuntimeVersionCheck(platform: <string>, version: <string>)

    guard let fcall = node.as(FunctionCallExprSyntax.self) else {
      return nil
    }
    guard fcall.calledExpression.trimmedDescription == "CaseInfo" else {
      return nil
    }

    let args: [LabeledExprSyntax] = fcall.arguments.map { $0 }
    guard args.count == 2 else {
      return nil
    }

    let platformArg = args[0]
    let versionArg = args[1]

    guard platformArg.label?.trimmedDescription ?? "" == "platform" else {
      return nil
    }
    guard versionArg.label?.trimmedDescription ?? "" == "version" else {
      return nil
    }

    guard let platform = Self.parseString(expr: platformArg.expression) else {
      return nil
    }
    guard let version = Self.parseString(expr: versionArg.expression) else {
      return nil
    }

    return RuntimeVersionCheck(platform: platform, version: version)
  }

  /// Parses a StoredProperty from an expression syntax node, returns nil in
  /// case of failure
  static func parseStoredProperty(expr node: ExprSyntax) -> StoredProperty? {

    // Expected:
    // StoredProperty(
    //     name: <string>,
    //     typeName: <string>,
    //     isVar: <bool>,
    //     isStatic: <bool>)

    guard let fcall = node.as(FunctionCallExprSyntax.self) else {
      return nil
    }
    guard fcall.calledExpression.trimmedDescription == "StoredProperty" else {
      return nil
    }

    let args: [LabeledExprSyntax] = fcall.arguments.map { $0 }
    guard args.count == 4 else {
      return nil
    }

    let nameArg = args[0]
    let typeNameArg = args[1]
    let isVarArg = args[2]
    let isStaticArg = args[3]

    guard nameArg.label?.trimmedDescription ?? "" == "name" else {
      return nil
    }
    guard typeNameArg.label?.trimmedDescription ?? "" == "typeName" else {
      return nil
    }
    guard isVarArg.label?.trimmedDescription ?? "" == "isVar" else {
      return nil
    }
    guard isStaticArg.label?.trimmedDescription ?? "" == "isStatic" else {
      return nil
    }

    guard let name = Self.parseString(expr: nameArg.expression) else {
      return nil
    }
    guard let typeName = Self.parseString(expr: typeNameArg.expression) else {
      return nil
    }
    guard let isVar = Self.parseBool(expr: isVarArg.expression) else {
      return nil
    }
    guard let isStatic = Self.parseBool(expr: isStaticArg.expression) else {
      return nil
    }

    return StoredProperty(
      name: name,
      typeName: typeName,
      isVar: isVar,
      isStatic: isStatic,
    )
  }

  /// Parses a NominalTypeInfo wrapped in a string literal, returns nil in case
  /// of failure
  static func parse(stringLiteral node: StringLiteralExprSyntax) -> NominalTypeInfo? {
    guard let contents = node.representedLiteralValue else {
      return nil
    }
    return Self.parseFromString(str: contents)
  }

  /// Parses a NominalTypeInfo from a String containing Swift syntax, returns
  /// nil in case of failure
  static func parseFromString(str: String) -> NominalTypeInfo? {
    Self.parseFromExprSyntax(expr: "\(raw: str)")
  }
}

extension NominalTypeInfo {
  public static func from(expr: ExprSyntax) -> Self? {
    NominalTypeInfoParser.parseFromExprSyntax(expr: expr)
  }

  public static func from(str: String) -> Self? {
    NominalTypeInfoParser.parseFromString(str: str)
  }

  public static func from(stringLiteral: StringLiteralExprSyntax) -> Self? {
    NominalTypeInfoParser.parse(stringLiteral: stringLiteral)
  }
}
