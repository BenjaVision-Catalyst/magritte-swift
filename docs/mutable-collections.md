# Mutable collection identity (0.30 / MAG-004)

Both ports now distinguish inline Value snapshots from explicitly shared mutable collection objects. Arrays, OrderedCollections, Sets, Bags and Strings use native storage: C++ vectors, strings and maps under `shared_ptr` ownership; Swift arrays, strings and dictionaries in reference boxes under ARC. The Value layer adapts these platform representations to Magritte operations. It does not emulate a Smalltalk heap.

`CollectionStore.create` creates a collection handle (a local ID is optional); copying a handle preserves identity. `elements`/`snapshot` copies the outer native storage while retaining nested collection handles. `shallowCopy` creates a distinct collection with the same elements, including nested aliases. Ordered/Array membership may be cyclic. Scoped ownership keeps cyclic edges weak internally and roots strong, so dropping the ownership scope and its root handles releases a cycle. A retained root remains valid after its CollectionStore facade leaves scope. The store owns all allocated nodes until that scope is released, including copies; callers should choose a scope matching their object graph or editing session. This is explicit native ownership, not automatic tracing garbage collection.

```cpp
CollectionStore storage;
auto items = storage.create("ordered", "items", {Value("base")});
auto alias = items;
auto original = items.shallowCopy();
items.mutableCollection()->append(Value("outside"));
// alias sees two elements; original still has one.
```

```swift
let storage = CollectionStore()
let items = try storage.create(kind: "ordered", id: "items", elements: [.string("base")])
let alias = items
let original = try items.shallowCopy()
try items.mutableCollection().append(.string("outside"))
```

Array and String sizes are fixed; indexed replacement uses zero-based platform indices. OrderedCollection, Set and Bag support append/removal/clear. Set uniqueness and Bag multiplicity use the existing supported Value equality. Mutable members of hashed collections are rejected because mutating an equality/hash key is outside the stable hashed-key profile. Related mutable collections must belong to one ownership store; cross-store edges fail explicitly. The supported profile does not add arbitrary collection subclasses, mutation notifications, deepCopy/fullCopy, tracing GC, thread safety or rollback transactions. Independently recursive equality without a terminating source result raises a bounded error; identity comparison and shallow copies of cyclic collections terminate.

## Mementos follow source copy boundaries

`MACachedMemento` retains raw collection aliases when it cooks pulled values. Writes stage the exact supplied object; commit preserves its identity. `MACheckedMemento.reset` first resets that cache, then performs its separate raw pull. It shallow-copies an original only when the value is a collection and the description is an `MAReferenceDescription` with `isMultiple=true`. This includes multiple options, not just relations. Single references and non-reference descriptions retain the original object. Class values remain singleton values.

An external in-place edit may therefore leave model and cache equal (`hasChanges=false`) while a checked original differs (`hasModelChangedElsewhere=true`). That alone is not a conflict. Nested collection edits remain visible through shallow originals. A staged replacement can create a conflict; commit still does not implicitly validate. Reset rebinds the cache and creates new shallow originals. The two historical GT alias rows in editing-boundaries-reference.json now execute unchanged in both ports; no live GT image was accessed for this phase.

## Native container backing

C++ `DescriptionChildren` wraps a shared native vector; `storage()->values` provides that vector. Swift `DescriptionChildren.values` is a native Array in an ARC reference box, available through `Description.childCollection`. Plain `setChildren` with that shared backing aliases it. The array/vector overload creates a new backing collection. Adding/removing children through either alias changes the shared collection. `removeAll` replaces the receiver's backing. Fixed Array backing permits moves but rejects size changes.

Priority assignment converts to fresh sorted backing. A plain container can alias that backing and then inherits its sorted insertion behavior. Priority resort replaces its backing, leaving an old alias attached to the previous collection. `postCopy` copies the backing and shares child descriptions; it never recursively clones the child graph. Direct native vector/array edits remain platform operations; use the source-shaped APIs for Magritte construction/mutation behavior.

## Interchange

Graph/4 optionally adds `collections: [{id, kind, elements}]`; Values refer to these rows with `{type: "collectionReference", value: id}`. IDs are interchange labels; native identity is node identity, not ID text or content equality. All rows are allocated before linking elements, allowing aliases and cycles. Export visits reachable rows only, adapts roots from independent native ownership stores, and gives distinct native objects distinct wire IDs even when their local labels coincide. Inline snapshot tags are unchanged. A standalone Value codec has no identity table and rejects mutable handles rather than flattening them.

Graph/4 also optionally adds `childCollections: [{id, kind, children}]` and a container `childrenCollection` reference. `kind` is ordered, sorted or array. The ordinary children sequence must agree exactly with the referenced backing, including duplicate IDs and stale ordering. Only shared or otherwise non-default backing needs a table row. Import attaches the same native backing to all referring containers. Composition cycles remain unsupported as before. Older graph versions reject identity-bearing features, and dangling/duplicate identities, unsupported kinds, inconsistent snapshots and limits fail explicitly. These are portable data records, not callback or VM-object serialization.

## Verification

Source revision: `d67f318686b7779aed79416db121e257d1191f2e` of magritte-metamodel/magritte. The source fingerprint fixture records the exact memento/container/reference methods consulted and supporting Pharo collection species/identity equality. Eight independently authored checked-original cases, the unchanged historical aliases and an explicitly authored graph fixture are shared. Tests also cover native mutation failures, nested aliases, cyclic ownership, shallow copies, reset/commit/conflict state, sorted/fixed/shared backing, graph feature gates and C++↔Swift replay. Standalone package tests and C++ sanitizers require no GT access.

On macOS arm64, the final debug and ASan/UBSan runs each pass all 29 CTest targets; the dedicated mutable-collection executable passes 154 checks, including cross-port replay. Swift passes all 110 tests. Both mirrors verify 135 shared payloads; the earlier 132 payloads are byte-unchanged. The exported graphs compare semantically, and an installed CMake 0.30 consumer and an independently linked Swift executable exercise the public APIs. LeakSanitizer is unavailable on this host, so ASan uses `detect_leaks=0`; native weak-ownership tests check cyclic arena release. Verification did not use GT.
