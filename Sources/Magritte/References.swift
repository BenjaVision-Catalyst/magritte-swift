import Foundation

func freshDescriptionID() -> String { "auto.description." + UUID().uuidString.lowercased() }
// Structural reads preserve nil and must not send the behavioral getter.
func storedReference(_ owner: Description) throws -> Description? {
  if owner.reference == nil && owner.referenceWasBound {
    throw MagritteError("Reference description expired; retain explicit references in the graph")
  }
  return owner.reference
}
func referenceTarget(_ owner: Description) throws -> Description {
  guard let target = try storedReference(owner) else { throw MagritteError("Reference description is uninitialized") }
  return target
}
public enum RelationCommonClass {
  case classValue(String)
  case container(Description)
}
extension Description {
  @discardableResult public func setReference(_ target: Description?) throws -> Description {
    try require(isReference, "Reference setter requires a reference description")
    reference = target
    return self
  }
  public func referenceDescription() throws -> Description {
    if descriptionIs(self, "MABooleanDescription") { return self }
    try require(isReference, "Reference getter requires a reference or Boolean description")
    let target: Description
    if let stored = try storedReference(self) { target = stored }
    else {
      target = Description(id: freshDescriptionID())
      reference = target
      defaultReference = target
    }
    let block = displayBlock
    if block != nil {
      target.properties["displayBlockOrSymbol"] = .undefined
    } else if let setting = properties["displayBlockOrSymbol"] {
      target.properties["displayBlockOrSymbol"] = setting
    } else {
      target.properties.removeValue(forKey: "displayBlockOrSymbol")
    }
    target.displayBlock = block
    return target
  }
  @discardableResult public func setUndefined(_ value: Value, limits: Limits = Limits()) throws
    -> Description
  {
    if !value.isNil {
      guard case .string = value else {
        throw MagritteError("Undefined text must be String or nil")
      }
    }
    try checkLocalValue(value, limits: limits)
    var work = 0
    func apply(_ current: Description, _ depth: Int) throws {
      work += 1
      try require(
        work <= limits.visits && depth <= limits.depth, "Undefined propagation work/depth limit")
      current.properties["undefined"] = value
      if current.isOption {
        _ = try current.referenceDescription()
        try apply(current.referenceDescription(), depth + 1)
      }
    }
    try apply(self, 0)
    return self
  }
}

func makeDescriptionContainer(_ owner: Description) throws -> Description {
  guard let info = ClassRegistry.shared.find(owner.className) else { throw MagritteError("Unknown description class") }
  let result = Description(id: freshDescriptionID(), className: "MAPriorityContainer")
  result.properties["label"] = .string(info.label)
  return result
}
extension Description {
  public func allClasses(limits: Limits = Limits()) throws -> [String] {
    try require(isRelation, "Class choices require a relation description")
    try require(classes.count <= limits.items && classes.count <= limits.visits, "Relation class limit")
    var labels: [String: String] = [:]
    for name in classes {
      guard let info = ClassRegistry.shared.find(name) else { throw MagritteError("Unknown relation class: \(name)") }
      labels[name] = info.label
    }
    var work = classes.count
    func key(_ name: String) throws -> String {
      let text = labels[name]!
      try require(text.utf8.count <= limits.bytes && text.utf8.count <= limits.visits - work, "Relation label limit")
      work += text.utf8.count
      try require(text.utf8.allSatisfy { $0 < 128 }, "Non-ASCII relation class sorting is not implemented")
      return text.lowercased()
    }
    return try classes.sorted { a, b in
      work += 1
      try require(work <= limits.visits, "Relation sorting work limit")
      let left = try key(a), right = try key(b)
      return left < right
    }
  }
  public func commonClass(limits: Limits = Limits()) throws -> RelationCommonClass {
    try require(isRelation, "Common class requires a relation description")
    try require(classes.count <= limits.items && classes.count <= limits.visits, "Relation class limit")
    if classes.isEmpty { return .container(try descriptionContainer()) }
    guard let name = try ClassRegistry.shared.commonSuperclass(classes) else { throw MagritteError("Relation classes have no common class") }
    return .classValue(name)
  }
}
