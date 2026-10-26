import Foundation
import Magritte
import XCTest

final class PragmaTests: XCTestCase {
  final class Probe: Model {
    var values: [String: Value] = [:]
    func readSlot(strategy: String, name: String) throws -> Value { values[name] ?? .undefined }
    func writeSlot(strategy: String, name: String, value: Value) throws { values[name] = value }
    func read(using d: Description) throws -> Value { try d.effectiveAccessor.read(self) }
    func write(_ value: Value, using d: Description) throws {
      try d.effectiveAccessor.write(value, to: self)
    }
    weak var peer: Probe?
    let mode: String
    var containers = 0, events: [String] = []
    init(_ mode: String = "simple") {
      self.mode = mode
      values = ["name": .string("Ada"), "score": .integer(7)]
    }
  }
  func label(_ d: Description) throws -> String {
    guard case .string(let s) = try d.property("label") else {
      throw MagritteError("Missing label")
    }
    return s
  }
  func field(_ r: DescriptionRequest, _ key: String, _ label: String, _ priority: Int64) throws
    -> Description
  {
    let d = Description(id: try r.builder.freshID(), key: key)
    d.properties = ["label": .string(label), "priority": .integer(priority)]
    return d
  }
  override func setUpWithError() throws {
    try ClassRegistry.shared.registerClasses([
      ClassInfo(name: "MAPragmaProbeBase", label: "Probe Base"),
      ClassInfo(
        name: "MAPragmaProbeTagged", superclass: "MAPragmaProbeBase", label: "Probe Tagged"),
      ClassInfo(name: "MAPragmaProbePlain", superclass: "MAPragmaProbeBase", label: "Probe Plain"),
      ClassInfo(
        name: "MAPragmaProbeDuplicate", superclass: "MAPragmaProbeBase", label: "Probe Duplicate"),
      ClassInfo(
        name: "MAPragmaProbeContainer", superclass: "MAPragmaProbeBase", label: "Probe Container"),
      ClassInfo(name: "MAPragmaProbeEmpty", label: "Empty"),
    ])
    let registry = DescriptionMethodRegistry.shared
    func install(
      _ cls: String, _ selector: String, _ arity: Int, _ tags: [DescriptionPragma],
      _ op: @escaping (DescriptionRequest, Description?) throws -> DescriptionCopy?
    ) throws {
      try registry.install(
        DescriptionMethod(
          className: cls, selector: selector, arguments: arity, pragmas: tags, operation: op))
    }
    try install("MAPragmaProbeBase", "descriptionContainer", 0, []) { [self] r, _ in
      let p = try XCTUnwrap(r.target.model as? Probe)
      p.containers += 1
      p.events.append("container")
      XCTAssertTrue(DescribedObject.current?.identity === r.target.identity)
      if p.mode == "container-error" { throw MagritteError("provider") }
      if p.mode == "container-recursive" {
        return try r.builder.forTarget(r.target, idPrefix: "ignored")
      }
      if p.mode == "nil-container" { return nil }
      let d = try field(r, "", XCTUnwrap(ClassRegistry.shared.find(r.target.className)).label, 0)
      d.className = p.mode == "scalar-container" ? "MAStringDescription" : "MAPriorityContainer"
      return DescriptionCopy(root: d)
    }
    try install(
      "MAPragmaProbeBase", "decorateContainer:", 1, [DescriptionPragma("magritteContainer")]
    ) { [self] r, d in
      let p = try XCTUnwrap(r.target.model as? Probe)
      p.events.append("decorate")
      XCTAssertTrue(DescribedObject.current?.identity === r.target.identity)
      if let d {
        d.properties["label"] = .string(try label(d) + "C")
        if p.mode == "seed" { d.children.append(try field(r, "seed", "Seed", 5)) }
      }
      return nil
    }
    func name(_ label: String) -> (DescriptionRequest, Description?) throws -> DescriptionCopy? {
      { [self] r, _ in
        let p = try XCTUnwrap(r.target.model as? Probe)
        p.events.append("name")
        if p.mode == "nil-name" { return nil }
        return DescriptionCopy(root: try field(r, "name", label, 20))
      }
    }
    try install(
      "MAPragmaProbeBase", "descriptionName", 0, [DescriptionPragma("magritteDescription")],
      name("Name"))
    try install(
      "MAPragmaProbeBase", "descriptionNumber", 0, [DescriptionPragma("magritteDescription")]
    ) { [self] r, _ in
      let p = try XCTUnwrap(r.target.model as? Probe)
      p.events.append("number")
      if p.mode == "getter-error" { throw MagritteError("getter") }
      let d = try field(r, "score", "Score", 10)
      d.className = "MANumberDescription"
      return DescriptionCopy(root: d)
    }
    try install(
      "MAPragmaProbeBase", "descriptionSelf", 0, [DescriptionPragma("magritteDescription")]
    ) { [self] r, _ in
      let p = try XCTUnwrap(r.target.model as? Probe)
      if p.mode != "recursive" { return nil }
      let cached = try XCTUnwrap(r.builder.forTarget(r.target, idPrefix: "ignored"))
      XCTAssertTrue(cached.root.children.isEmpty)
      let d = try field(r, "self", "Self", 30)
      d.className = "MAToOneRelationDescription"
      d.reference = cached.root
      d.classes = [r.target.className]
      return DescriptionCopy(root: d, retained: [cached.root])
    }
    let tags = [DescriptionPragma("magritteDescription:", arguments: [.symbol("descriptionName")])]
    try install("MAPragmaProbeBase", "aName:", 1, tags) { [self] r, arg in
      let p = try XCTUnwrap(r.target.model as? Probe)
      let d = try XCTUnwrap(arg)
      XCTAssertNotNil(d.definingContext)
      p.events.append("a:" + (try label(d)))
      if p.mode == "replacement" {
        return DescriptionCopy(root: try field(r, "name", "Replacement", 20))
      }
      if p.mode == "nil-first" { return nil }
      d.properties["label"] = .string(try label(d) + "A")
      return DescriptionCopy(root: d)
    }
    try install("MAPragmaProbeBase", "zName:", 1, tags) { [self] r, arg in
      let p = try XCTUnwrap(r.target.model as? Probe)
      let d = try XCTUnwrap(arg)
      p.events.append("z:" + (try label(d)))
      if p.mode == "extension-error" { throw MagritteError("extension") }
      if p.mode == "nil-last" { return nil }
      d.properties["label"] = .string(try label(d) + "Z")
      return DescriptionCopy(root: d)
    }
    try install(
      "MAPragmaProbeTagged", "descriptionName", 0, [DescriptionPragma("magritteDescription")],
      name("Tagged"))
    try install("MAPragmaProbePlain", "descriptionName", 0, [], name("Plain"))
    try install("MAPragmaProbeDuplicate", "aName:", 1, tags) { [self] _, arg in
      let d = try XCTUnwrap(arg)
      d.properties["label"] = .string(try label(d) + "S")
      return DescriptionCopy(root: d)
    }
    try install(
      "MAPragmaProbeContainer", "ownContainer", 0, [DescriptionPragma("magritteContainer")]
    ) { [self] r, _ in
      let d = try field(r, "", "Own", 0)
      d.className = "MAContainer"
      return DescriptionCopy(root: d)
    }
  }
  func data(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
  }
  func graph(_ copy: DescriptionCopy) -> Graph {
    let g = Graph(root: copy.root.id)
    g.format = "magritte.graph/4"
    g.descriptions = Dictionary(uniqueKeysWithValues: copy.retained.map { ($0.id, $0) })
    return g
  }
  func testSharedSourceScenarios() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "pragma-scenarios", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let rows = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
    let builder = PragmaBuilder()
    for row in rows {
      let mode = try XCTUnwrap(row["mode"] as? String)
      let cls = try XCTUnwrap(row["modelClass"] as? String)
      let p = Probe(mode)
      let target = DescriptionTarget(p, className: cls)
      let cache = try DynamicDescriptionCache(idPrefix: "scenario")
      var success = true
      var result: DescriptionCopy?
      try withDescriptionCache(cache) {
        do { result = try builder.forTarget(target, idPrefix: "ignored") } catch { success = false }
        XCTAssertEqual(success, row["success"] as? Bool, mode)
        let events = p.events
        let count = p.containers
        if cache.count > 0 {
          result = try builder.forTarget(target, idPrefix: "ignored")
          XCTAssertEqual(events, p.events)
          XCTAssertEqual(count, p.containers)
          XCTAssertTrue(try builder.forTarget(target, idPrefix: "ignored")?.root === result?.root)
        }
        XCTAssertEqual(cache.count, mode == "container-error" ? 0 : 1)
      }
      XCTAssertNil(DescribedObject.current)
      var fields: [[String: Any]] = []
      if let root = result?.root {
        XCTAssertEqual(try label(root), row["label"] as? String)
        for d in try root.orderedChildren() {
          var item: [String: Any] = [
            "key": d.key, "label": try label(d), "selector": NSNull(), "methodClass": NSNull(),
          ]
          if let c = d.definingContext {
            XCTAssertEqual(c.modelClass, cls)
            item["selector"] = c.methodSelector
            item["methodClass"] = try c.methodClass()
          }
          fields.append(item)
        }
        if mode == "recursive" {
          XCTAssertTrue(try root.children.last?.referenceDescription() === root)
        }
      } else {
        XCTAssertTrue(row["label"] is NSNull)
      }
      XCTAssertEqual(try data(fields), try data(XCTUnwrap(row["fields"])), mode)
      if mode == "replacement" || mode == "nil-first" { XCTAssertTrue(p.events.contains("z:Name")) }
      if mode == "simple", let result {
        let g = graph(result)
        let person = AdaptiveModel(id: "sample", description: result.root)
        for d in result.root.children { person.values[d.id] = try p.read(using: d) }
        XCTAssertTrue(try validate(person, using: result.root).isEmpty)
        XCTAssertEqual(try writeString(person, using: result.root), "7-Ada")
        g.objects[person.id] = person
        _ = try Graph.decode(g.encode())
      }
      if mode == "simple", let path = ProcessInfo.processInfo.environment["MAGRITTE_PRAGMA_EXPORT"],
        let result
      {
        let g = graph(result)
        let person = AdaptiveModel(id: "sample", description: result.root)
        for d in result.root.children { person.values[d.id] = try p.read(using: d) }
        g.objects[person.id] = person
        try g.encode().write(to: URL(fileURLWithPath: path))
      }
    }
  }
  func testDynamicScopesAndIdentity() throws {
    let builder = PragmaBuilder()
    let p = Probe()
    let t = DescriptionTarget(p, className: "MAPragmaProbeBase")
    let a = try XCTUnwrap(builder.forTarget(t, idPrefix: "a"))
    let b = try XCTUnwrap(builder.forTarget(t, idPrefix: "b"))
    XCTAssertFalse(a.root === b.root)
    XCTAssertEqual(p.containers, 2)
    XCTAssertFalse(try DynamicDescriptionCache.current === DynamicDescriptionCache.current)
    let outer = try DynamicDescriptionCache(idPrefix: "outer")
    let inner = try DynamicDescriptionCache(idPrefix: "inner")
    try withDescriptionCache(outer) {
      try withDescribedObject(t) {
        XCTAssertThrowsError(try withDescriptionCache(inner) { throw MagritteError("restore") })
        XCTAssertTrue(try DynamicDescriptionCache.current === outer)
        XCTAssertTrue(DescribedObject.current?.identity === p)
        let q = Probe()
        _ = try builder.forTarget(DescriptionTarget(q, className: t.className), idPrefix: "ignored")
        XCTAssertEqual(outer.count, 1)
      }
    }
    XCTAssertNil(DescribedObject.current)
  }
  func testContextCopyWireAndRecompilation() throws {
    let builder = PragmaBuilder()
    let p = Probe()
    let t = DescriptionTarget(p, className: "MAPragmaProbeBase")
    let result = try XCTUnwrap(builder.forTarget(t, idPrefix: "wire"))
    let c = DescriptionContext(modelClass: t.className, methodSelector: "descriptionName")
    let same = DescriptionContext(modelClass: t.className, methodSelector: "descriptionName")
    XCTAssertEqual(c, same)
    XCTAssertEqual(Set([c, same]).count, 1)
    XCTAssertEqual(try c.methodClass(), t.className)
    XCTAssertThrowsError(try DescriptionContext().compiledMethod())
    XCTAssertNil(
      try DescriptionContext(modelClass: "Object", methodSelector: "missing").compiledMethod())
    result.root.definingContext = c
    let copy = try copyDescription(result.root, newID: "copy")
    XCTAssertTrue(copy.root.definingContext === c)
    let g = graph(result)
    let encoded = try g.encode()
    let round = try Graph.decode(encoded)
    XCTAssertEqual(round.descriptions[g.root]?.definingContext, c)
    var bad = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    bad["format"] = "magritte.graph/3"
    XCTAssertThrowsError(try Graph.decode(data(bad)))
    g.format = "magritte.graph/3"
    XCTAssertThrowsError(try g.encode())
    g.format = "magritte.graph/4"
    bad = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var nodes = try XCTUnwrap(bad["descriptions"] as? [[String: Any]])
    var ctx = try XCTUnwrap(nodes[0]["definingContext"] as? [String: Any])
    ctx["extra"] = true
    nodes[0]["definingContext"] = ctx
    bad["descriptions"] = nodes
    XCTAssertThrowsError(try Graph.decode(data(bad)))
    for value in [
      ["type": "string", "value": "Object"], ["type": "class", "value": "UnknownPragmaClass"],
    ] {
      bad = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
      nodes = try XCTUnwrap(bad["descriptions"] as? [[String: Any]])
      ctx = try XCTUnwrap(nodes[0]["definingContext"] as? [String: Any])
      ctx["modelClass"] = value
      nodes[0]["definingContext"] = ctx
      bad["descriptions"] = nodes
      XCTAssertThrowsError(try Graph.decode(data(bad)))
    }
    bad = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    nodes = try XCTUnwrap(bad["descriptions"] as? [[String: Any]])
    ctx = try XCTUnwrap(nodes[0]["definingContext"] as? [String: Any])
    ctx["methodSelector"] = ["type": "string", "value": "descriptionName"]
    nodes[0]["definingContext"] = ctx
    bad["descriptions"] = nodes
    XCTAssertThrowsError(try Graph.decode(data(bad)))
    result.root.definingContext = DescriptionContext()
    XCTAssertNil(
      try Graph.decode(graph(result).encode()).descriptions[g.root]?.definingContext?.modelClass)
    result.root.definingContext = c
    let registry = DescriptionMethodRegistry.shared
    let original = try XCTUnwrap(
      registry.lookup(className: t.className, selector: "descriptionName"))
    var changed = original
    changed.operation = { [self] r, _ in DescriptionCopy(root: try field(r, "name", "Changed", 20))
    }
    defer { try! registry.install(original) }
    let cache = try DynamicDescriptionCache(idPrefix: "cached")
    try withDescriptionCache(cache) {
      let old = try XCTUnwrap(builder.forTarget(t, idPrefix: "ignored"))
      try registry.install(changed)
      XCTAssertTrue(try builder.forTarget(t, idPrefix: "ignored")?.root === old.root)
    }
    let fresh = try XCTUnwrap(builder.forTarget(t, idPrefix: "fresh"))
    XCTAssertEqual(try label(fresh.root.orderedChildren()[1]), "ChangedAZ")
    let tagged = try XCTUnwrap(
      registry.lookup(className: "MAPragmaProbeTagged", selector: "descriptionName"))
    registry.remove(className: tagged.className, selector: tagged.selector)
    defer { try! registry.install(tagged) }
    XCTAssertEqual(
      try registry.lookup(className: tagged.className, selector: tagged.selector)?.className,
      t.className)
  }
  func testBoundsAndGrowingGraphOwnership() throws {
    var limits = Limits()
    limits.depth = 3
    let recurse = Probe("container-recursive")
    let target = DescriptionTarget(recurse, className: "MAPragmaProbeBase")
    XCTAssertThrowsError(try PragmaBuilder(limits: limits).forTarget(target, idPrefix: "bounded"))
    limits = Limits()
    limits.visits = 2
    XCTAssertThrowsError(
      try PragmaBuilder(limits: limits).forTarget(
        DescriptionTarget(Probe(), className: target.className), idPrefix: "work"))
    let builder = PragmaBuilder()
    var early: DescriptionCopy?
    weak var laterRoot: Description?
    do {
      let cache = try DynamicDescriptionCache(idPrefix: "late")
      try withDescriptionCache(cache) {
        early = try builder.forTarget(
          DescriptionTarget(Probe(), className: target.className), idPrefix: "ignored")
        let later = try XCTUnwrap(
          builder.forTarget(
            DescriptionTarget(Probe(), className: target.className), idPrefix: "ignored"))
        laterRoot = later.root
        let relation = Description(id: "lateRelation", className: "MAToOneRelationDescription")
        relation.reference = later.root
        early?.root.children.append(relation)
      }
    }
    XCTAssertNotNil(laterRoot)
    XCTAssertTrue(try early?.root.children.last?.referenceDescription() === laterRoot)
    early = nil
    XCTAssertNil(laterRoot)
    let registry = DescriptionMethodRegistry.shared
    let original = try XCTUnwrap(
      registry.lookup(className: target.className, selector: "descriptionName"))
    var wrong = original
    wrong.arguments = 1
    try registry.install(wrong)
    XCTAssertThrowsError(
      try builder.forTarget(
        DescriptionTarget(Probe(), className: target.className), idPrefix: "arity"))
    try registry.install(original)
    var invalid = original
    invalid.pragmas = [DescriptionPragma("magritteDescription:")]
    XCTAssertThrowsError(try registry.install(invalid))
    for name in ["nodes", "items"] {
      var small = Limits()
      if name == "nodes" { small.nodes = 1 } else { small.items = 1 }
      XCTAssertThrowsError(
        try PragmaBuilder(limits: small).forTarget(
          DescriptionTarget(Probe(), className: target.className), idPrefix: "limited"))
    }

  }
  func testMutualRecursionAndHostIdentity() throws {
    let registry = DescriptionMethodRegistry.shared
    let cls = "MAPragmaProbeBase"
    let builder = PragmaBuilder()
    try registry.install(
      DescriptionMethod(
        className: cls, selector: "descriptionPeer",
        pragmas: [DescriptionPragma("magritteDescription")]
      ) { [self] r, _ in
        let p = try XCTUnwrap(r.target.model as? Probe)
        guard let other = p.peer else { return nil }
        let result = try XCTUnwrap(
          r.builder.forTarget(DescriptionTarget(other, className: cls), idPrefix: "ignored"))
        let d = try field(r, "peer", "Peer", 30)
        d.className = "MAToOneRelationDescription"
        d.reference = result.root
        return DescriptionCopy(root: d, retained: [result.root])
      })
    defer { registry.remove(className: cls, selector: "descriptionPeer") }
    let cache = try DynamicDescriptionCache(idPrefix: "mutual")
    let a = Probe()
    let b = Probe()
    a.peer = b
    b.peer = a
    try withDescriptionCache(cache) {
      let result = try XCTUnwrap(
        builder.forTarget(DescriptionTarget(a, className: cls), idPrefix: "ignored"))
      let peer = try XCTUnwrap(result.root.orderedChildren().last?.referenceDescription())
      XCTAssertTrue(try peer.orderedChildren().last?.referenceDescription() === result.root)
      XCTAssertEqual(cache.count, 2)
      XCTAssertEqual(a.containers, 1)
      XCTAssertEqual(b.containers, 1)
    }
    let shared = NSObject()
    let aliasCache = try DynamicDescriptionCache(idPrefix: "identity")
    let c = Probe()
    let d = Probe()
    try withDescriptionCache(aliasCache) {
      let first = try builder.forTarget(
        DescriptionTarget(c, className: cls, identity: shared), idPrefix: "ignored")
      let second = try builder.forTarget(
        DescriptionTarget(d, className: cls, identity: shared), idPrefix: "ignored")
      XCTAssertTrue(first?.root === second?.root)
      XCTAssertEqual(c.containers, 1)
      XCTAssertEqual(d.containers, 0)
    }
  }

}
