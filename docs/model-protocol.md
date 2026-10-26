# Model initialization and described comparison (0.25)

Both ports implement native equivalents of upstream Object's `initializeMagritte` and `isSameAs:using:` protocols, using an explicitly supplied description or description provider. They operate through the existing Model read/write and accessor-capability hooks. They introduce no object migration, validation rule, wire schema or application dependency.

## Audit and evidence

The baseline remains [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), with remote HEAD reconfirmed on 2026-10-27. The audit reviewed Object's initialization/comparison/read/write extensions, description defaults, container enumeration and accessor readability. `model-protocol-upstream-methods.json` fingerprints fourteen selected methods. The readUsing fingerprint also identifies an existing adapter gap described below; inclusion does not claim that entire method is implemented.

Supporting [Pharo Collection](https://github.com/pharo-project/pharo/blob/81f614957ca93536d2483a0f64480456b0350451/src/Collections-Abstract/Collection.class.st) and [SequenceableCollection](https://github.com/pharo-project/pharo/blob/81f614957ca93536d2483a0f64480456b0350451/src/Collections-Sequenceable/SequenceableCollection.class.st) source was reviewed to confirm membership/equality direction and short-circuit order. This is separately attributed kernel-source evidence, not a live-image check or a Magritte method fingerprint.

`model-protocol-scenarios.json` contains 48 initialization cases across readOnly/visible/cache flags and six declared defaults, plus 384 nil/default/scalar/collection comparison cases. Both ports consume that source-derived result set. Further native tests cover operation order, mutation between fields/reads, partial writes, unreadable fields, provider evaluation/errors, callable-default refusal, direct container defaults, host-reference equality, bounds and portable round trips.

**GT was not accessed, as requested.** These results are upstream-source and standalone native evidence. Fresh GT comparison/replay remains deferred; earlier fixture payloads remain unchanged.

## APIs

C++:

```cpp
using namespace magritte;
auto root = std::make_shared<Description>();
root->id = "person";
root->className = "MAContainer";
auto name = std::make_shared<Description>();
name->id = name->key = "name";
name->properties["default"] = Value("Ada");
root->children = {name};
AdaptiveModel first, second;
first.description = second.description = root;
initializeMagritte(first, *root); // first.values["name"] is "Ada".
auto same = isSameAs(first, second, *root); // true: nil and the declared default match.
```

Swift:

```swift
let root = Description(id: "person", className: "MAContainer")
let name = Description(id: "name", key: "name")
name.properties["default"] = .string("Ada")
root.children = [name]
let first = AdaptiveModel(description: root), second = AdaptiveModel(description: root)
try initializeMagritte(first, using: root)
let same = try isSameAs(first, second, using: root) // true
```

Both functions also accept a zero-argument description provider. C++ providers return a shared Description pointer; Swift providers return Description and may throw. The provider runs exactly once per call, before field processing, including for an empty container. Its returned description is retained for the operation. Missing/null C++ providers fail explicitly; provider errors propagate. Initialization returns the supplied Model (Swift is discardable); comparison returns Boolean. Comparison optionally accepts a Graph resolver and both APIs accept Limits.

These explicit descriptions/providers bridge upstream `magritteDescription` lookup and valuable evaluation to existing native descriptions/builders. They do not install implicit methods on every native class or add another discovery registry.

## Initialization

Initialization enumerates direct fields in existing native container order. For each field it reads readOnly and, when false, writes the declared default through the model. It performs no current-value read or write-capability probe. It writes even a nil default, overwrites existing values, ignores visibility and shouldCacheDefault, and does not use initialAnswer, shouldWrite, validation or memento default cooking.

A write callback can change a later field's default or readOnly flag; those are obtained when that field is reached. A failing write leaves prior writes and the writer's own completed side effects in place. No rollback or atomic preflight is invented. Direct container fields use MADescription's undefinedValue default and are written as fields; their children are not initialized recursively.

Declared Values retain the existing snapshot/reference rules. No default-object copy or factory evaluation is added. The native defaultFunction slot has no raw block-Value representation, so these protocols explicitly refuse it when the default is needed. Read-only initialization fields and unreadable comparison fields bypass it. Existing evaluated defaultValue/memento APIs are unchanged.

## Comparison

For each direct field, comparison follows this order:

1. Ask that field's current accessor whether it can read the right-hand model. If false, return false without either read.
2. Read the left model, then the right model, through their Model hooks.
3. Obtain the current declared default once, after both reads.
4. If both values belong to the pair nil/default, accept that field. Otherwise compare the left value with the right value.
5. Stop at the first false result; an empty container returns true.

Visibility, readOnly, shouldCacheDefault, initialAnswer and custom undefinedValue do not add exclusions or equivalences. A custom undefined sentinel only matches nil through the default rule if it is itself the declared default. The declared default is obtained even when the two raw values are already equal. Only right-hand readability is checked; comparing an object to itself does not bypass this check. Reads/default lookups/equality callbacks may propagate errors and effects; comparison performs no model writes of its own.

Nil/default membership compares the stored default as the left equality receiver. Primitive values use the established native Value equality profile, including exact numeric/text and inline collection rules. Direct reference receivers resolve through the Graph and send `=` through Model.binaryMessage, preserving the existing host-identity/equality override bridge. Results must be Boolean; no truthiness conversion is introduced. The final comparison sends equality to the left field value. These rules and right-hand readability can be directional; this API is not a replacement for general native operator equality, recursive object-graph equality or a hash contract. References nested in inline collections retain the existing Value snapshot/reference-ID comparison boundary.

## Model hooks and remaining gaps

These functions honor each supplied Model's read/write behavior, including custom adapters and mementos. They do not reinterpret an adapter's returned nil or sentinel. The audit found that pinned Object>>readUsing: replaces an accessor's nil with undefinedValue, while the current generic native adapters retain their established raw-nil policy. That generic-object fallback remains a separately recorded gap. Upstream MAAdaptiveModel overrides readUsing: to return actual values/absent nil; the native adaptive model retains that behavior.

Implicit per-object description discovery, the complete generic Object adapter fallback, maHash/maHashUsing, raw callable defaults, mutable collection-object identity and arbitrary Smalltalk scalar/collection equality remain unsupported. No platform-specific or application-framework behavior is imported from GT.

The functions use the existing bounded direct-child snapshot; structurally mutating the container during an operation remains outside the enumeration profile. Default/Value comparison work shares a budget across fields; existing accessor and local Value checks retain their own limits. Native callbacks/providers are not preempted. Callers synchronize model, metadata and captured state.

## Interchange and executed checks

No graph version, Value tag, semantic property, self-description annotation or runtime class registration is added. Descriptions/providers are supplied locally; executable providers are not serialized. Imported ordinary descriptions/objects can use these operations directly. Each port exports equivalent two-field/two-object graphs, reimports them, compares an initialized object with nil/default-equivalent values, reinitializes it and checks the unchanged graph.

On macOS arm64, all 24 CTest targets and 94 Swift tests pass. The focused C++ target passes 1,342 checks in ordinary and AddressSanitizer/UndefinedBehaviorSanitizer builds (leak detection disabled). An independently installed CMake 0.25 consumer runs, and an independent Swift consumer type-checks. All 124 shared fixture checksums verify; the previous 122 payloads remain unchanged.

```sh
# In magritte-cpp:
build/magritte-model-protocol-tests /tmp/model-protocol-cpp.json
# In magritte-swift:
MAGRITTE_MODEL_PROTOCOL_EXPORT=/tmp/model-protocol-swift.json swift test --filter ModelProtocolTests
# In magritte-cpp:
python3 tools/compare-graphs.py /tmp/model-protocol-cpp.json /tmp/model-protocol-swift.json
```

These are standalone checks with saved fixtures and no GT connection.
