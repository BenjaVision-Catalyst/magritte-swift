import Foundation

/// A local Magritte object. Equality and hashing depend on species, not kind or text.
public final class CompositeConflict: Equatable, Hashable, CustomStringConvertible {
  public var kind: String?, stringValue: String?
  public init(kind: String? = nil, string: String? = nil) {
    self.kind = kind
    self.stringValue = string
  }
  public var string: String { stringValue ?? "(Multiple values)" }
  public var description: String { string }
  public static func == (_ a: CompositeConflict, _ b: CompositeConflict) -> Bool { true }
  public func hash(into hasher: inout Hasher) { hasher.combine("MACompositeConflict") }
  public func copy() -> CompositeConflict { CompositeConflict(kind: kind, string: stringValue) }
  public func kindOf(_ name: String) -> Bool {
    kind == name || ClassRegistry.shared.includesBehavior("MACompositeConflict", name)
  }
  /// Mirrors doesNotUnderstand:. Host class protocol discovery is explicit.
  public func doesNotUnderstand(
    _ selector: String,
    canUnderstand: (String, String) throws -> Bool
  ) throws -> String {
    guard let kind, try canUnderstand(kind, selector) else {
      throw MagritteError("Message not understood: " + selector)
    }
    return string
  }
}
extension Value {
  public var conflict: CompositeConflict? {
    if case .conflict(let c) = self { return c }
    return nil
  }
}
extension Accessor {
  public static func composite(head: Accessor, next: Accessor, kind: String? = nil) -> Accessor {
    var result = Accessor(className: "MACompositeAccessor", steps: [head, next])
    result.kind = kind
    return result
  }
  public static func compositeVia(_ head: Accessor, using d: Description, limits: Limits = Limits())
    throws -> Accessor
  {
    let type = try d.property("kind", limits: limits)
    let kind: String?
    if type.isNil {
      kind = nil
    } else if case .classValue(let name) = type {
      kind = name
    } else {
      throw MagritteError("Description kind must be Class or nil")
    }
    let result = try composite(head: head, next: d.effectiveAccessor, kind: kind)
    try result.check(limits: limits)
    if try d.hasLabel(limits: limits) {
      guard case .string(let label) = try d.property("label", limits: limits) else {
        throw MagritteError("Expected label")
      }
      let combined = try head.defaultLabel(for: d, limits: limits) + "::" + label
      try checkLocalValue(.string(combined), limits: limits)
      d.properties["label"] = .string(combined)
    }
    d.accessor = result
    d.accessorObject = nil
    return result
  }
}
func checkLocalValue(_ value: Value, limits: Limits = Limits()) throws {
  var work = 0
  func project(_ v: Value, _ depth: Int) throws -> Value {
    work += 1
    try require(work <= limits.visits && depth <= limits.depth, "Local value work/depth limit")
    switch v {
    case .conflict(let c):
      if let kind = c.kind { try require(knownClass(kind), "Unknown conflict kind") }
      return .array([.string(c.string)] + (c.kind.map { [.string($0)] } ?? []))
    case .array(let values):
      try require(values.count <= limits.items, "Local value item limit")
      return .array(try values.map { try project($0, depth + 1) })
    case .collection(let kind, let values):
      try require(values.count <= limits.items, "Local value item limit")
      try require(["set", "ordered", "bag"].contains(kind), "Unsupported collection kind")
      if kind == "set" {
        var keys = Set<String>()
        for e in values {
          let key = try valueKey(
            e,
            tick: { d in
              work += 1
              try require(
                work <= limits.visits && d <= limits.depth, "Local set work/depth limit")
            }, depth: depth + 1)
          try require(keys.insert(key).inserted, "Duplicate set element")
        }
        return .array(try values.map { try project($0, depth + 1) })
      }
      return .collection(kind: kind, elements: try values.map { try project($0, depth + 1) })
    default: return v
    }
  }
  _ = try encodeValue(project(value, 0), limits: limits)
}
