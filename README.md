# Magritte Swift

An independent Swift Package port of [Magritte](https://github.com/magritte-metamodel/magritte). **0.5 adds recursive description metadata sessions and selective composition/copy semantics; it is not a complete Magritte implementation.** No C++ dependency, UI, networking or application-framework integration.

The headless Magritte library includes ordered/priority containers, a scalar subset, runtime adaptive objects, native accessors, to-one/to-many/scalar relations, static options, typed collections, cyclic references, validation, a self-description bootstrap and bounded graph/value interchange.

```sh
swift test
python3 tools/verify-fixtures.py
```

Add this repository as a Swift Package dependency and import the `Magritte` product (Swift >=6.0). Foundation and CoreFoundation are the only system framework dependencies. macOS arm64 was executed with Swift 6.3.3; Linux is intended but has not been executed here. Optional UI targets are future separate consumers.

```swift
import Magritte
// jsonData contains the shared person-v1.json fixture.
let graph = try Graph.decode(jsonData)
let person = graph.objects["ada"]!
let name = graph.descriptions["name"]!
try person.write(.string("Ada"), using: name)
let errors = try validate(person, using: person.description)
let wire = try graph.encode()
```

To adopt an added field and changed constraint at runtime:

```swift
let changed = try Graph.decode(changedJSONData) // shared person-v2.json
person.description = changed.descriptions[changed.root]!
let errors = try validate(person, using: person.description)
// Errors identify age (minimum now 21) and email (new required field).
```

Generic code writes values using the newly loaded descriptions; no Person class or per-schema translation is required. Existing application reference objects can instead use NativeModel and Description.nativeRead/nativeWrite closures. NativeModel retains its object. DictionaryModel uses dictionary keys; AdaptiveModel uses stable description IDs. Raw writes do not validate; call validation explicitly when accepting edits. Description implements Model, and descriptionModel() exposes common properties for the same generic reading/editing/validation APIs. Executed examples are in Tests/MagritteTests/ConformanceTests.swift.

Read the [support matrix and phased plan](docs/audit.md), [interchange contract](docs/interchange.md), [shared reference evidence](docs/conformance.md) and [attribution](NOTICE.md). Tests bundle the single authoritative fixture set from magritte-cpp, pinned by revision and SHA-256 in conformance-source.json. Runtime description adoption is explicit; it is not a migration engine. Mutable objects require caller synchronization. Unsupported semantics throw; Int64 does not claim full Magritte number support.

Relationship examples, GT evidence and remaining limits are documented in [relationships.md](docs/relationships.md). For reference-valued validation pass the owning Graph as the resolver context. The graph/2 fixture demonstrates aliases, cycles, options and nested adaptive values without domain-specific native types.

```swift
let graph = try Graph.decode(relationalJSON)
let ada = graph.objects["ada"]!
let target = try graph.resolve(ada.read(using: graph.descriptions["spouse"]!))
let errors = try validate(ada, using: ada.description, graph: graph)
let choices = try graph.descriptions["status"]!.allOptions()
```

The 0.3 phase adds labelled portable MACondition objects, dictionary/property/selector/variable/identity/null/chain accessors, memo/password/token descriptions, finite binary64, and MAStringReader/Writer behavior. See [portable-behavior.md](docs/portable-behavior.md) for executed GT evidence, APIs, numeric policies and remaining gaps. Graph/3 carries these forms; legacy graph/1 and graph/2 remain readable. Native names require host bindings; callback behavior remains local.

The 0.4 phase adds editing and metadata editors, including original/cache tracking, conflict reset and selective checked commits. Class-specific self-description covers all fourteen supported classes through ordinary selector accessors. See [editing.md](docs/editing.md) for APIs, GT/upstream evidence, collection snapshot boundaries and remaining metadata gaps. Editing state stays local; committed descriptions and objects use graph/3.

The 0.5 phase recursively describes metadata objects and edits their child/reference links through ordinary mementos. Description equality, concatenation, union/intersection, selective copies, filtering and transformation follow the audited Magritte protocol. See [composition.md](docs/composition.md) for ownership, APIs, GT evidence and profile limits. Generated metadata remains ordinary graph/3 data; local adapters are explicit session state.
