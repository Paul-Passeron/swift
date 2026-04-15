#if $Macros && hasAttribute(attached)

  @attached(body)
  public macro EquatableStructMacro() = Builtin.DerivedConformanceMacro

  @attached(body)
  public macro EquatableEnumMacro() = Builtin.DerivedConformanceMacro

  @attached(member, names: arbitrary)
  public macro EquatableDeclMacroOld() = Builtin.DerivedConformanceMacro

  @freestanding(declaration, names: named(__derived_equals))
  public macro EquatableDeclMacro() = Builtin.DerivedConformanceMacro
#endif  // $Macros && hasAttribute(attached)
