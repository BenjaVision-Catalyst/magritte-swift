import Foundation

/// Direct MAContainer enumeration; native indices are zero-based. Callbacks must not
/// structurally mutate the container during an operation. Children retain identity.
public func enumerationChildren(_ d: Description, limits: Limits = Limits()) throws -> [Description]
{
  try require(d.isContainer, "Enumeration requires a container")
  try require(
    d.children.count <= limits.items && d.children.count <= limits.visits,
    "Container enumeration item/work limit")
  return try d.orderedChildren()
}
public func childAt(
  _ d: Description, index: Int, limits: Limits = Limits(),
  ifAbsent: () throws -> Description?
) throws -> Description? {
  let children = try enumerationChildren(d, limits: limits)
  return try children.indices.contains(index) ? children[index] : ifAbsent()
}
public func childAt(_ d: Description, index: Int, limits: Limits = Limits()) throws -> Description {
  guard
    let child = try childAt(
      d, index: index, limits: limits,
      ifAbsent: { throw MagritteError("Container index outside children") })
  else {
    throw MagritteError("Container index outside children")
  }
  return child
}
public func detectDescription(
  _ d: Description, limits: Limits = Limits(),
  where predicate: (Description) throws -> Bool, ifNone: () throws -> Description?
) throws -> Description? {
  for child in try enumerationChildren(d, limits: limits) {
    if try predicate(child) { return child }
  }
  return try ifNone()
}
public func detectDescription(
  _ d: Description, limits: Limits = Limits(),
  where predicate: (Description) throws -> Bool
) throws -> Description {
  guard
    let child = try detectDescription(
      d, limits: limits, where: predicate,
      ifNone: { throw MagritteError("No matching container child") })
  else {
    throw MagritteError("No matching container child")
  }
  return child
}
public func allDescriptionsSatisfy(
  _ d: Description, limits: Limits = Limits(),
  _ predicate: (Description) throws -> Bool
) throws -> Bool {
  for child in try enumerationChildren(d, limits: limits) {
    if try !predicate(child) { return false }
  }
  return true
}
public func anyDescriptionSatisfies(
  _ d: Description, limits: Limits = Limits(),
  _ predicate: (Description) throws -> Bool
) throws -> Bool {
  for child in try enumerationChildren(d, limits: limits) {
    if try predicate(child) { return true }
  }
  return false
}
public func noDescriptionSatisfies(
  _ d: Description, limits: Limits = Limits(),
  _ predicate: (Description) throws -> Bool
) throws -> Bool {
  try !anyDescriptionSatisfies(d, limits: limits, predicate)
}
public func forEachDescription(
  _ d: Description, limits: Limits = Limits(),
  _ body: (Description) throws -> Void
) throws {
  for child in try enumerationChildren(d, limits: limits) { try body(child) }
}
public func forEachDescriptionIndexed(
  _ d: Description, limits: Limits = Limits(),
  _ body: (Int, Description) throws -> Void
) throws {
  for (i, child) in try enumerationChildren(d, limits: limits).enumerated() { try body(i, child) }
}
public func forEachDescriptionSeparated(
  _ d: Description, limits: Limits = Limits(),
  _ body: (Description) throws -> Void, separator: () throws -> Void
) throws {
  for (i, child) in try enumerationChildren(d, limits: limits).enumerated() {
    if i > 0 { try separator() }
    try body(child)
  }
}
public func reduceDescriptions<Accumulator>(
  _ d: Description, initial: Accumulator, limits: Limits = Limits(),
  _ combine: (Accumulator, Description) throws -> Accumulator
) throws -> Accumulator {
  var result = initial
  for child in try enumerationChildren(d, limits: limits) { result = try combine(result, child) }
  return result
}
public func forEachDescriptionPaired<T>(
  _ d: Description, with other: [T], limits: Limits = Limits(),
  _ body: (Description, T) throws -> Void
) throws {
  let children = try enumerationChildren(d, limits: limits)
  try require(children.count == other.count, "Container paired enumeration size mismatch")
  for (child, value) in zip(children, other) { try body(child, value) }
}
