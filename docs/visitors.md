# Visitor dispatch and description builders (0.9)

This phase supplies the missing native `MAVisitor` protocol and its `MADescriptionBuilder` consumer in both ports. The baseline remains upstream `d67f318686b7779aed79416db121e257d1191f2e`; upstream HEAD was rechecked on 2026-10-26. These are headless Magritte operations. No UI, application framework or new wire format was added.

## Audit and choice of phase

The audit compared each port's support matrix, public API, dispatch/validation, option sources, accessors and copy implementation with the upstream model hierarchy and tests, then inspected the live GT visitor and builder methods. The existing graph callback walker follows composition/reference edges, deduplicates identities and terminates cycles. That is useful graph infrastructure, but it does not provide `acceptMagritte:`, typed visitor methods, superclass fallback, or visitor-controlled traversal. Both ports had this same gap. `MADescriptionBuilder` is a small existing upstream consumer that makes those semantics observable through real description transformation.

The other material gaps remain open:

| Area | Audited upstream behavior still missing |
| --- | --- |
| Mutable collections | Shared collection-object identity and alias-sensitive memento behavior; current collections are value snapshots |
| Dynamic options | `MADynamicOptions` completion, membership and reader blocks; `allOptions` can return a provider rather than an Array |
| Accessors and labels | `canRead:`/`canWrite:`, full inferred camel-case labels, composite access/conflict behavior |
| Scalars | Full Smalltalk numeric domains, date/time/duration, URL, color and file descriptions |
| Description construction | Complete pragma-based discovery, description caches, builder composition and `MADescriptionFlattener` |
| Interpretation | Custom interpreter classes, resumable nested exception trees, and all unsupported description kinds |

Dynamic options cannot faithfully be added by eagerly evaluating a closure into the existing static options array: upstream preserves the provider and its separate completion/membership protocols. No such shortcut was introduced. The present phase completes visitor dispatch for the represented hierarchy and base builder behavior, not these separate facilities or the complete headless core.

## Visitor protocol

`Visitor.visit` calls `Description.acceptMagritte`. The selected method defaults through the Magritte hierarchy: for example Memo -> String -> Element -> Description, or ToManyScalar -> ToMany -> Relation -> Reference -> Element -> Description. There are 21 dispatch points covering the fifteen represented concrete description classes and their six abstract bases. Native Description subclasses can override `acceptMagritte` explicitly. Native visitor subclasses override these visit methods; calling the superclass method continues fallback, and omitting that call stops it.

A base visitor does not read models, filter hidden/read-only descriptions, follow references, visit children, or deduplicate repeated objects. `visitAll` visits each occurrence in order and routes each through the virtual/open `visit` entry point. A container override can explicitly visit its children. A registered application subclass inherits the nearest implemented description dispatch; registration does not invent a new class-specific visit selector or enable unsupported validation or interchange semantics.

C++:

```cpp
struct Strings : magritte::Visitor {
    std::vector<std::string> fields;
    void visitStringDescription(magritte::Description& d) override {
        fields.push_back(d.id); // Memo, Password and Symbol also reach this method.
    }
    void visitContainer(magritte::Description& d) override {
        visitAll(d.orderedChildren());
    }
};
Strings visitor;
visitor.visit(*description);
```

Swift:

```swift
final class Strings: Visitor {
    var fields: [String] = []
    override func visitStringDescription(_ description: Description) throws {
        fields.append(description.id)
    }
    override func visitContainer(_ description: Description) throws {
        try visitAll(description.orderedChildren())
    }
}
let visitor = Strings()
try visitor.visit(description)
```

Visitors and builders are mutable local objects. Ordinary native exceptions propagate and stop a batch; depth/work accounting is restored on failure. Subsequent top-level visits start a new budget. `visitAll` limits batch size and shares a work budget with nested visits. Explicit recursive visitors retain repeated occurrences and stop at limits rather than deduplicating them. Calling an individual typed method or `acceptMagritte` directly bypasses the `visit` entry-point budget, as it bypasses any custom `visit` override. Instances require caller synchronization.

## Builder semantics and ownership

`DescriptionBuilder.buildFrom` retains its input, sets `target`, and visits it. `model` is separate caller-supplied context; `priority` starts at zero. Override a typed method, enrich the received description, then call the superclass implementation to add it to the result. Base behavior follows upstream:

