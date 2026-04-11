//
//  DeriveEquatable.swift
//  Swift
//
//  Created by Paul Passeron on 10/04/2026.
//

import SwiftSyntax

func expandEquatableMacroBody(propertyNames: [String], lhsName lhs: String = "a", rhsName rhs: String = "b")
  -> CodeBlockSyntax
{
  let guards: [CodeBlockItemSyntax] = propertyNames.map {
    name in
    """
    guard \(raw: lhs).\(raw: name) == \(raw: rhs).\(raw: name) else { return false; }
    """
  }
  return CodeBlockSyntax {
    for g in guards { g }
    "return true;"
  }

}
