import Foundation

public struct DescriptionCopy {
  public let root: Description
  // Retains copied references and shared children, including their weak targets.
  var retained: [Description]
}
private final class CompositionWork {
  let limits: Limits
  var count = 0
  init(_ limits: Limits) { self.limits = limits }
  func tick(_ depth: Int = 0) throws {
    count += 1
    try require(count <= limits.visits && depth <= limits.depth, "Composition work/depth limit")
  }
  func accessor(_ a: Accessor, _ b: Accessor, _ depth: Int) throws -> Bool {
    try tick(depth)
    try a.check(limits: limits)
    try b.check(limits: limits)
    if a.className != b.className { return false }
    if a.className == "MAChainAccessor" || a.className == "MADelegatorAccessor" {
      if a.steps.count != b.steps.count { return false }
      for (x, y) in zip(a.steps, b.steps) { if try !accessor(x, y, depth + 1) { return false } }
      return true
    }
    if a.className == "MANullAccessor" {
      return try valueKey(a.uuid) { depth in try self.tick(depth) }
        == valueKey(b.uuid) { depth in try self.tick(depth) }
    }
    let sameName =
      try valueKey(.string(a.name)) { try self.tick($0) }
      == valueKey(.string(b.name)) { try self.tick($0) }
    return try sameName
      && (a.className != "MASelectorAccessor"
        || valueKey(.string(a.writeName)) { try self.tick($0) }
          == valueKey(.string(b.writeName)) { try self.tick($0) })
  }
  func equal(_ a: Description, _ b: Description, _ depth: Int = 0) throws -> Bool {
    try tick(depth)
    try supported(a)
    try supported(b)
    try require(
      a.nativeRead == nil && a.nativeWrite == nil && b.nativeRead == nil && b.nativeWrite == nil,
      "Local accessor callback equality is unavailable")
    if try a.className != b.className || !accessor(a.effectiveAccessor, b.effectiveAccessor, depth)
    {
      return false
    }
    if !a.isContainer { return true }
    let x = try a.orderedChildren()
    let y = try b.orderedChildren()
    if x.count != y.count { return false }
    for (one, two) in zip(x, y) { if try !equal(one, two, depth + 1) { return false } }
    return true
  }
}
private func retainDescriptions(_ source: Description, _ limits: Limits) throws -> [Description] {
  var work = 0
  try visit(source, limits: limits) {
    try supported($0)
    try checkPortableDescription($0, limits: limits, work: &work)
    for value in $0.properties.values {
      _ = try valueKey(value) { depth in
        work += 1
        try require(work <= limits.visits && depth <= limits.depth, "Copy value work/depth limit")
      }
    }
  }
  var seen = Set<ObjectIdentifier>()
  var result: [Description] = []
  func walk(_ d: Description) throws {
    if !seen.insert(ObjectIdentifier(d)).inserted { return }
    result.append(d)
    for child in d.children { try walk(child) }
    if d.isReference { try walk(d.referenceDescription()) }
  }
  try walk(source)
  return result
}
private func mergeOwners(_ result: inout DescriptionCopy, _ source: Description, _ limits: Limits)
  throws
{
  if result.retained.contains(where: { $0 === source }) { return }
  var ids = Set(result.retained.map(ObjectIdentifier.init))
  for d in try retainDescriptions(source, limits) {
    if ids.insert(ObjectIdentifier(d)).inserted { result.retained.append(d) }
  }
  try require(result.retained.count <= limits.nodes, "Copy retained node limit")
}
private func containerFields(_ d: Description) throws -> [Description] {
  try require(d.isContainer, "Composition operation requires a container")
  return try d.orderedChildren()
}
public func descriptionEqual(_ a: Description, _ b: Description, limits: Limits = Limits()) throws
  -> Bool
{ try CompositionWork(limits).equal(a, b) }
/// Follows Magritte postCopy, not a graph deep clone. The new root ID is explicit.
public func copyDescription(_ source: Description, newID: String, limits: Limits = Limits()) throws
  -> DescriptionCopy
{
  var retained = try retainDescriptions(source, limits)
  try require(
    !newID.isEmpty && !retained.contains { $0.id == newID },
    "Copy identity already belongs to a retained description")
  let work = CompositionWork(limits)
  var active = Set<ObjectIdentifier>()
  var identities = Set(retained.map(\.id))
  func clone(_ d: Description, _ id: String, _ depth: Int) throws -> Description {
    try work.tick(depth)
    try require(
      identities.insert(id).inserted && !id.isEmpty && id.utf8.allSatisfy { $0 >= 33 && $0 <= 126 },
      "Copy generated identity collision or invalid identity")
    _ = try valueKey(.string(id)) { try work.tick($0) }
    try require(retained.count < limits.nodes, "Copy retained node limit")
    try require(
      active.insert(ObjectIdentifier(d)).inserted,
      "Recursive reference postCopy is unsupported; copy is not a graph deep clone")
    let n = Description(id: id, className: d.className, key: d.key)
    n.properties = d.properties
    n.children = d.children
    n.classes = d.classes
    n.options = d.isOption ? d.options.copy() : d.options
    n.labels = d.labels
    n.conditions = d.conditions
    n.portableConditions = d.portableConditions
    n.accessor = d.accessor
    if let object = d.accessorObject { n.accessorObject = try AccessorObject.fromAccessor(id: id + ".accessor", object.snapshot(limits: limits), limits: limits); n.accessor = nil }
      n.nativeRead = d.nativeRead
    n.nativeWrite = d.nativeWrite
    n.defaultFunction = d.defaultFunction
    retained.append(n)
    if d.isReference {
      n.reference = try clone(d.referenceDescription(), id + ".reference", depth + 1)
    }
    active.remove(ObjectIdentifier(d))
    return n
  }
  let root = try clone(source, newID, 0)
  return DescriptionCopy(root: root, retained: retained)
}
public func asContainer(_ d: Description, newID: String, limits: Limits = Limits()) throws
  -> DescriptionCopy
{
  let retained = try retainDescriptions(d, limits)
  if d.isContainer { return DescriptionCopy(root: d, retained: retained) }
  try require(
    !newID.isEmpty && newID.utf8.allSatisfy { $0 >= 33 && $0 <= 126 }
      && !retained.contains { $0.id == newID }, "Invalid wrapper identity or collision")
  try require(retained.count < limits.nodes, "Wrapper node limit")
  let root = Description(id: newID, className: "MAContainer")
  root.children = [d]
  return DescriptionCopy(root: root, retained: retained)
}
public func concatenate(
  _ a: Description, _ b: Description, newID: String, limits: Limits = Limits()
) throws -> DescriptionCopy {
  let wrapped = try asContainer(a, newID: newID + ".source", limits: limits)
  var result = try copyDescription(wrapped.root, newID: newID, limits: limits)
  try mergeOwners(&result, b, limits)
  result.root.children += try b.isContainer ? b.orderedChildren() : [b]
  try require(result.root.children.count <= limits.items, "Composition item limit")
  return result
}
public func unionDescriptions(
  _ a: Description, _ b: Description, newID: String, limits: Limits = Limits()
) throws -> DescriptionCopy {
  let left = try containerFields(a)
  let right = try containerFields(b)
  let work = CompositionWork(limits)
  var result = try copyDescription(a, newID: newID, limits: limits)
  try mergeOwners(&result, b, limits)
  for d in right {
    var contains = false
    for e in left {
      if try work.equal(e, d) {
        contains = true
        break
      }
    }
    if !contains { result.root.children.append(d) }
  }
  try require(result.root.children.count <= limits.items, "Composition item limit")
  return result
}
public func intersectDescriptions(
  _ a: Description, _ b: Description, newID: String, limits: Limits = Limits()
) throws -> DescriptionCopy {
  let left = try containerFields(a)
  let right = try containerFields(b)
  let work = CompositionWork(limits)
  var result = try copyDescription(a, newID: newID, limits: limits)
  try mergeOwners(&result, b, limits)
  result.root.children = []
  for d in left {
    var contains = false
    for e in right {
      if try work.equal(d, e) {
        contains = true
        break
      }
    }
    if contains {
      var duplicate = false
      for e in result.root.children {
        if try work.equal(d, e) {
          duplicate = true
          break
        }
      }
      if !duplicate { result.root.children.append(d) }
    }
  }
  return result
}
public func selectDescriptions(
  _ d: Description, newID: String, limits: Limits = Limits(),
  where predicate: (Description) throws -> Bool
) throws -> DescriptionCopy {
  let items = try containerFields(d)
  let result = try copyDescription(d, newID: newID, limits: limits)
  result.root.children = try items.filter(predicate)
  return result
}
public func copyWithout(
  _ d: Description, excluding: Description, newID: String, limits: Limits = Limits()
) throws -> DescriptionCopy {
  let work = CompositionWork(limits)
  return try selectDescriptions(d, newID: newID, limits: limits) { try !work.equal($0, excluding) }
}
public func copyWithoutAll(
  _ d: Description, excluding: [Description], newID: String, limits: Limits = Limits()
) throws -> DescriptionCopy {
  try require(excluding.count <= limits.items, "Excluded item limit")
  let work = CompositionWork(limits)
  return try selectDescriptions(d, newID: newID, limits: limits) { item in
    for e in excluding { if try work.equal(item, e) { return false } }
    return true
  }
}
public func collectDescriptions(
  _ d: Description, newID: String, limits: Limits = Limits(),
  transform: (Description) throws -> Description
) throws -> DescriptionCopy {
  let items = try containerFields(d)
  var result = try copyDescription(d, newID: newID, limits: limits)
  result.root.children = []
  for item in items {
    let next = try transform(item)
    try mergeOwners(&result, next, limits)
    result.root.children.append(next)
  }
  return result
}
public func copyEmpty(_ d: Description, newID: String, limits: Limits = Limits()) throws
  -> DescriptionCopy
{
  _ = try containerFields(d)
  let result = try copyDescription(d, newID: newID, limits: limits)
  result.root.children = []
  return result
}
/// Zero-based half-open native range; upstream copyFrom:to: is one-based inclusive.
public func copyRange(_ d: Description, range: Range<Int>, newID: String, limits: Limits = Limits())
  throws -> DescriptionCopy
{
  let items = try containerFields(d)
  try require(
    range.lowerBound >= 0 && range.upperBound <= items.count, "Composition range outside children")
  let result = try copyDescription(d, newID: newID, limits: limits)
  result.root.children = Array(items[range])
  return result
}
extension Description {
  public func kindOf(_ name: String) -> Bool {
    ClassRegistry.shared.includesBehavior(className,name)
  }
}
