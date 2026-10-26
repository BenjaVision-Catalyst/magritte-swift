import Foundation

/// MAVisitor's one-object dispatch. Visitors choose whether to traverse children or references.
open class Visitor {
  public let limits: Limits
  private var depth = 0
  private var work = 0
  public init(limits: Limits = Limits()) { self.limits = limits }
  private func during(_ body: () throws -> Void) throws {
    if depth == 0 { work = 0 }
    work += 1
    try require(work <= limits.visits && depth <= limits.depth, "Visitor work/depth limit")
    depth += 1
    defer { depth -= 1 }
    try body()
  }
  open func visit(_ description: Description) throws {
    try during { try description.acceptMagritte(self) }
  }
  open func visitAll(_ descriptions: [Description]) throws {
    try require(descriptions.count <= limits.items, "Visitor item limit")
    try during { for description in descriptions { try visit(description) } }
  }
  open func visitDescription(_ description: Description) throws {}
  open func visitContainer(_ description: Description) throws { try visitDescription(description) }
  open func visitPriorityContainer(_ description: Description) throws {
    try visitContainer(description)
  }
  open func visitElementDescription(_ description: Description) throws {
    try visitDescription(description)
  }
  open func visitBooleanDescription(_ description: Description) throws {
    try visitElementDescription(description)
  }
  open func visitClassDescription(_ description: Description) throws {
    try visitElementDescription(description)
  }
  open func visitStringDescription(_ description: Description) throws {
    try visitElementDescription(description)
  }
  open func visitMemoDescription(_ description: Description) throws {
    try visitStringDescription(description)
  }
  open func visitPasswordDescription(_ description: Description) throws {
    try visitStringDescription(description)
  }
  open func visitSymbolDescription(_ description: Description) throws {
    try visitStringDescription(description)
  }
  open func visitMagnitudeDescription(_ description: Description) throws {
    try visitElementDescription(description)
  }
  open func visitNumberDescription(_ description: Description) throws {
    try visitMagnitudeDescription(description)
  }
  open func visitReferenceDescription(_ description: Description) throws {
    try visitElementDescription(description)
  }
  open func visitTokenDescription(_ description: Description) throws {
    try visitReferenceDescription(description)
  }
  open func visitOptionDescription(_ description: Description) throws {
    try visitReferenceDescription(description)
  }
  open func visitSingleOptionDescription(_ description: Description) throws {
    try visitOptionDescription(description)
  }
  open func visitMultipleOptionDescription(_ description: Description) throws {
    try visitOptionDescription(description)
  }
  open func visitRelationDescription(_ description: Description) throws {
    try visitReferenceDescription(description)
  }
  open func visitToOneRelationDescription(_ description: Description) throws {
    try visitRelationDescription(description)
  }
  open func visitToManyRelationDescription(_ description: Description) throws {
    try visitRelationDescription(description)
  }
  open func visitToManyScalarRelationDescription(_ description: Description) throws {
    try visitToManyRelationDescription(description)
  }
}
func dispatchMagritte(_ description: Description, _ visitor: Visitor) throws {
  var name: String? = description.className
  while let current = name {
    switch current {
    case "MADescription":
      try visitor.visitDescription(description)
      return
    case "MAContainer":
      try visitor.visitContainer(description)
      return
    case "MAPriorityContainer":
      try visitor.visitPriorityContainer(description)
      return
    case "MAElementDescription":
      try visitor.visitElementDescription(description)
      return
    case "MABooleanDescription":
      try visitor.visitBooleanDescription(description)
      return
    case "MAClassDescription":
      try visitor.visitClassDescription(description)
      return
    case "MAStringDescription":
      try visitor.visitStringDescription(description)
      return
    case "MAMemoDescription":
      try visitor.visitMemoDescription(description)
      return
    case "MAPasswordDescription":
      try visitor.visitPasswordDescription(description)
      return
    case "MASymbolDescription":
      try visitor.visitSymbolDescription(description)
      return
    case "MAMagnitudeDescription":
      try visitor.visitMagnitudeDescription(description)
      return
    case "MANumberDescription":
      try visitor.visitNumberDescription(description)
      return
    case "MAReferenceDescription":
      try visitor.visitReferenceDescription(description)
      return
    case "MATokenDescription":
      try visitor.visitTokenDescription(description)
      return
    case "MAOptionDescription":
      try visitor.visitOptionDescription(description)
      return
    case "MASingleOptionDescription":
      try visitor.visitSingleOptionDescription(description)
      return
    case "MAMultipleOptionDescription":
      try visitor.visitMultipleOptionDescription(description)
      return
    case "MARelationDescription":
      try visitor.visitRelationDescription(description)
      return
    case "MAToOneRelationDescription":
      try visitor.visitToOneRelationDescription(description)
      return
    case "MAToManyRelationDescription":
      try visitor.visitToManyRelationDescription(description)
      return
    case "MAToManyScalarRelationDescription":
      try visitor.visitToManyScalarRelationDescription(description)
      return
    default:
      guard let info = ClassRegistry.shared.find(current) else {
        throw MagritteError("Unregistered visited class: \(current)")
      }
      name = info.superclass
    }
  }
  throw MagritteError("Visited class has no implemented Magritte description dispatch")
}

