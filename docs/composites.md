# Composite accessors and conflicts (0.15)

Both ports implement `MACompositeAccessor` and local `MACompositeConflict` objects within the existing native Value/model profile. They support editing a field across several related models, while preserving the upstream distinction between a common value and conflicting values.

## Upstream and live evidence

The audited upstream remains [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), confirmed against remote HEAD on 2026-10-27. `composite-live-methods.json` records 35 matching live/upstream method fingerprints: the composite/conflict protocols, inherited chain/delegator copying/equality/names/annotations, and description kind getters/setters/defaults. This is a method-level comparison, not an assertion that the entire GT image matches that Git revision.

`composite-reference.json` records fresh GT execution of:

- 25 composite scenarios, each with canRead/canWrite/read/write results and callback traces, plus resulting values. These include common/different/nil/empty/single values; Array/OrderedCollection/Set/Bag sources; absent blocks; nil/scalar/failing heads; late read failures; partial writes; conflict writes; and nil writes.
- Six conflict kinds: nil, String, Number, Integer, Boolean and MACompositeConflict. The cases check exact kind membership, species equality/hash, copy identity/equality, ordinary inherited predicates, message fallback, validation, scalar writers, empty/custom/default strings and the empty annotated schema.
- Three `via:using:` label/copy/annotation cases; fifteen represented default description kinds; four declared kind overrides; and four cached-memento editing snapshots.

The native tests consume these shared results. They compare error occurrence and traces, rather than native exception classes or nested Smalltalk exception trees. GT Set/Bag enumeration order is recorded explicitly and used as the input snapshot order; no cross-platform ordering guarantee is invented for unordered collections. No installed Magritte methods were compiled or changed.

Each port exports four portable accessor configurations. GT reconstructs them as real dictionary/chain/composite/delegator accessors, checks capabilities, reads a conflict, writes a common value and reads it back, and reexports the exact configurations. Both ports then execute all eight GT round-trip result cases. See `composite-roundtrip-reference.json` and its replay.

All GT reference execution uses `CCNativeMcpLease`; controllers check the completion marker outside GT before reading reports or making another GT call. These runs allocate only temporary Smalltalk model objects, not native plugins or Runtime resources; there is therefore no independent native Runtime owner to clean up. Standalone native tests run in separate processes. The registered image checkout locations were inspected through MCP and left untouched.

## Composite semantics

A composite accessor has exactly two slots: a head accessor that reads the collection, and a next accessor applied to every element. Its optional kind is a registered class identity or nil. Composite boundaries remain binary even when next is itself a chain/composite; accessor-object materialization must not flatten them into ordinary chain traversal.

- `canRead` requires a readable head and readable next for every element. `canWrite` requires a readable head and writable next for every element; it does not require a head setter or next reader. Empty collections satisfy the universal next-capability check. Both queries read the head only after its capability succeeds.
- Read evaluates next on every element before comparing results. One distinct value returns the first common result. More than one distinct value creates a fresh conflict with the configured kind. An empty read raises an error. A late read failure propagates even if earlier values already differ.
- Write reads/enumerates the head collection and writes the given value through next for each element. A conflict value suppresses next writes, but still evaluates the head and propagates head/collection errors. Writes are not transactional: a failure on a later element leaves earlier successful writes in place. Raw accessor operations do not implicitly validate models.
- Inherited equality compares species/head/next and ignores kind. Copies copy accessor configuration/objects while retaining callable identity in pluggable block slots. Names and labels use the inherited chain ordering. The annotated schema contains inherited `next` and `accessor` fields; kind is not an invented annotation.

`compositeVia` follows `via:using:`: it wraps the description's current accessor, takes the description's declared kind, prefixes its existing nonempty label using the head's default label, and installs the composite accessor on that description. A nil/empty label is preserved. The description `kind` property now exposes its upstream default or explicit Class/nil value; validation honors declared scalar kinds and checks relation/option kind overrides before their existing finite validation protocol. Invalid kind metadata fails explicitly. This support is required by composite construction, not a separate type system.

## Conflict semantics and native bridge