- A scalar root becomes the exact input object. An enriching override can therefore mutate that root.
- A container is copied and emptied. Its ordered children are copied separately before visiting them. Repeated occurrences produce separate copies. Reference descriptions follow existing Magritte `postCopy` semantics.
- A priority container preserves its class and priority ordering. Children use their real accessors and can drive ordinary native/adaptive validation and string writing.
- `buildFrom` does not reset an existing `builtDescription`. A later scalar can append to an existing container; appending to a scalar result fails. `setBuiltDescription(nil/nullptr)` explicitly resets the current result.
- A nested container replaces the builder's current result, and subsequent outer fields append to that result. This surprising base behavior is present in pinned upstream and live GT and is preserved here. This is not a flattening or nested-schema repair API.

C++:

```cpp
struct Labelled : magritte::DescriptionBuilder {
    void visitStringDescription(magritte::Description& d) override {
        d.properties["label"] = magritte::Value("Edited");
        DescriptionBuilder::visitStringDescription(d);
    }
};
Labelled builder;
auto result = builder.buildFrom(description, "built", &dictionaryModel);
// result.root and result.retained own the copied graph and weak reference targets.
```

Swift:

```swift
final class Labelled: DescriptionBuilder {
    override func visitStringDescription(_ description: Description) throws {
        description.properties["label"] = .string("Edited")
        try super.visitStringDescription(description)
    }
}
let builder = Labelled()
let result = try builder.buildFrom(description, newIDPrefix: "built", target: dictionaryModel)
// Keep result alive for its copied graph and weak reference targets.
```

A builder owns descriptions it visits through `buildFrom`/`setBuiltDescription`; C++ direct visits to an unretained builder input fail explicitly. Visitor callbacks otherwise borrow the description for the call. C++ `model` and `target` pointers are borrowed; Swift retains them. Result handles retain copied references and shared descendants beyond the builder's lifetime. Existing copy limits apply: recursive reference postCopy is rejected, collection values remain snapshots, and copying is not a graph deep clone. Output identities use the caller's printable ASCII prefix followed by `.N`; generated collisions fail explicitly. A suppressed scalar visit produces a null C++ result root / nil Swift result. Failures can leave partial builder state, just as upstream operations are not transactional.

`MADescriptionBuilder` is registered as an ordinary class with superclass `MAVisitor`; new relation metadata discovers it and its Class value round-trips through graph/4. Existing historical fixture comparisons are projected only in test code to their declared class environments. Production discovery remains open to registrations.

## Reference evidence

`visitor-reference.json` records execution of real GT visitor/builder objects: 21 dispatch traces, no implicit traversal, explicit recursion, repeated batch entries, an override stopping fallback, hidden/read-only behavior, exception interruption, five enriched builder cases, identity/copy checks and state reuse. Abstract dispatch points use initialized `basicNew` instances solely to test those abstract methods. Builder transformations execute ordinary concrete descriptions. Temporary probe subclasses were created and compiled through GT MCP and then removed; absence was checked. No GT-managed checkout was edited.

`visitor-live-methods.json` records 55 method fingerprints. Fifty-four match pinned upstream ignoring whitespace. The installed `MAVisitor>>visit:` additionally aggregates resumable validation errors; pinned upstream simply dispatches. The ports follow pinned dispatch and ordinary native exception propagation, retaining the existing documented flat validation result API. They do not claim Smalltalk resumable exception equivalence.

`visitor-roundtrip-reference.json` records GT reconstructing each port's six-description/one-object builder export, validating it, reading all values and writing `Ada-7-Ada-a`, then reexporting equivalent graph/4 data. Replay requests are included. Operations ran inside `CCNativeMcpLease`; the controller checked post-release completion markers before reading outputs or making the next GT call. No native Runtime resources were allocated.

Generate the native inputs with `magritte-visitor-tests /private/tmp/magritte-cpp-visitor-native.json` and `MAGRITTE_VISITOR_EXPORT=/private/tmp/magritte-swift-visitor-native.json swift test --filter VisitorTests`. Compare native and GT outputs using `tools/compare-graphs.py`. Native-only tests cover ownership, runtime inherited dispatch, current class discovery, identity collisions, item/node/work/depth limits, failure recovery and explicit suppression. This phase was tested on macOS arm64; other platforms remain unexecuted.
