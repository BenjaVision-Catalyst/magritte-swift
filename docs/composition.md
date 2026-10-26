# Recursive self-description, composition and copy (0.5)

This increment implements recursive description metadata sessions and Magritte's selective composition/copy protocol for the supported description hierarchy. It is not a claim of complete reflective Magritte or arbitrary object deep copy. The baseline remains upstream d67f318686b7779aed79416db121e257d1191f2e, also the upstream remote HEAD checked during this phase. Upstream source/tests were inspected; native code/tests and GT reference harnesses were independently written.

## Recursive metadata sessions

`RecursiveDescriptionModel` owns description targets, metadata schemas and local Model adapters. `bind(description)` returns an adapter for the actual description object; `describe(description)` builds one fresh metadata container and registers its fields. Every generated node is itself a Description and can be passed to describe again. This is lazy, bounded recursion: callers request levels explicitly rather than allocating an infinite metadata tree. Separate requests build fresh instances, consistent with the inspected MAPragmaBuilder dynamic-cache scope and live GT behavior. There is no invented permanent class-wide schema cache. Edits to a returned schema remain effective for interpreters using that schema; call describe again to build another schema from upstream defaults.

The session resolver retains targets and their referenced descriptions. Adapters hold a weak link back to the session, preventing ownership cycles; model access after the session expires throws. C++ session copies share this ownership; keep a session alive throughout memento use. Swift callers retain the session object. Do not remove bindings or mutate IDs through the exposed resolver. Duplicate IDs belonging to different description objects fail explicitly. Bounds cover traversal, retained nodes, generated identities, value operations and comparisons. Failed schema construction publishes no partial schema, although a valid target can remain bound.

The existing seven-property bootstrap and 0.4 descriptionModelFor factory remain available unchanged. Recursive sessions extend the latter with real selected upstream annotations:

| Target | Additional metadata |
| --- | --- |
| All supported descriptions | name (MASymbolDescription, priority 1) |
| Containers | children (MAToManyRelationDescription, ordered, Elements label, children/setChildren: selectors) |
| References, relations, options, Token | reference (MAToOneRelationDescription); required for nonrelations, optional and constrained to containers for relations |
| Options | optionsTextual (MAMemoDescription, Options label, priority 410) |

Existing scalar/class-specific metadata is retained. These are ordinary description graphs and selectors, interpreted by the same mementos and validator as application descriptions. Child and reference values are existing object-reference Values resolved to **actual Description adapters**, not adaptive copies pretending to be descriptions. Updating children or reference preserves target identity. Structural writes preflight values and reject owning child cycles, restoring the old child collection on failure. Setting nil reference is explicitly unsupported because automatic reference reconstruction/common-class inference is not implemented. Raw structural writes remain distinct from validation; validating children rejects container children through its supported MAElementDescription class list, although direct raw setters can accept supported nested containers.

optionsTextual uses the referenced description's text reader/writer, accepts CR/LF/CRLF lines, renders with CR separators, and publishes a new option list only after every line parses. An empty line can produce nil, as upstream does. It does not validate option membership or discard existing labels. The option storage API remains a value list; Smalltalk's particular collection-instance/species identity is not exposed.

`schemas()` returns the generated description graphs without local bindings, suitable for ordinary graph/3 export. Importing those schemas and binding native description targets makes the imported metadata executable without a new schema-specific mapping layer. The resolver itself contains native adapters and cannot be exported. Editing-session caches and bindings remain local; no new object wire tag or executable language was introduced.

C++ example:

```cpp
magritte::RecursiveDescriptionModel metadata;
auto schema = metadata.describe(numberDescription);
auto metaMin = metadata.resolver().descriptions.at(schema->id + ".min");
auto nextSchema = metadata.describe(metaMin);
auto model = metadata.bind(metaMin);
magritte::CheckedMemento editor(*model, nextSchema, &metadata.resolver());
editor.writeUsing(*metadata.resolver().descriptions.at(nextSchema->id + ".min"),
                  magritte::Value(std::int64_t(7)));
if (editor.validate().empty()) editor.commit();
// schema's min field now requires >=7; generic editing of numberDescription uses it.
auto portableMetadata = metadata.schemas().encode();
```

