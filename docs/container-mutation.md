# Container mutation and persistent priority order (0.29)

Both ports implement MAG-003 over native child storage. Container mutations now follow Magritte's identity/equality and receiver-return rules; priority order is stored state and reads no longer sort. Explicit setChildren/resort, copy, builders and metadata edits use the appropriate mutation protocol. Phase 0.30 (MAG-004) adds mutable backing identity and aliases; see [mutable collections](mutable-collections.md).

## Native platform implementation

| Platform | Representation and operations |
| --- | --- |
| C++17 | `std::vector<std::shared_ptr<Description>>`, native pointer identity, bounded binary insertion and `std::stable_sort`; mutations return `Description&`. |
| Swift | `[Description]`, ARC object identity and native array sorting/mutation; fluent methods return `Self` with `@discardableResult`. |

Child objects retain their actual native identity. At phase 0.29 child sequences were native snapshots. Phase 0.30 wraps native storage in shared ownership for explicit backing identity; it does not introduce a simulated Smalltalk collection runtime. The portable boundary carries description identities, values and actual stored order so each platform can reconstruct its own representation. It carries no C++/Swift object layout, executable code or executable implementation; backing alias identity is now represented explicitly in graph/4.

Use `setChildren`/`add`/`addAll` to construct or mutate a container. The public children vector/array remains a low-level stored-sequence bridge for adapters, codecs and rollback. Direct writes bypass the source mutation protocol; changing className from a plain to a priority container also does not initialize or sort its storage. `orderedChildren` returns the stored sequence, retaining the existing null-child check in C++.

## Upstream verification

The Magritte target is [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), reconfirmed as remote HEAD on 2026-10-27 using an independent read-only checkout. `container-mutation-upstream-methods.json` fingerprints thirty inspected Magritte methods and five supporting Pharo collection methods. `container-mutation-scenarios.json` records 58 source-derived steps across plain/priority containers and registered descendants. **GT was not accessed.** Historical GT fixtures remain evidence for their stated earlier profiles.

