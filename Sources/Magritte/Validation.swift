import Foundation

public final class ValidationIssue {
  public let tag: Description
  public let code: String
  public let signalText: String?
  public let collection: [ValidationIssue]
  public init(
    tag: Description, code: String, signalText: String?, collection: [ValidationIssue] = []
  ) throws {
    try require(
      ClassRegistry.shared.includesBehavior(code, "MAValidationError"),
      "Validation issue class must inherit MAValidationError")
    try require(
      collection.isEmpty || ClassRegistry.shared.includesBehavior(code, "MAMultipleErrors"),
      "Only multiple errors have a collection")
    self.tag = tag
    self.code = code
    self.signalText = signalText
    self.collection = collection
  }
  public var isResumable: Bool { true }
  public var messageText: String { signalText ?? "" }
  public func kindOf(_ name: String) -> Bool { ClassRegistry.shared.includesBehavior(code, name) }
  public func printString(limits: Limits = Limits()) throws -> String {
    var output = ""
    var work = 0
    func append(_ text: String) throws {
      try require(
        text.utf8.count <= limits.bytes - output.utf8.count, "Validation print byte limit")
      output += text
    }
    func walk(_ e: ValidationIssue, _ depth: Int) throws {
      work += 1
      try require(
        work <= limits.visits && depth <= limits.depth && e.collection.count <= limits.items,
        "Validation print work/depth/item limit")
      if e.kindOf("MAMultipleErrors") {
        for (i, child) in e.collection.enumerated() {
          if i > 0 { try append("\r") }
          try walk(child, depth + 1)
        }
      } else {
        let label = try e.tag.property("label", limits: limits)
        if !label.isNil {
          try append(displayString(label))
          try append(": ")
        }
        try append(e.messageText)
      }
    }
    try walk(self, 0)
    return output
  }
}
// Swift Error requires Sendable. The retained live tag remains caller-confined.
public struct ValidationFailure: Error, @unchecked Sendable {
  public let error: ValidationIssue
  public init(_ error: ValidationIssue) { self.error = error }
}
public struct ValidationResult {
  public let error: ValidationIssue?
  public init(error: ValidationIssue? = nil) { self.error = error }
  public var passed: Bool { error == nil }
  public func raiseIfInvalid() throws { if let error { throw ValidationFailure(error) } }
  public func flatErrors(limits: Limits = Limits()) throws -> [ValidationError] {
    var result: [ValidationError] = []
    var work = 0
    func walk(_ e: ValidationIssue, _ depth: Int) throws {
      work += 1
      try require(
        work <= limits.visits && depth <= limits.depth && e.collection.count <= limits.items,
        "Validation projection limit")
      if e.kindOf("MAMultipleErrors") && !e.collection.isEmpty {
        for child in e.collection { try walk(child, depth + 1) }
      } else {
        try require(result.count < limits.items, "Validation leaf item limit")
        result.append(
          ValidationError(descriptionID: e.tag.id, code: e.code, message: e.messageText))
      }
    }
    if let error { try walk(error, 0) }
    return result
  }
}
public final class ValidationContext {
  private let description: Description, limits: Limits
  private var errors: [ValidationIssue] = []
  public init(_ description: Description, limits: Limits = Limits()) {
    self.description = description
    self.limits = limits
  }
  public var count: Int { errors.count }
  @discardableResult public func signal(_ code: String, text: String?) throws -> ValidationIssue {
    try require(
      errors.count < limits.items && errors.count < limits.visits,
      "Validation error item/work limit")
    if let text {
      try require(text.utf8.count <= limits.bytes, "Validation message byte limit")
      var l = limits
      l.bytes = Int.max
      try checkLocalValue(.string(text), limits: l)
    }
    let error = try ValidationIssue(tag: description, code: code, signalText: text)
    errors.append(error)
    return error
  }
  public func include(_ result: ValidationResult) throws {
    if let error = result.error {
      try require(
        errors.count < limits.items && errors.count < limits.visits,
        "Validation error item/work limit")
      errors.append(error)
    }
  }
  public func tryValidation(
    _ body: (ValidationContext) throws -> Void, ifPass: (ValidationContext) throws -> Void
  ) throws {
    let previous = errors.count
    try body(self)
    if errors.count == previous { try ifPass(self) }
  }
  public func finish() throws -> ValidationResult {
    if errors.isEmpty { return ValidationResult() }
    let label = try description.property("label", limits: limits)
    return ValidationResult(
      error: try ValidationIssue(
        tag: description, code: "MAMultipleErrors",
        signalText: label.isNil ? nil : displayString(label), collection: errors))
  }
}
private struct ValidationTarget {
  var value: Value?
  var model: Model?
  init(_ value: Value? = nil, model: Model? = nil) {
    self.value = value
    self.model = model
  }
}
private final class Validator {
  let graph: Graph?, limits: Limits
  var work = 0, collections = Set<ObjectIdentifier>()
  init(_ graph: Graph?, _ limits: Limits) {
    self.graph = graph
    self.limits = limits
  }
  func tick(_ depth: Int) throws {
    work += 1
    try require(work <= limits.visits && depth <= limits.depth, "Validation work/depth limit")
  }
  func model(_ t: ValidationTarget) throws -> Model? {
    if let m = t.model { return m }
    if let v = t.value, case .reference = v {
      guard let graph else {
        throw MagritteError("Object reference validation requires a graph resolver")
      }
      return try graph.resolve(v)
    }
    return nil
  }
  func boolean(_ v: Value) throws -> Bool {
    try checkRuntimeValue(v, limits, &work)
    guard case .boolean(let b) = v else {
      throw MagritteError("Validation message must return Boolean")
    }
    return b
  }
  func kind(_ t: ValidationTarget, _ cls: String) throws -> Bool {
    if let m = t.model { return m.kindOf(cls) }
    return try validationKindOf(t.value!, cls, graph)
  }
  func references(_ v: Value, _ depth: Int) throws {
    try tick(depth)
    switch v {
    case .mutableCollection(let ref):
      if !collections.insert(try ref.identity()).inserted { return }
      try references(ref.snapshot(), depth)
    case .reference: _ = try model(ValidationTarget(v))
    case .array(let a), .collection(_, let a):
      try require(a.count <= limits.items, "Validation collection item limit")
      for e in a { try references(e, depth + 1) }
    default: break
    }
  }
  func undefined(_ t: ValidationTarget, _ d: Description) throws -> Bool {
    let sentinel = try d.property("undefinedValue", limits: limits)
    if let m = try model(t) {
      return try boolean(m.binaryMessage("=", argument: sentinel, graph: graph))
    }
    return try equalRuntimeValues(t.value!, sentinel, limits, &work)
  }
  func emit(_ c: ValidationContext, _ d: Description, _ code: String, _ depth: Int) throws {
    try tick(depth)
    try c.signal(code, text: validationMessage(d, code, limits))
  }
  func kindStage(_ d: Description, _ t: ValidationTarget, _ c: ValidationContext, _ depth: Int)
    throws
  {
    guard case .classValue(let cls) = try d.property("kind", limits: limits) else {
      throw MagritteError("Description kind is nil")
    }
    let before = c.count
    if try !kind(t, cls) { try emit(c, d, "MAKindError", depth) }
    let multipleRelation = descriptionIs(d, "MAToManyRelationDescription")
    let multipleOption = descriptionIs(d, "MAMultipleOptionDescription")
    if (multipleRelation || multipleOption) && before != c.count { return }
    func relation(_ v: Value) throws {
      var accepted = false
      for cls in d.classes {
        try tick(depth)
        if try kind(ValidationTarget(v), cls) { accepted = true }
      }
      if !accepted { try emit(c, d, "MAKindError", depth) }
    }
    func option(_ v: Value) throws {
      var member = false
      if case .dynamic(let source) = d.options {
        member = try source.includes(v, limits: limits)
      } else {
        for o in try d.options.values(limits: limits) {
          try tick(depth)
          if try equalRuntimeValues(v, o, limits, &work) {
            member = true
            break
          }
        }
      }
      if member { return }
      if try !d.flag("extensible") {
        try emit(c, d, "MAKindError", depth)
      } else {
        try c.include(run(d.referenceDescription(), ValidationTarget(v), depth + 1))
      }
    }
    if d.isRelation {
      if multipleRelation {
        guard let v = t.value else {
          throw MagritteError(
            "Native model collection enumeration requires an explicit Value adapter")
        }
        for e in try v.elements() {
          try tick(depth)
          try relation(e)
        }
      } else if let v = t.value {
        try relation(v)
      } else {
        var accepted = false
        for cls in d.classes {
          try tick(depth)
          if try kind(t, cls) { accepted = true }
        }
        if !accepted { try emit(c, d, "MAKindError", depth) }
      }
    } else if d.isOption {
      guard let v = t.value else {
        throw MagritteError("Native model options require an explicit Value adapter")
      }
      if multipleOption {
        for e in try v.elements() {
          try tick(depth)
          try option(e)
        }
      } else {
        try option(v)
      }
    }
  }
  func own(_ d: Description, _ t: ValidationTarget, _ c: ValidationContext, _ depth: Int) throws {
    if try d.flag("required"), let v = t.value, v.isNil { try emit(c, d, "MARequiredError", depth) }
    if try d.flag("required"), d.isMultiple, let v = t.value, v.isCollection,
      try v.collectionCount() == 0
    {
      try emit(c, d, "MARequiredError", depth)
    }
    if try undefined(t, d) { return }
    try c.tryValidation(
      { stage in try self.kindStage(d, t, stage, depth) },
      ifPass: { stage in
        if descriptionIs(d, "MANumberDescription") {
          guard let v = t.value else {
            throw MagritteError("Native magnitude requires an explicit Value adapter")
          }
          let min = try d.property("min")
          let max = try d.property("max")
          if try (!min.isNil && compareNumbers(v, min) < 0)
            || (!max.isNil && compareNumbers(v, max) > 0)
          {
            try self.emit(stage, d, "MARangeError", depth)
          }
        }
        for condition in d.portableConditions {
          try self.tick(depth)
          let pass: Bool
          if let m = try self.model(t) {
            pass = try evaluateModelPredicate(
              condition.predicate, m, self.graph, self.limits, &self.work)
          } else {
            pass = try evaluatePredicate(
              condition.predicate, t.value!, limits: self.limits, work: &self.work)
          }
          if !pass { try stage.signal("MAConditionError", text: condition.label) }
        }
        for condition in d.conditions {
          try self.tick(depth)
          let pass: Bool
          if let test = condition.modelTest {
            guard let m = try self.model(t) else {
              throw MagritteError("Model condition requires an actual model target")
            }
            pass = try test(m)
          } else {
            guard let test = condition.test else {
              throw MagritteError("Missing local condition function")
            }
            guard let value = t.value else {
              throw MagritteError("Native model condition requires a modelTest binding")
            }
            pass = try test(value)
          }
          if !pass { try stage.signal("MAConditionError", text: condition.label) }
        }
      })
  }
  func run(_ d: Description, _ t: ValidationTarget, _ depth: Int) throws -> ValidationResult {
    try tick(depth)
    try supported(d)
    try checkPortableDescription(d, limits: limits, work: &work)
    if try !d.flag("visible") || d.flag("readOnly") { return ValidationResult() }
    if let v = t.value {
      try checkRuntimeValue(v, limits, &work)
      try references(v, depth)
    }
    let context = ValidationContext(d, limits: limits)
    try own(d, t, context, depth)
    if d.isContainer {
      if let m = try model(t) {
        for child in try enumerationChildren(d, limits: limits) {
          try tick(depth)
          let identity =
            try child.isContainer && !m.usesStoredContainerValues && child.nativeRead == nil
            && ((child.accessor == nil && child.accessorObject == nil)
              || child.effectiveAccessor.className == "MAIdentityAccessor")
          if identity {
            try context.include(run(child, ValidationTarget(model: m), depth + 1))
          } else {
            let value = try m.read(using: child)
            try context.include(run(child, ValidationTarget(value), depth + 1))
          }
        }
      } else if let value = t.value, !value.isNil {
        throw MagritteError("Container value requires an object reference")
      }
    }
    return try context.finish()
  }
  func preflight(_ d: Description) throws {
    try visit(d, limits: limits) {
      try supported($0)
      try checkPortableDescription($0, limits: self.limits, work: &self.work)
    }
  }
}
public func validateValueDetailed(
  _ value: Value, using d: Description, graph: Graph? = nil, limits: Limits = Limits()
) throws -> ValidationResult {
  let validator = Validator(graph, limits)
  try validator.preflight(d)
  return try validator.run(d, ValidationTarget(value), 0)
}
public func validateDetailed(
  _ model: Model, using d: Description, limits: Limits = Limits(), graph: Graph? = nil
) throws -> ValidationResult {
  let validator = Validator(graph, limits)
  try validator.preflight(d)
  if d.isContainer { return try validator.run(d, ValidationTarget(model: model), 0) }
  if try !d.flag("visible") || d.flag("readOnly") { return ValidationResult() }
  return try validator.run(d, ValidationTarget(model.read(using: d)), 0)
}
public func isSatisfiedBy(
  _ value: Value, using d: Description, graph: Graph? = nil, limits: Limits = Limits()
) throws -> Bool { try validateValueDetailed(value, using: d, graph: graph, limits: limits).passed }
public func isSatisfiedBy(
  _ model: Model, using d: Description, limits: Limits = Limits(), graph: Graph? = nil
) throws -> Bool { try validateDetailed(model, using: d, limits: limits, graph: graph).passed }