Swift independently uses the same concepts:

```swift
let metadata = RecursiveDescriptionModel()
let schema = try metadata.describe(numberDescription)
let metaMin = metadata.resolver.descriptions[schema.id + ".min"]!
let nextSchema = try metadata.describe(metaMin)
let editor = try CheckedMemento(model: metadata.bind(metaMin), description: nextSchema,
                                graph: metadata.resolver)
try editor.write(.integer(7), using: metadata.resolver.descriptions[nextSchema.id + ".min"]!)
if try editor.validate().isEmpty { try editor.commit() }
let portableMetadata = try metadata.schemas().encode()
```

## Composition and equality

`descriptionEqual` follows MAObject/MADescription/MAContainer equality: same concrete class and equal accessors, plus equal ordered child descriptions for containers. IDs, labels, properties, conditions, references, relation classes and options do not participate. Thus two String descriptions with different IDs/labels/defaults can be equal when their accessors match. Equality supports the existing dictionary/property/selector/variable/identity/null/chain accessor profile. Native callback accessor equality is unavailable and throws, rather than guessing function identity.

| Native operation | Upstream behavior preserved |
| --- | --- |
| asContainer | Existing container returned by identity; an element is wrapped without copying it |
| concatenate | Copy the left container (or wrap an element), then append the right fields; preserve duplicates and left properties/species |
| unionDescriptions | Copy left; append every right field absent from the original left by description equality; equal right-only fields can both remain |
| intersectDescriptions | Set intersection using description equality; deduplicate equal fields |
| selectDescriptions / collectDescriptions | Copy container properties/species, replace the child collection with filtered/transformed shared fields |
| copyEmpty / copyRange / copyWithout / copyWithoutAll | New container with selected shared fields, using equality for exclusions |

Native ranges are zero-based and half-open; Smalltalk copyFrom:to: is one-based inclusive. Native intersection uses the first equal left representative and stable left order. GT's Set enumeration and choice of equal representative are not promised; the fixture retains actual GT IDs and tests equality-class membership/multiplicity. Priority container ties remain the existing stable native policy; GT tie order is not claimed. Concatenation can produce duplicate child IDs locally, as upstream permits duplicate descriptions. The current graph codec rejects duplicate child IDs; resolve those explicitly before interchange. Composition does not silently rename shared fields or migrate adaptive values.

## Selective copy and ownership

`copyDescription(source, newID)` follows postCopy rather than deep cloning everything:

- A new description copies its property dictionary and accessor value.
- A container copies its child collection and shares its child descriptions.
- A reference description recursively copies its reference; a referenced container still shares its own children.
- Relation class collections and option collections are copied. Object-reference Values keep the same object IDs.
- Conditions, inline values, labels and native callbacks retain the existing native value/capture model. Upstream property values, nested label dictionaries and condition objects can share mutable identity; that aliasing is not supported by this profile. C++ function wrapper copies and Swift closures retain their host-language capture semantics, not a portable Smalltalk block identity claim.

Copies require explicit new root IDs, with deterministic `.reference` suffixes for copied reference nodes. Collisions and limits fail explicitly. New field IDs require application-directed adoption/migration of keyed adaptive values, as before. `DescriptionCopy` returns the root plus retained owners; **keep the whole result alive** or register all retained descriptions in an owning Graph. Retaining only its root can lose weak reference targets. The ownership result also retains shared descendants and their reference targets, so the original Graph can be released. It does not copy a source Graph's object table; retain/pass an appropriate resolver for object-reference Values. APIs are mutable and require caller synchronization; user callbacks must coordinate their own state and avoid reentrant mutation.

