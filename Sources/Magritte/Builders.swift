import Foundation

public struct BuilderStep {
  public var operation: (Description?, String, DescriptionBuilder) throws -> DescriptionCopy?
  public init(
    _ operation: @escaping (Description?, String, DescriptionBuilder) throws -> DescriptionCopy?
  ) { self.operation = operation }
  public static func named(_ name: String) -> BuilderStep {
    BuilderStep { source, prefix, context in
      let factory = try builderFactory(name)
      if context.environment.budget == nil { context.environment.budget = BuilderBudget() }
      let budget = context.environment.budget!
      if budget.depth == 0 { budget.work = 0 }
      budget.work += 1
      try require(
        budget.depth < context.limits.depth && budget.work <= context.limits.visits,
        "Builder pipeline depth/work limit")
      budget.depth += 1
      defer { budget.depth -= 1 }
      let builder = factory(context.limits)
      builder.environment = context.environment
      builder.model = context.model
      guard let source else { throw MagritteError("Nil builder input") }
      if let value = context.targetValue {
        return try builder.buildFromValue(source, newIDPrefix: prefix, target: value)
      }
      return try builder.buildFrom(source, newIDPrefix: prefix, target: context.target)
    }
  }
}
final class BuilderBudget { var depth = 0, work = 0 }
public struct BuilderEnvironment {
  var budget: BuilderBudget?
  public var graph: Graph?
  public var describe: ((Model?) throws -> Description?)?
  public var tabDisplay: ((Description) throws -> Bool)?,
    groupExpandOnLabel: ((Description) throws -> Bool)?
  public var addToAccessor: ((Description, Accessor) throws -> Void)?
  public var descriptionBuilders: ((Description) throws -> [BuilderStep])?
  public init() {}
}
private final class BuilderFactories: @unchecked Sendable {
  static let shared = BuilderFactories()
  let lock = NSLock()
  var values: [String: (Limits) -> DescriptionBuilder] = [
    "MADescriptionBuilder": { DescriptionBuilder(limits: $0) },
    "MAComposedDescriptionBuilder": { ComposedDescriptionBuilder(limits: $0) },
    "MADescriptionFlattener": { DescriptionFlattener(limits: $0) },
  ]
}
private func builderFactory(_ name: String) throws -> (Limits) -> DescriptionBuilder {
  let registry = BuilderFactories.shared
  registry.lock.lock()
  defer { registry.lock.unlock() }
  guard let factory = registry.values[name] else {
    throw MagritteError("No buildFrom:target:model: implementation: " + name)
  }
  return factory
}
public func registerDescriptionBuilder(
  _ name: String, factory: @escaping (Limits) -> DescriptionBuilder
) throws {
  if ClassRegistry.shared.find(name) == nil {
    try ClassRegistry.shared.registerClass(
      ClassInfo(name: name, superclass: "MADescriptionBuilder"))
  } else {
    try require(
      ClassRegistry.shared.includesBehavior(name, "MADescriptionBuilder"),
      "Class is not a description builder")
  }
  let registry = BuilderFactories.shared
  registry.lock.lock()
  defer { registry.lock.unlock() }
  try require(registry.values[name] == nil, "Builder factory already registered")
  registry.values[name] = factory
}
public func canExpand(_ d: Description, environment: BuilderEnvironment = BuilderEnvironment())
  throws -> Bool
{
  if let value = d.properties["canExpand"] {
    guard case .boolean(let b) = value else { throw MagritteError("canExpand must be Boolean") }
    return b
  }
  if try !d.flag("visible") || d.flag("readOnly") { return false }
  guard let hook = environment.tabDisplay else {
    throw MagritteError("Message not understood: tabDisplay")
  }
  if try hook(d) { return false }
  return try d.property("group").isNil
}
public func setDescriptionBuilders(_ d: Description, classes: [String], limits: Limits = Limits())
  throws
{
  try require(
    d.isContainer && classes.count <= limits.items, "Invalid descriptionBuilders receiver/items")
  let values = Value.array(classes.map(Value.classValue))
  try checkLocalValue(values, limits: limits)
  d.properties["descriptionBuilder"] = .classValue("MAComposedDescriptionBuilder")
  d.properties["descriptionBuilders"] = values
}
extension DescriptionBuilder {
  func targetModel() throws -> Model? {
    guard let v = targetValue else { return target }
    if v.isNil { return nil }
    guard let graph = environment.graph else {
      throw MagritteError("Builder target requires graph resolver")
    }
    return try graph.resolve(v)
  }
  func targetDescription(_ model: Model?) throws -> Description? {
    if let describe = environment.describe { return try describe(model) }
    if let adaptive = model as? AdaptiveModel { return adaptive.description }
    if model == nil { return nil }
    return nil  // undescribed native objects have no annotated fields by default
  }
  func currentTargetDescription() throws -> Description? {
    if let value = targetValue { if case .reference = value {} else { return nil } }
    return try targetDescription(targetModel())
  }
  func stepsFor(_ d: Description) throws -> [BuilderStep] {
    if let provider = environment.descriptionBuilders { return try provider(d) }
    return try d.property("descriptionBuilders").elements().map { value in
      guard case .classValue(let name) = value else {
        throw MagritteError("Builder entry is not an executable Class")
      }
      return .named(name)
    }
  }
  public func buildFromValue(_ source: Description, newIDPrefix: String, target: Value) throws
    -> DescriptionCopy?
  {
    try require(
      !newIDPrefix.isEmpty && newIDPrefix.utf8.allSatisfy { $0 >= 33 && $0 <= 126 },
      "Invalid builder identity prefix")
    try checkLocalValue(target, limits: limits)
    try remember(source)
    prefix = newIDPrefix
    self.target = nil
    targetValue = target
    try visit(source)
    guard let root = builtDescription else { return nil }
    return DescriptionCopy(root: root, retained: retained)
  }
}
open class ComposedDescriptionBuilder: DescriptionBuilder {
  private var pipelineSerial = 0
  private func compose(
    _ source: Description?, _ steps: [BuilderStep], target: Model?, value: Value?
  ) throws {
    try require(steps.count <= limits.items, "Builder pipeline item limit")
    try setBuiltDescriptionRaw(source)
    let oldTarget = self.target
    let oldValue = targetValue
    self.target = target
    targetValue = value
    defer {
      self.target = oldTarget
      targetValue = oldValue
    }
    for step in steps {
      pipelineSerial += 1
      try require(pipelineSerial <= limits.visits, "Builder pipeline work limit")
      let next = try step.operation(
        builtDescription, prefix + ".pipeline." + String(pipelineSerial), self)
      if let next { for owner in next.retained { try remember(owner) } }
      try setBuiltDescriptionRaw(next?.root)
    }
  }
  open override func setBuiltDescription(_ description: Description?) throws {
    let schema = try currentTargetDescription()
    let steps = try schema.map(stepsFor) ?? []
    try compose(description, steps, target: target, value: targetValue)
  }
  open override func visitContainer(_ d: Description) throws {
    try compose(d, stepsFor(d), target: target, value: targetValue)
  }
  open override func visitRelationDescription(_ d: Description) throws {
    let actual = try targetModel()
    let schema = try targetDescription(actual)
    let steps = try schema.map(stepsFor) ?? []
    guard let actual else { throw MagritteError("Nil target readUsing: protocol") }
    let value = try actual.read(using: d)
    if !value.isNil {
      let saved = builtDescription
      defer { builtDescription = saved }
      try compose(d.referenceDescription(), steps, target: nil, value: value)
      d.reference = builtDescription
    }
    try super.visitRelationDescription(d)
  }
}
open class DescriptionFlattener: DescriptionBuilder {
  private var expansionDepth = 0, expansionWork = 0
  open override func visitToOneRelationDescription(_ d: Description) throws {
    if try !canExpand(d, environment: environment) {
      try super.visitToOneRelationDescription(d)
      return
    }
    var sample = target
    if var v = targetValue {
      if v.isCollection {
        if try v.collectionCount() == 0 {
          try super.visitToOneRelationDescription(d)
          return
        }
        v = try v.elements()[0]
      }
      if v.isNil {
        sample = nil
      } else {
        guard let graph = environment.graph else {
          throw MagritteError("Flattener sample requires graph resolver")
        }
        sample = try graph.resolve(v)
      }
    }
    guard let sample else { throw MagritteError("Nil sample readUsing: protocol") }
    let value = try sample.read(using: d)
    if value.isNil {
      try super.visitToOneRelationDescription(d)
    } else {
      try expandDescription(d, for: value)
    }
  }
  public func expandDescription(_ parent: Description, for value: Value) throws {
    if expansionDepth == 0 { expansionWork = 0 }
    try require(expansionDepth < limits.depth, "Flattener depth limit")
    expansionDepth += 1
    defer { expansionDepth -= 1 }
    var model: Model?
    if !value.isNil { guard case .reference = value else { return } }
    if !value.isNil {
      guard let graph = environment.graph else {
        throw MagritteError("Flattener expansion requires graph resolver")
      }
      model = try graph.resolve(value)
    }
    guard let schema = try targetDescription(model) else { return }
    try remember(schema)
    let children = try schema.orderedChildren()
    try require(children.count <= limits.items, "Flattener item limit")
    for child in children {
      expansionWork += 1
      try require(expansionWork <= limits.visits, "Flattener work limit")
      guard let model else { throw MagritteError("Nil expansion readUsing: protocol") }
      let next = try model.read(using: child)
      guard let add = environment.addToAccessor else {
        throw MagritteError("Message not understood: addToAccessor:")
      }
      try add(child, parent.effectiveAccessor)
      child.properties["priority"] = try flattenedPriority(
        parent.priorityValue(), child.priorityValue())
      guard let group = environment.groupExpandOnLabel else {
        throw MagritteError("Message not understood: groupExpandOnLabel")
      }
      child.properties["group"] = try parent.property(group(parent) ? "label" : "group")
      try addToBuiltDescription(child, for: next)
    }
  }
  public func addToBuiltDescription(_ d: Description, for value: Value) throws {
    if try canExpand(d, environment: environment) {
      try expandDescription(d, for: value)
    } else {
      guard let root = builtDescription, root.isContainer else {
        throw MagritteError("Built description cannot add field")
      }
      try require(root.children.count < limits.items, "Flattener item limit")
      try root.add(d, limits: limits)
    }
  }
}
