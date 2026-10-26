# Default/self references and relation helpers (0.28)

Both ports implement MAG-002 for the supported description profile: lazy owned String references, Boolean self-reference, the reference setter/nil reset, relation `allClasses`/`commonClass`, and their recursive metadata bindings. Stored nil remains distinct from reading a reference. The target remains the headless Magritte model.

## Upstream evidence and the relation fallback

The source is [Magritte d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), reconfirmed as remote HEAD on 2026-10-27 using an independent read-only checkout. `default-reference-upstream-methods.json` fingerprints 23 inspected methods. The shared scenario fixture covers fourteen canonical/inherited getter cases and eight relation class-list cases. Expectations are source-derived; **GT was not accessed** and fresh live-image replay remains deferred.

[MAReferenceDescription](https://github.com/magritte-metamodel/magritte/blob/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model/MAReferenceDescription.class.st) creates a fresh MAStringDescription when its stored reference is nil, stores it, applies the owner's display setting, and returns it. MABooleanDescription's separate getter returns self. The ports follow these rules, including registered descendants from MAG-001.

[MARelationDescription](https://github.com/magritte-metamodel/magritte/blob/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model/MARelationDescription.class.st) tests the superclass getter's result for nil before its common-class template fallback. That superclass getter has already created and returned a String description. A repository-wide source search found no other defaultReference definition or relation reference override in the pinned source packages. Therefore the normal core getter returns the String default, even with nonempty class constraints. This phase preserves that behavior; it does not invent an intersection/template builder from the method comment.

The relation's annotated reference field still offers container classes. A lazy String default does not become a container to satisfy that annotation. This source-level tension is retained rather than concealed by a changed getter. Arbitrary Smalltalk class-side method overrides or platform-specific template behavior are not inferred from the normal core branch.

## Getters, setters and lifetime

`referenceDescription()` lazily creates one default per reference description and returns that same object on repeated reads. Distinct owners and nil resets create distinct defaults. A generated default has an independent native graph ID; its ID is not semantic metadata and does not depend on the owner's mutable ID. The getter then performs the existing display propagation, including block identity, explicit nil and the default-display projection documented in [reference-access.md](reference-access.md).

`setReference(target)` assigns the graph edge; `setReference(nullptr)` in C++ or `setReference(nil)` in Swift resets it. Replacement/reset releases private generated-default ownership. Assigning the same generated target preserves ownership. The setter does not read the getter or eagerly propagate display. A subsequent getter after reset allocates a fresh default.

Generated defaults are retained by their owner and remain usable without a Graph. Source-shaped copying preserves uninitialized nil without initializing the original; a materialized default is selectively copied and its private ownership follows the copy. Boolean copying retains self-reference to the new Boolean receiver, with no stored self edge or ownership cycle.

Explicitly assigned reference edges keep the existing native graph ownership profile: callers or a Graph retain the target. An expired explicit weak edge is an ownership error; it is not silently reinterpreted as source nil. Use `setReference` for the source setter/reset protocol; the public low-level weak slot remains a storage bridge. In C++, a Boolean held by shared_ptr returns a retaining handle to that same receiver. A stack/otherwise borrowed Boolean returns a borrowing handle whose lifetime must remain within its receiver's lifetime. Swift returns the receiver with its ordinary ARC ownership.

The default constructor behavior is inherited from the implemented source family. Native class registration does not install arbitrary executable class-side defaultReference overrides. Existing callback execution/serialization boundaries remain in force.

## Relation helpers

`allClasses()` copies the relation's supplied classes and sorts by their registered class-side labels, case-insensitively. It does not enumerate the registry, expand subclasses or mutate the stored choices. Duplicate entries remain duplicates. The comparison profile is ASCII, consistent with the existing option sorter; comparisons requiring non-ASCII labels fail explicitly. Empty/singleton lists require no label comparisons. Work/item/text limits bound native sorting; ties have no claimed cross-VM order.

`commonClass()` returns the common superclass of a nonempty class list through the runtime class environment. For an empty list, pinned source returns `self descriptionContainer`, which is an actual fresh container rather than a Class, Object sentinel or nil. The native return types preserve that distinction:

- C++: `RelationCommonClass`, a variant of `Value::Class` and `shared_ptr<Description>`.
- Swift: `RelationCommonClass.classValue(name)` or `.container(description)`.

The default `descriptionContainer()` creates a fresh MAPriorityContainer labelled with the receiver's registered class label. It supports native virtual/open overrides. Helpers reject unknown class identities and calls on unrelated description families. Recursive metadata adapters expose allClasses/commonClass as read-only selectors; Boolean's reference selector is read-only as upstream specifies. These selectors add no invented annotated fields.

## Nil storage, traversal and graph/4

Structural traversal, copy retention, builders/discovery and codecs inspect raw storage without sending a behavioral getter. A nil edge is skipped; a stored edge is traversed; an expired explicit edge still fails. Thus native readers/validators can accept a supported description before any default has been created, and actual conversion/option operations allocate defaults only where source sends reference. Existing option members and empty operations retain their short-circuit behavior.

**Graph/4 now accepts JSON null in a reference node's required `reference` field.** It represents uninitialized/reset storage. Import/export preserves nil and does not allocate defaults, apply display settings or execute callbacks. Graph/1–3 still require explicit reference IDs; the reference field itself remains required. Dangling IDs and malformed shapes still fail. Older graph/4 implementations can reject this newly supported field value, as with other profile extensions.

After a behavioral getter materializes a default, exporting that edge requires registering the returned target in the Graph's description table, just like any other description edge:

```cpp
auto child = option->referenceDescription();
graph.descriptions.emplace(child->id, child);
```

```swift
let child = try option.referenceDescription()
graph.descriptions[child.id] = child
```

Export fails if the materialized target is absent or its ID aliases another object. No implicit graph growth or class-definition envelope is introduced. Private default ownership and native callbacks are not wire state. Recursive metadata getter bindings perform their existing bounded registration automatically; metadata nil writes invoke setReference and the next read binds a fresh target. A Boolean's behavioral self-reference is derived from its class and has no new wire edge.

## Executed checks

On macOS arm64, all 27 CTest targets and 102 Swift tests pass, including the earlier phases. All 27 C++ targets also pass AddressSanitizer/UndefinedBehaviorSanitizer; leak detection is disabled on this host. Both mirrors verify 130 shared fixture payloads. Native exports containing both nil and registered generated references compare and replay in the other port. An installed CMake 0.28 consumer and independent Swift executable exercise the public APIs. These are standalone source/native checks, with no GT connection.

The new checks cover defaults, repeated gets, same-target assignment, reset/replacement, weak expiry, copy ownership, Boolean identity/lifetime, inherited behavior, label ordering, empty/nonempty commonClass results, native container overrides, text/validation consumers, recursive metadata, nil-format gates, callback refusal and missing graph registration. Historical tests expecting missing-reference getter failure were updated because lazy initialization now closes that gap; earlier shared fixture payloads remain unchanged.

Capture/replay with `magritte-default-reference-tests output.json [peer.json]` in C++. Swift DefaultReferenceTests use `MAGRITTE_DEFAULT_REFERENCE_OUTPUT` and `MAGRITTE_DEFAULT_REFERENCE_INPUT`. Remaining collection identity, persistent container state, grouping, Unicode and complete self-description gaps stay separate.