Direct recursive chains of reference postCopy are rejected with a bounded error. The audited upstream method recursively sends copy without a cycle memo; it does not establish a graph deep-clone contract. A separate cycle-preserving clone or arbitrary object copy facility is not claimed. Owning child cycles remain invalid. Native copied accessors/option lists/property entries can be modified independently, while edits to shared child descriptions affect source and copy as upstream tests require.

## Wire profile and explicit limits

Graph/3 gains the finite supported description class names and ancestor names as **relation class constraints**, plus the description name property (nil/String/Symbol). These denote actual native Magritte classes when bound in a metadata session; they do not turn portable MAAdaptiveModel instances into those classes. Unknown classes still fail import. Old ports can explicitly reject the expanded profile; there is no silent downgrade. Existing graph formats, scalar tags, object tables and predicate forms are unchanged.

Recursive fixtures project upstream class lists to the fourteen supported concrete classes, preserve the established as-is label policy, and represent empty SortedCollection defaults and child reads as ordered snapshots. Live default-label strings and default-collection classes are recorded separately. Symbolic names are used for selector/dictionary/property accessor fallback names in the native session; variable names remain Strings. The earlier wire accessor keys do not distinguish Smalltalk String/Symbol key identity; use explicit name values when that distinction matters. These are declared profile policies, not claims of full reflective equivalence.

The 0.6 profile adds class-valued metadata (classes, stringReader, stringWriter, validator), accessor/condition self-description and local accessor identity; see [reflection.md](reflection.md). Arbitrary class discovery, all platform scalar classes and full bootstrap of the entire upstream hierarchy remain unsupported. Omitted annotations are documented selections, not invented replacement fields. The selected description metadata itself is recursively usable at further levels; recursion does not imply those missing domains are implemented.

## Evidence

composition-reference.json records 256 live GT equality comparisons, twelve composition operations and selective-copy identity/independence checks. The pinned description/container/reference/relation/option/accessor postCopy/equality methods and their upstream tests were reviewed. recursive-live-methods.json records 37 source fingerprints matching pinned upstream and two image-kernel collection fingerprints, separately attributed. No upstream implementation or tests were copied.

recursive-reference.json records all fourteen expanded metadata graphs/getters, three recursive levels, metadata-driven range validation and structural child edits. Original GT labels/default collection classes are retained beside the documented profile projection. recursive-structural-reference.json checks actual reference replacement and four option-text inputs, including failed parse preservation and empty-line nil. recursive-roundtrip-reference.json records both native exports reconstructed in live GT: 47 description objects, no adaptive surrogate objects; GT validates a Number target, its metadata container and its metadata field, then reexports equivalent graphs. Native tests additionally reimport the schemas and perform another structural memento edit without schema mapping.

All GT evaluation/export used GT MCP, CCNativeMcpLease and post-release completion markers checked outside GT. These pure Magritte operations allocated no native Runtime resources and changed no persistent Smalltalk source or registered-checkout Git metadata. Source hashes rather than full inspected method bodies are committed. Replay requests are JSON tool requests, not compiled Smalltalk source files.

The 0.5 baseline ran CTest (four targets) and `swift test` (thirty tests); the current 0.6 counts are in reflection.md. Run CTest, `swift test`, and `tools/verify-fixtures.py` in each repository. Native round-trip inputs come from `magritte-recursive-tests /private/tmp/magritte-cpp-recursive-native.json` and `MAGRITTE_RECURSIVE_EXPORT=/private/tmp/magritte-swift-recursive-native.json swift test`. Replay through GT MCP only. Debug C++, ASan/UBSan and the installed CMake consumer are checked on macOS arm64; LeakSanitizer remains unavailable. No new cross-platform execution claim is made.

The 0.7 bootstrap expands a finite reachable description graph in one staged batch and exposes mementos through their exact represented schemas. schemas() now includes current published-schema closure and is throwing in Swift. See bootstrap.md.