[MAContainer](https://github.com/magritte-metamodel/magritte/blob/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model/MAContainer.class.st) delegates mutations to children without an explicit return, so each container mutator returns the receiver. Its remove delegates to equality-based collection removal. The upstream [SequenceableCollection extensions](https://github.com/magritte-metamodel/magritte/blob/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model/SequenceableCollection.extension.st) find movement targets with identity, swap one adjacent element, and leave missing/boundary targets unchanged. Priority containers reject both moves.

[MAPriorityContainer](https://github.com/magritte-metamodel/magritte/blob/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model/MAPriorityContainer.class.st) stores a SortedCollection, converts in setChildren, and implements resort through a fresh conversion. Child priority edits do not notify/reorder that collection. Supporting [Pharo SortedCollection source](https://github.com/pharo-project/pharo/blob/81f614957ca93536d2483a0f64480456b0350451/src/Collections-Sequenceable/SortedCollection.class.st) establishes the insertion/bulk-add profile used here: binary insertion for add; addAll inserts individually for batches no larger than one third of the old size, otherwise appends then re-sorts. This matters for stale priorities. It is supporting kernel evidence, not whole-image provenance or a universal VM optimization requirement. Native algorithms implement those observable cases over vectors/arrays.

## Mutation contract

- `setChildren(next)` replaces storage. Plain containers retain supplied order. Priority containers convert to ascending exact numeric priority order.
- `add(child)` appends to a plain container or binary-inserts into a priority container's existing sequence. It does not repair unrelated stale entries.
- `addAll(children)` keeps order/duplicates in plain containers and uses the verified priority bulk-add behavior above. Native input vectors/arrays are snapshots, including self-input calls.
- `remove(child)` removes the first equal child, with the sought description as the left equality receiver, and raises if absent. Existing description equality compares species/accessors and container contents; labels/priorities do not make ordinary element descriptions unequal.
- `removeAll()` installs empty storage. `moveUp`/`moveDown` move the first identical object by one position, with no-op missing/boundary cases; priority containers raise even for a missing target.
- `resort()` is available on priority containers and re-converts a copy of the current sequence. It is not an invented plain-container operation.

All successful operations return the original receiver. Runtime-registered subclasses inherit these operations through their registered hierarchy. Native item/work checks bound inputs, equality searches and comparisons; null C++ child pointers fail explicitly. Set/resort conversion errors leave the previous sequence intact. Priority bulk addition has already appended membership when sorting fails; no rollback or exact failed-sort permutation is claimed. Native stable ties remain the existing port policy; cross-VM tie order is not claimed.

```cpp
auto root = std::make_shared<magritte::Description>();
root->className = "MAPriorityContainer";
root->setChildren({first, second});
first->properties["priority"] = magritte::Value(std::int64_t(50));
auto stale = root->orderedChildren(); // reads the existing sequence
root->resort();
```

```swift
let root = Description(id: "root", className: "MAPriorityContainer")
try root.setChildren([first, second])
first.properties["priority"] = .integer(50)
let stale = try root.orderedChildren() // reads the existing sequence
try root.resort()
```

## Copying, builders and metadata

MAContainer postCopy calls setChildren on a copied sequence; consequently copying a stale priority container re-sorts the copy while leaving the original unchanged. Children themselves remain shared, as in the established selective-copy profile. Selection, range and collect operations perform their source conversions; collect evaluates transformations in source sequence order before converting the completed result. Concatenation, union/intersection, description builders, flatteners and pragma discovery now publish children through the mutation protocol.

Recursive metadata's setChildren setter uses the same conversion. Its existing composition validation still rejects owning cycles, and failure restores the exact old sequence, including stale priority order. Ordinary enumeration, validation, printing, text writers and mementos consume stored order. No priority snapshot is recomputed behind a read.

## Interchange and adaptation

Graph/4 priority-container nodes now include `"childrenOrder":"stored"`. Their children list is the actual sequence, which may contain stale priority order or repeated identities. Import preserves that sequence without conversion; an explicit resort remains necessary to re-sort it. The marker is valid only on priority containers in graph/4 and accepts only the String `stored`.

A priority node without that marker is an existing construction-form snapshot: import uses setChildren and sorts it. This preserves older fixture/producer behavior. Graph/1–3 can still carry non-stale unique-child priority snapshots; exporting stale priority state to those formats fails explicitly. Graph/4 also permits repeated container child IDs, preserving repeated references to the same registered native child. Earlier formats continue to reject duplicates. Missing nodes, ownership cycles, malformed markers and item limits still fail.

Export does not resort or mutate the source. The node table continues to define each child's identity once; child arrays can reference it repeatedly. The marker records state rather than a foreign collection implementation, making adaptation from one native platform to the other preserve observed ordering and aliasing between description nodes. Shared mutable backing-array identity/species remains MAG-004 and is not reconstructed from this marker.

## Executed standalone checks

On macOS arm64, all 28 CTest targets and 105 Swift tests pass. The 28 C++ targets also pass AddressSanitizer/UndefinedBehaviorSanitizer; leak detection is disabled on this host. Both fixture mirrors verify 132 payloads, with previous shared payloads unchanged. Native stale/duplicate graphs compare and replay in the other port. An installed CMake 0.29 consumer and independent Swift executable verify the public APIs, including Swift's subclass-preserving fluent return.

Tests cover all mutator return values; missing/equal/identical/duplicate targets; stale reads, insertion, bulk addition and resort; exact priorities; copy/collect/range behavior; metadata ordering and rollback; failure/bounds; inherited containers; malformed/legacy snapshots; and cross-port adaptation. Earlier native setup code now constructs priority containers with setChildren/resort instead of relying on read-time sorting. Those migrations preserve the earlier expected reference behavior.

Capture/replay with `magritte-mutation-tests output.json [peer.json]` in C++. Swift ContainerMutationTests use `MAGRITTE_MUTATION_OUTPUT` and `MAGRITTE_MUTATION_INPUT`. These are standalone native processes with no GT connection.
