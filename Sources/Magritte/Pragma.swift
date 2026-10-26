import Foundation

public struct DescriptionTarget {
  public let model: Model, className: String, identity: AnyObject
  public init(_ model: Model, className: String, identity: AnyObject? = nil) {
    self.model = model
    self.className = className
    self.identity = identity ?? model
  }
}
public struct DescriptionPragma {
  public var selector: String, arguments: [Value]
  public init(_ selector: String, arguments: [Value] = []) {
    self.selector = selector
    self.arguments = arguments
  }
}
public struct DescriptionRequest { public let target: DescriptionTarget, builder: PragmaBuilder }
public struct DescriptionMethod {
  public var className: String, selector: String, arguments: Int, pragmas: [DescriptionPragma]
  public var operation: (DescriptionRequest, Description?) throws -> DescriptionCopy?
  public init(
    className: String, selector: String, arguments: Int = 0, pragmas: [DescriptionPragma] = [],
    operation: @escaping (DescriptionRequest, Description?) throws -> DescriptionCopy?
  ) {
    self.className = className
    self.selector = selector
    self.arguments = arguments
    self.pragmas = pragmas
    self.operation = operation
  }
}
private func methodIdentity(_ name: String) throws {
  try require(
    !name.isEmpty && name.utf8.allSatisfy { $0 >= 33 && $0 <= 126 },
    "Invalid description method identity")
}
public final class DescriptionMethodRegistry: @unchecked Sendable {
  public static let shared = DescriptionMethodRegistry()
  private let lock = NSLock()
  private var methods: [String: [DescriptionMethod]] = [:]
  private init() {
    methods["Object"] = [
      DescriptionMethod(
        className: "Object", selector: "descriptionContainer",
        pragmas: [DescriptionPragma("magritteContainer")]
      ) { request, _ in
        let d = Description(id: try request.builder.freshID(), className: "MAPriorityContainer")
        guard let info = ClassRegistry.shared.find(request.target.className) else {
          throw MagritteError("Unknown model class")
        }
        d.properties["label"] = .string(info.label)
        return DescriptionCopy(root: d, retained: [d])
      }
    ]
  }
  public func install(_ method: DescriptionMethod) throws {
    try methodIdentity(method.className)
    try methodIdentity(method.selector)
    try require(
      ClassRegistry.shared.find(method.className) != nil && method.arguments >= 0,
      "Unregistered description method class/arity")
    for pragma in method.pragmas {
      try methodIdentity(pragma.selector)
      try require(
        pragma.selector.filter { $0 == ":" }.count == pragma.arguments.count,
        "Pragma arity mismatch")
      for arg in pragma.arguments { _ = try encodeValue(arg) }
    }
    lock.lock()
    defer { lock.unlock() }
    var entries = methods[method.className] ?? []
    if let i = entries.firstIndex(where: { $0.selector == method.selector }) {
      entries[i] = method
    } else {
      entries.append(method)
    }
    methods[method.className] = entries
  }
  public func remove(className: String, selector: String) {
    lock.lock()
    defer { lock.unlock() }
    methods[className]?.removeAll { $0.selector == selector }
  }
  public func lookup(className: String, selector: String) throws -> DescriptionMethod? {
    var cls: String? = className
    while let name = cls {
      lock.lock()
      let entries = methods[name] ?? []
      lock.unlock()
      if let found = entries.first(where: { $0.selector == selector }) { return found }
      guard let info = ClassRegistry.shared.find(name) else {
        throw MagritteError("Unknown method lookup class")
      }
      cls = info.superclass
    }
    return nil
  }
  public func annotated(className: String, pragma: String) throws -> [DescriptionMethod] {
    var cls: String? = className
    var result: [DescriptionMethod] = []
    while let name = cls {
      lock.lock()
      let entries = methods[name] ?? []
      lock.unlock()
      for method in entries {
        for tag in method.pragmas where tag.selector == pragma {
          var tagged = method
          tagged.pragmas = [tag]
          result.append(tagged)
        }
      }
      if name == "Object" { break }
      guard let info = ClassRegistry.shared.find(name) else {
        throw MagritteError("Unknown pragma lookup class")
      }
      cls = info.superclass
    }
    return result
  }
}
public final class DescriptionContext: Equatable, Hashable {
  public var modelClass: String?, methodSelector: String?
  public init(modelClass: String? = nil, methodSelector: String? = nil) {
    self.modelClass = modelClass
    self.methodSelector = methodSelector
  }
  public static func == (_ a: DescriptionContext, _ b: DescriptionContext) -> Bool {
    a.modelClass == b.modelClass && a.methodSelector == b.methodSelector
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(modelClass)
    hasher.combine(methodSelector)
  }
  public func compiledMethod() throws -> DescriptionMethod? {
    guard let cls = modelClass else {
      throw MagritteError("Description context has no model class")
    }
    guard let selector = methodSelector else { return nil }
    return try DescriptionMethodRegistry.shared.lookup(className: cls, selector: selector)
  }
  public func methodClass() throws -> String? { try compiledMethod()?.className }
}
private final class PragmaThreadState {
  var cache: DynamicDescriptionCache?, described: DescriptionTarget?
}
private func dynamicState() -> PragmaThreadState {
  let key = "Magritte.NativePragmaDynamicScope"
  if let state = Thread.current.threadDictionary[key] as? PragmaThreadState { return state }
  let state = PragmaThreadState()
  Thread.current.threadDictionary[key] = state
  return state
}
public func withDescriptionCache<T>(_ cache: DynamicDescriptionCache, _ body: () throws -> T)
  rethrows -> T
{
  let state = dynamicState()
  let old = state.cache
  state.cache = cache
  defer { state.cache = old }
  return try body()
}
public func withDescribedObject<T>(_ target: DescriptionTarget, _ body: () throws -> T) rethrows
  -> T
{
  let state = dynamicState()
  let old = state.described
  state.described = target
  defer { state.described = old }
  return try body()
}
public enum DescribedObject {
  public static var current: DescriptionTarget? { dynamicState().described }
}
public final class DynamicDescriptionCache {
  fileprivate struct Entry {
    let target: DescriptionTarget
    let root: Description?
  }
  fileprivate var entries: [ObjectIdentifier: Entry] = [:], owners: [String: Description] = [:],
    lifetimes: [AnyObject] = []
  fileprivate let prefix: String, limits: Limits
  fileprivate var serial = 0, work = 0, depth = 0
  public init(idPrefix: String = "description", limits: Limits = Limits()) throws {
    try methodIdentity(idPrefix)
    prefix = idPrefix
    self.limits = limits
  }
  public static var current: DynamicDescriptionCache {
    get throws {
      if let cache = dynamicState().cache { return cache }
      return try DynamicDescriptionCache()
    }
  }
  public var count: Int { entries.count }
  fileprivate func tick(_ depth: Int = 0) throws {
    work += 1
    try require(work <= limits.visits && depth <= limits.depth, "Pragma discovery work/depth limit")
  }
  fileprivate func retain(_ result: DescriptionCopy?) throws {
    guard let result else { return }
    if let lifetime = result.lifetime, lifetime !== self { lifetimes.append(lifetime) }
    var pending = result.retained.map { ($0, 0) }
    pending.append((result.root, 0))
    var seen = Set<ObjectIdentifier>()
    while let (d, depth) = pending.popLast() {
      try tick(depth)
      if !seen.insert(ObjectIdentifier(d)).inserted { continue }
      try require(
        owners[d.id] == nil || owners[d.id] === d, "Discovery description identity collision")
      if owners[d.id] == nil {
        try require(owners.count < limits.nodes, "Discovery owner limit")
        try methodIdentity(d.id)
        owners[d.id] = d
      }
      try require(d.children.count <= limits.items, "Discovery item limit")
      pending += d.children.map { ($0, depth + 1) }
      if d.isReference, let ref = try storedReference(d) { pending.append((ref, depth + 1)) }
    }
  }
  fileprivate func result(_ root: Description?) -> DescriptionCopy? {
    guard let root else { return nil }
    return DescriptionCopy(root: root, retained: Array(owners.values), lifetime: self)
  }
}
open class PragmaBuilder {
  public let limits: Limits
  public init(limits: Limits = Limits()) { self.limits = limits }
  open var containerPragma: String { "magritteContainer" }
  open var descriptionPragma: String { "magritteDescription" }
  open var extensionPragma: String { "magritteDescription:" }
  public func freshID() throws -> String {
    guard let cache = dynamicState().cache else {
      throw MagritteError("No dynamic description cache")
    }
    try cache.tick()
    cache.serial += 1
    return cache.prefix + "." + String(cache.serial)
  }
  private func invoke(
    _ target: DescriptionTarget, _ selector: String, _ argument: Description?, _ count: Int
  ) throws -> DescriptionCopy? {
    guard let cache = dynamicState().cache else {
      throw MagritteError("No dynamic description cache")
    }
    try cache.tick(cache.depth)
    guard
      let method = try DescriptionMethodRegistry.shared.lookup(
        className: target.className, selector: selector), method.arguments == count
    else { throw MagritteError("Description method dispatch/arity failure: " + selector) }
    let result = try method.operation(DescriptionRequest(target: target, builder: self), argument)
    try cache.retain(result)
    return result
  }
  public func forTarget(_ target: DescriptionTarget, idPrefix: String) throws -> DescriptionCopy? {
    try require(
      ClassRegistry.shared.includesBehavior(target.className, "Object"), "Invalid described target")
    let cache =
      try dynamicState().cache ?? DynamicDescriptionCache(idPrefix: idPrefix, limits: limits)
    return try withDescriptionCache(cache) {
      try cache.tick(cache.depth)
      let identity = ObjectIdentifier(target.identity)
      if let hit = cache.entries[identity] { return cache.result(hit.root) }
      try require(cache.depth < cache.limits.depth, "Pragma recursive container depth limit")
      cache.depth += 1
      defer { cache.depth -= 1 }
      let registry = DescriptionMethodRegistry.shared
      let containers = try registry.annotated(className: target.className, pragma: containerPragma)
      try require(containers.count <= cache.limits.items, "Container pragma item limit")
      guard let getter = containers.first(where: { $0.arguments == 0 }) else {
        throw MagritteError("No container pragma getter")
      }
      let root: Description? = try withDescribedObject(target) {
        let root = try invoke(target, getter.selector, nil, 0)?.root
        for method in containers where method.arguments == 1 {
          _ = try invoke(target, method.selector, root, 1)
        }
        return root
      }
      try require(cache.entries.count < cache.limits.nodes, "Description cache target limit")
      cache.entries[identity] = DynamicDescriptionCache.Entry(target: target, root: root)
      let declarations = try registry.annotated(
        className: target.className, pragma: descriptionPragma)
      let extensions = try registry.annotated(className: target.className, pragma: extensionPragma)
      try require(
        declarations.count <= cache.limits.items && extensions.count <= cache.limits.items,
        "Description pragma item limit")
      let selectors = Set(declarations.map(\.selector)).sorted()
      var extensionSelectors: [String: [String]] = [:]
      for method in extensions {
        for pragma in method.pragmas where pragma.selector == extensionPragma {
          if let value = pragma.arguments.first {
            let name: String
            switch value {
            case .symbol(let s), .string(let s): name = s
            default: continue
            }
            extensionSelectors[name, default: []].append(method.selector)
          }
        }
      }
      for key in extensionSelectors.keys { extensionSelectors[key]?.sort() }
      var fields: [Description] = []
      for selector in selectors {
        guard let initial = try invoke(target, selector, nil, 0)?.root else { continue }
        initial.definingContext = DescriptionContext(
          modelClass: target.className, methodSelector: selector)
        var result: Description? = initial
        for ext in extensionSelectors[selector] ?? [] {
          result = try invoke(target, ext, initial, 1)?.root
        }
        if let result { fields.append(result) }
      }
      guard let root, root.isContainer else {
        throw MagritteError("Container does not understand addAll:")
      }
      try require(
        root.children.count + fields.count <= cache.limits.items, "Discovered container item limit")
      root.children += fields
      try cache.retain(DescriptionCopy(root: root))
      return cache.result(root)
    }
  }
}
