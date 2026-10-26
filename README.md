# Magritte Swift

An independent Swift Package port of [Magritte](https://github.com/magritte-metamodel/magritte). **0.21 adds stored property lookup and lazy conditional operations; it is not a complete Magritte implementation.** No C++ dependency, UI, networking or application-framework integration.

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

The 0.6 phase adds MAClassDescription, a finite class registry, class-valued interpreter/relation metadata and live accessor-object editing. Conditions retain their actual upstream empty annotated schemas. See [reflection.md](docs/reflection.md) for APIs, GT evidence, graph/4 and explicit accessor snapshot boundaries.

The 0.7 phase binds actual mementos through their represented descriptions and bootstraps metadata for a reachable description graph in one bounded batch. See [bootstrap.md](docs/bootstrap.md) for identity, nested editing, the 65-class registry, current schema closure and GT evidence.

The 0.8 class environment supports application class registration, RTTI/metatype lookup, inheritance and subclass discovery. Metadata, validation and codecs use that environment. See [registration.md](docs/registration.md) for native examples, identity/ownership rules and GT evidence.

The 0.9 phase adds `acceptMagritte`, native visitor overrides with inherited fallback, and the stateful `MADescriptionBuilder` copy/enrichment protocol. See [visitors.md](docs/visitors.md) for APIs, the upstream/GT audit, ownership and remaining semantics.

The 0.10 phase implements `MADynamicOptions` completion, membership, reader and shallow-copy semantics. `Options` preserves collection/provider results; known static callers use `.values()` explicitly. See [dynamic-options.md](docs/dynamic-options.md) for APIs, the source migration, GT evidence and export boundaries.

The 0.11 phase adds `Accessor.canRead`/`canWrite`, explicit host selector/variable discovery, and independent absent read/write selectors. See [accessor-capabilities.md](docs/accessor-capabilities.md) for the exact upstream rules, GT traces, APIs and remaining reflection boundaries.

The 0.12 phase adds local `MAPluggableAccessor` block slots, block-identity equality, shallow copying and chain/memento integration. See [pluggable-accessors.md](docs/pluggable-accessors.md) for APIs, GT evidence, ownership and explicit closure interchange boundaries.

The 0.13 phase implements accessor-derived names/default labels, explicit nil/empty overrides, faithful lazy null defaults and metadata integration. Swift property reads now require `try`. See [accessor-inference.md](docs/accessor-inference.md) for APIs, GT evidence, bounds and the remaining Unicode inflection boundary.

Container query and enumeration APIs, GT traces and remaining boundaries are documented in [container-enumeration.md](docs/container-enumeration.md).

Composite accessors, conflict object semantics and GT verification are documented in [composites.md](docs/composites.md).

Builder composition, flattener extension hooks, exact priorities and GT evidence are documented in [builders.md](docs/builders.md).

Runtime method registration, recursive discovery, defining contexts and the deferred fresh-GT verification are documented in [pragma-discovery.md](docs/pragma-discovery.md).

Description display conversion, option label/sort behavior, source evidence and native API boundaries are documented in [display.md](docs/display.md). GT was not accessed for this phase.

The MASortBlock protocol, Value-target accessors and source/native verification are documented in [sorting.md](docs/sorting.md). GT was not accessed for this phase.

Reference getter side effects, option undefined cascades and snapshot boundaries are documented in [reference-access.md](docs/reference-access.md). GT was not accessed for this phase.

Stored property semantics, nil/presence rules and source/native evidence are documented in [properties.md](docs/properties.md). GT was not accessed for this phase.