C++ holds a conflict as `Value(std::shared_ptr<CompositeConflict>)`; Swift uses `Value.conflict(CompositeConflict)`. The object has independently mutable optional kind and string slots. A nil string reads as `(Multiple values)`; an empty string stays empty. Value copies retain object identity. Explicit `copy()` creates an independent object with the same slots. Two represented conflict objects compare equal and hash alike regardless of either slot, as upstream compares species. Mutation does not change their equality/hash.

`kindOf` accepts the actual conflict/Object ancestry plus the exact configured kind. It does not pretend that a configured Integer is also a Number, or that a configured String has Collection ancestry. Ordinary inherited predicates still treat the object as a conflict: it is non-nil, is not an actual integer, and is not an actual collection. Scalar validation and writers retain this distinction. For example, a Number conflict passes bare Number validation but a numeric bound can raise a message/protocol error; a Boolean conflict cannot be used as a Boolean branch condition. The GT failures are retained rather than silently coerced.

C++/Swift have no Smalltalk message lookup. `doesNotUnderstand(selector, canUnderstand)` therefore accepts an explicit host class-protocol callback, like the ports' explicit native selector bindings. It queries the configured kind and selector, returns the conflict string when that class understands the message, and raises otherwise (including a nil kind). The method does not evaluate the message on an imagined payload or return a fabricated numeric/Boolean result. The callback can consult application-registered classes; no closed method/class registry is introduced. Arbitrary Smalltalk reflection or automatic forwarding of every native language operation is not claimed.

The class environment seeds these two real Magritte class identities in the existing runtime-open registry. Existing historical class-environment fixture projections remain historical; production discovery is not filtered to them.

## Editing, interchange and bounds

Mementos, pluggable accessors, lazy defaults and dynamic-option callbacks accept local conflict values and retain their identity. Local value checks bound their actual string/class state and surrounding collections independently of public interchange encoding. Set duplicate checks use conflict species equality even when kind/string differ. Internal bound-check projections are not exported values.

Portable accessor configurations use graph/4 (or the standalone accessor codec):

```json
{
  "class": "MACompositeAccessor",
  "kind": { "type": "class", "value": "String" },
  "steps": [
    { "class": "MADictionaryAccessor", "key": "people" },
    { "class": "MADictionaryAccessor", "key": "name" }
  ]
}
```

Kind may instead be `{ "type": "nil" }`. Older graph formats reject composites, including nested untyped composites. Invalid slot counts, unknown kinds, unexpected keys, excessive work/depth/items and accessor-object cycles fail explicitly. Composite traversal resolves existing Graph model references; it does not introduce a second object model.

Conflict instances are local objects: public Value/graph export rejects them, including inside nested collections, properties or values. No conflict wire tag, string sentinel, remote message executor or lossy substitution was invented. Portable composite accessors can still be exported when their stored graph values are portable; reading them locally may produce a conflict. Pluggable accessor configurations remain local even when nested inside composites.

The preexisting Value profile still governs common-value equality: scalar equality, collection snapshots and reference identities. Mutable collection identity, arbitrary host-object equality overrides, and subclasses with different Smalltalk species are not added by this phase. Native conflict objects represent the concrete upstream class. Full recursive conflict-object reflection remains outside the selected self-description profile; its empty upstream annotation set is recorded without adding kind/string annotation fields.

## APIs

C++:

```cpp
auto group = Accessor::composite(head, next, "String");
auto result = group.read(model, &graph);
if (auto conflict = result.conflict()) {
    auto label = conflict->string();
}
group.write(model, Value("common value"), &graph);
auto installed = Accessor::compositeVia(head, description);
```

Swift:

```swift
let group = Accessor.composite(head: head, next: next, kind: "String")
let result = try group.read(model, graph: graph)
if let conflict = result.conflict { print(conflict.string) }
try group.write(.string("common value"), to: model, graph: graph)
let installed = try Accessor.compositeVia(head, using: description)
```

Swift adds a public Value enum case; external exhaustive switches must handle `.conflict`. C++ appends a variant alternative and keeps the existing Accessor aggregate member ordering intact. Both libraries remain independent of Catalyst consumers, UI or networking runtimes.