/// MADescriptionBuilder's stateful copy/enrichment protocol. The result retains weak reference targets.
open class DescriptionBuilder: Visitor {
  public var target: Model?
  public var model: Model?
  public var priority: Int64 = 0
  public private(set) var builtDescription: Description?
  private var owners: [ObjectIdentifier: Description] = [:]
  private var identities: [String: ObjectIdentifier] = [:]
  private var retained: [Description] = []
  private var prefix = ""
  private var serial = 0
  private func remember(_ source: Description) throws {
    var pending = [(source, 0)]
    var work = 0
    while let (d, depth) = pending.popLast() {
      work += 1
      try require(
        work <= limits.visits && depth <= limits.depth, "Builder ownership work/depth limit")
      let key = ObjectIdentifier(d)
      if owners[key] != nil { continue }
      try require(identities[d.id] == nil || identities[d.id] == key, "Builder identity collision")
      try require(
        owners.count < limits.nodes && d.children.count <= limits.items,
        "Builder retained node/item limit")
      owners[key] = d
      identities[d.id] = key
      retained.append(d)
      pending += d.children.map { ($0, depth + 1) }
      if d.isReference { pending.append((try d.referenceDescription(), depth + 1)) }
    }
  }
  private func copyForBuild(_ source: Description) throws -> Description {
    serial += 1
    let id = prefix + "." + String(serial)
    try require(identities[id] == nil, "Builder generated identity collision")
    let copied = try copyDescription(source, newID: id, limits: limits)
    for d in copied.retained { try remember(d) }
    return copied.root
  }
  public func setBuiltDescription(_ description: Description?) throws {
    if let description { try remember(description) }
    builtDescription = description
  }
  /// New identities use newIDPrefix.N. A visitor which suppresses every field can return nil.
  public func buildFrom(_ source: Description, newIDPrefix: String, target: Model? = nil) throws
    -> DescriptionCopy?
  {
    try require(
      !newIDPrefix.isEmpty && newIDPrefix.utf8.allSatisfy { $0 >= 33 && $0 <= 126 },
      "Invalid builder identity prefix")
    try remember(source)
    prefix = newIDPrefix
    self.target = target
    // Like upstream, a second buildFrom does not reset the accumulated result.
    try visit(source)
    guard let root = builtDescription else { return nil }
    return DescriptionCopy(root: root, retained: retained)
  }
  open override func visitContainer(_ description: Description) throws {
    try require(
      owners[ObjectIdentifier(description)] != nil,
      "Use buildFrom or setBuiltDescription to retain builder inputs")
    try setBuiltDescription(copyForBuild(description))
    builtDescription!.children.removeAll()
    let children = try description.orderedChildren()
    try require(children.count <= limits.items, "Builder item limit")
    for child in children { try visit(copyForBuild(child)) }
  }
  open override func visitDescription(_ description: Description) throws {
    try require(
      owners[ObjectIdentifier(description)] != nil,
      "Use buildFrom or setBuiltDescription to retain builder inputs")
    if let root = builtDescription {
      try require(root.isContainer, "Built scalar description cannot add another description")
      try require(root.children.count < limits.items, "Builder item limit")
      root.children.append(description)
    } else {
      try setBuiltDescription(description)
    }
  }
}
