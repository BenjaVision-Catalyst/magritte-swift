import Foundation

public func portableClasses() -> [String] { ClassRegistry.shared.allClasses() }
func knownClass(_ name: String) -> Bool { ClassRegistry.shared.find(name) != nil }

public final class AccessorObject {
  public var id: String
  public var value: Accessor
  public var accessor: AccessorObject?, next: AccessorObject?
  public init(id: String, value: Accessor) {
    self.id = id
    self.value = value
  }
  public static func fromAccessor(id: String, _ value: Accessor, limits: Limits = Limits()) throws
    -> AccessorObject
  {
    try value.check(limits: limits)
    var count = 0
    func build(_ id: String, _ a: Accessor, _ depth: Int) throws -> AccessorObject {
      count += 1
      try require(
        count <= limits.nodes && count <= limits.visits && depth <= limits.depth,
        "Accessor object construction limit")
      try checkReflectionID(id, limits)
      var leaf = a
      leaf.steps = []
      let object = AccessorObject(id: id, value: leaf)
      if a.className == "MADelegatorAccessor" {
        object.next = try build(id + ".next", a.steps[0], depth + 1)
      } else if a.className == "MAChainAccessor" {
        object.accessor = try build(id + ".accessor", a.steps[0], depth + 1)
        var tail = a.steps.count == 2 ? a.steps[1] : a
        if a.steps.count > 2 { tail.steps = Array(a.steps.dropFirst()) }
        object.next = try build(id + ".next", tail, depth + 1)
      }
      return object
    }
    return try build(id, value, 0)
  }
  public func snapshot(limits: Limits = Limits()) throws -> Accessor {
    var active = Set<ObjectIdentifier>()
    var count = 0
    func make(_ object: AccessorObject, _ depth: Int) throws -> Accessor {
      count += 1
      try require(
        count <= limits.visits && count <= limits.nodes && depth <= limits.depth,
        "Accessor object snapshot limit")
      try checkReflectionID(object.id, limits)
      try require(active.insert(ObjectIdentifier(object)).inserted, "Accessor object cycle")
      var a = object.value
      try require(a.steps.isEmpty, "Object accessor uses slots, not inline steps")
      if a.className == "MAChainAccessor" {
        guard let accessor = object.accessor, let next = object.next else {
          throw MagritteError("Chain requires accessor and next")
        }
        a.steps = [try make(accessor, depth + 1)]
        let tail = try make(next, depth + 1)
        a.steps += tail.className == "MAChainAccessor" ? tail.steps : [tail]
      } else if a.className == "MADelegatorAccessor" {
        guard object.accessor == nil, let next = object.next else {
          throw MagritteError("Delegator requires only next")
        }
        a.steps = [try make(next, depth + 1)]
      } else {
        try require(
          object.accessor == nil && object.next == nil, "Leaf accessor has unexpected slots")
      }
      active.remove(ObjectIdentifier(object))
      return a
    }
    let result = try make(self, 0)
    try result.check(limits: limits)
    return result
  }
}
public final class ConditionObject {
  public var id: String, predicate: Predicate
  public init(id: String, predicate: Predicate) {
    self.id = id
    self.predicate = predicate
  }
  public func evaluate(_ value: Value, limits: Limits = Limits()) throws -> Bool {
    try predicate.evaluate(value, limits: limits)
  }
}
func checkReflectionID(_ id: String, _ limits: Limits) throws {
  try require(
    !id.isEmpty && id.utf8.count <= limits.bytes && id.utf8.allSatisfy { $0 >= 33 && $0 <= 126 },
    "Invalid reflection object identity")
}
