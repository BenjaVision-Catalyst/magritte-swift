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

private func containerWork(_ d: Description, _ count: Int, _ limits: Limits) throws {
  try require(d.isContainer, "Mutation requires a container")
  try require(count <= limits.items && count <= limits.visits, "Container mutation item/work limit")
}
private func sortedChildren(_ children: [Description], _ limits: Limits) throws -> [Description] {
  var work = children.count
  return try children.enumerated().sorted { a, b in
    work += 1
    try require(work <= limits.visits, "Container sorting work limit")
    let order = try compareNumbers(a.element.priorityValue(), b.element.priorityValue())
    return order == 0 ? a.offset < b.offset : order < 0
  }.map { $0.element }
}
extension Description {
  @discardableResult public func setChildren(_ next: [Description], limits: Limits = Limits()) throws -> Self {
    try containerWork(self, next.count, limits)
    children = try descriptionIs(self, "MAPriorityContainer") ? sortedChildren(next, limits) : next
    return self
  }
  @discardableResult public func add(_ child: Description, limits: Limits = Limits()) throws -> Self {
    try containerWork(self, children.count + 1, limits)
    if !descriptionIs(self, "MAPriorityContainer") { children.append(child) }
    else {
      var low = 0, high = children.count, work = children.count
      while low < high {
        work += 1
        try require(work <= limits.visits, "Container insertion work limit")
        let mid = low + (high - low - 1) / 2
        if try compareNumbers(children[mid].priorityValue(), child.priorityValue()) <= 0 { low = mid + 1 }
        else { high = mid }
      }
      children.insert(child, at: low)
    }
    return self
  }
  @discardableResult public func addAll(_ incoming: [Description], limits: Limits = Limits()) throws -> Self {
    try require(incoming.count <= limits.items && children.count <= limits.items - incoming.count, "Container mutation item/work limit")
    try containerWork(self, children.count + incoming.count, limits)
    if descriptionIs(self, "MAPriorityContainer") && incoming.count > children.count / 3 {
      children.append(contentsOf: incoming)
      children = try sortedChildren(children, limits)
    } else { for child in incoming { try add(child, limits: limits) } }
    return self
  }
  @discardableResult public func remove(_ sought: Description, limits: Limits = Limits()) throws -> Self {
    try containerWork(self, children.count, limits)
    if let i = try firstEqualChild(children, sought, limits) { children.remove(at: i); return self }
    throw MagritteError("Container child not found")
  }
  @discardableResult public func removeAll(limits: Limits = Limits()) throws -> Self { try setChildren([], limits: limits) }
  @discardableResult public func moveUp(_ sought: Description, limits: Limits = Limits()) throws -> Self {
    try containerWork(self, children.count, limits)
    try require(!descriptionIs(self, "MAPriorityContainer"), "Priority containers do not implement moveUp:")
    if let i = children.firstIndex(where: { $0 === sought }), i > 0 { children.swapAt(i - 1, i) }
    return self
  }
  @discardableResult public func moveDown(_ sought: Description, limits: Limits = Limits()) throws -> Self {
    try containerWork(self, children.count, limits)
    try require(!descriptionIs(self, "MAPriorityContainer"), "Priority containers do not implement moveDown:")
    if let i = children.firstIndex(where: { $0 === sought }), i + 1 < children.count { children.swapAt(i, i + 1) }
    return self
  }
  @discardableResult public func resort(limits: Limits = Limits()) throws -> Self {
    try require(descriptionIs(self, "MAPriorityContainer"), "Resort requires a priority container")
    return try setChildren(children, limits: limits)
  }
}
