#if $Macros && hasAttribute(attached)

  @attached(body)
  public macro EquatableStructMacro() = Builtin.DerivedConformanceMacro

  @attached(body)
  public macro EquatableEnumMacro() = Builtin.DerivedConformanceMacro

#endif  // $Macros && hasAttribute(attached)