func evaluateModelPredicate(
  _ p: Predicate, _ model: Model, _ graph: Graph?, _ limits: Limits, _ work: inout Int
) throws -> Bool {
  try p.check(limits: limits)
  work += 1
  try require(work <= limits.visits, "Model condition work limit")
  if p.className == "MANegationCondition" {
    return try !evaluateModelPredicate(p.children[0], model, graph, limits, &work)
  }
  if p.className == "MAConjunctiveCondition" {
    for child in p.children {
      if try !evaluateModelPredicate(child, model, graph, limits, &work) { return false }
    }
    return true
  }
  try require(
    p.index == 0,
    "Portable model conditions require receiver index zero; bind a native model condition for model arguments"
  )
  if p.selector == "isNil" { return false }
  if p.selector == "notNil" { return true }
  if p.selector == "isInteger" { return model.kindOf("Integer") }
  let result: Value
  if p.arguments.isEmpty {
    result = try model.readSlot(strategy: "MASelectorAccessor", name: p.selector)
  } else if p.arguments.count == 1 {
    result = try model.binaryMessage(p.selector, argument: p.arguments[0], graph: graph)
  } else {
    throw MagritteError("Model condition requires an explicit multiargument native binding")
  }
  try checkRuntimeValue(result, limits, &work)
  guard case .boolean(let pass) = result else {
    throw MagritteError("Model condition message must return Boolean")
  }
  return pass
}
