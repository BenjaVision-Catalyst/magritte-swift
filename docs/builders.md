# Builder composition and description flattening (0.16)

Both ports now implement `MAComposedDescriptionBuilder` and `MADescriptionFlattener`, extending the existing stateful description-builder protocol. Description builder lists, exact fractional priorities and explicit host protocol bindings supply the parts these classes need. No UI or application framework dependency is introduced.

## Source and reference evidence

The source baseline remains [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model); remote HEAD was checked on 2026-10-27. `builders-live-methods.json` records 18 matching live/upstream method fingerprints and the missing flattener selectors. It is a selected-method comparison, not a whole-image provenance claim.

Fresh live GT fixtures cover 19 flattening cases, 24 `canExpand` flag/group/tab combinations, nine composition cases, 130 exact integer/fraction/Float comparisons and six priority arithmetic cases. The native tests consume complete results, fields, priorities, shared-object checks, callback/read traces and partial failure states. Error occurrence is compared; Smalltalk exception classes, messages and resumable error trees are not treated as native exception contracts.

Four temporary probe classes provide explicit model descriptions, a traceable dictionary protocol, pipeline steps and the missing description hooks. They were created and compiled only through GT MCP. `builders-probe-setup.json` records their actual live sources separately from upstream and includes cleanup verification. The probes were removed through GT MCP and their absence was verified; the original Magritte classes and their missing selectors remain unchanged. Class names in the native scenarios use the existing represented description classes, with the probe methods supplied as explicit environment bindings. This is a declared platform-protocol projection, not a claim those missing methods exist upstream.

GT reconstructed each port's four-description flattened graph, preserved its exact fractional priority, validated its adaptive object, read/wrote the expected `P-Ada-S` string and reexported a semantically equivalent graph/4. Replay requests and `builders-roundtrip-reference.json` preserve this evidence. `tools/compare-graphs.py` compares each native export with its GT reexport.

All reference operations ran inside `CCNativeMcpLease`. Controllers checked the completion marker outside GT before reading artifacts or starting another GT request. The operations allocated temporary Smalltalk objects only, with no native Runtime/plugin resources requiring an independent Runtime owner. Native suites run as separate standalone processes. No registered GT checkout was changed externally.

## Composition

`setDescriptionBuilders` sets a container's `descriptionBuilders` Class list and its `descriptionBuilder` to `MAComposedDescriptionBuilder`, matching the upstream setter's side effect. The defaults are an empty list and nil builder. Pipeline order is list order; builder priority does not sort it.

A composed builder:

- Starts container composition with the original container, without copying or implicitly visiting its fields. An empty pipeline returns that same object.
- Feeds each result into the next step and forwards the current target plus the separate original `model` context. A replacement becomes the next input. A failing step stops the pipeline and leaves previous mutations/results visible.
- Gets a scalar's pipeline from the target's `magritteDescription`, rather than from scalar properties.
- For a relation, gets the pipeline from the original target's description, reads the relation, and builds its reference with the relation value as target when non-nil. It then continues ordinary visitor fallback, which may separately apply the original target's pipeline to the relation itself. Nil relation values preserve the reference. To-many relation values remain collection targets; they are not silently reduced to one object.

A named `BuilderStep` uses a fresh builder from an open runtime factory registry, corresponding to upstream class-side `buildFrom:target:model:`. `registerDescriptionBuilder` adds an application implementation and its class identity; identity registration alone does not invent executable code. The built-in factories are the base, composed and flattening builders. Class lists can be encoded as graph/4 metadata. `BuilderEnvironment.descriptionBuilders` also supplies local `BuilderStep` callbacks for protocol-bearing objects, as exercised by the GT trace probes. These operations are ordinary local code and are not serialized.

The base builder's container visit assigns its copied container directly, as upstream does; it does not call an overridden composed `setBuiltDescription` accidentally. Existing reuse semantics remain stateful. C++ model/graph pointers are borrowed; Swift retains its context. `DescriptionCopy` owns retained graph targets, and its public Swift initializer lets custom builder steps supply those owners. New root IDs use the caller's prefix; pipeline steps receive distinct sub-prefixes. Collisions and invalid/null inputs fail explicitly. Failures are not transactions.

## Flattening and hooks

`canExpand` first honors an explicit Boolean override. Its default checks visibility, read-only, `tabDisplay`, then whether group is nil, in exactly that order. An explicit true can bypass those defaults. Empty strings count as a non-nil group.

The flattener overrides to-one relation visits. It uses the target directly, or a collection target's sample (`anyOne`, represented by the snapshot's first element). An empty target collection or nil relation value falls back to the base builder and preserves the field. It does not use the relation's reference description to expand: it asks the actual related value for its description.

For each child of that value's description it reads the child's value **before** changing its accessor, then:

1. Calls `addToAccessor:` with the parent accessor.
2. Assigns `parent priority + (child priority / 1000)` without rounding.
3. Assigns either the parent's label or the parent's group, according to `groupExpandOnLabel`.
4. Recursively expands the child when `canExpand` says true; otherwise appends that same child object.

The children come from the model's shared description and are mutated in place; they are not copied by expansion. Prefix/suffix fields copied by the base container builder remain distinct. Earlier mutation can survive a later failure. A primitive related value's default empty description contributes no fields; the flattener does not invent scalar reflection. A standalone expandable relation without an initialized built container can fail when it tries to append a field, just as the upstream protocol can.

**Upstream and live GT do not implement `tabDisplay`, `groupExpandOnLabel` or `addToAccessor:` in these description classes.** Missing hooks therefore raise native protocol errors. `BuilderEnvironment` supplies explicit bindings for them and for host `magritteDescription` lookup. Adaptive models use their existing description by default; other native models have no annotated fields unless a lookup callback supplies their description. Primitive/nil/collection values have no invented annotation schema. Nonempty custom scalar reflection requires an explicit model/reference bridge and remains outside the current profile. Grouping and accessor-prefix behavior are determined by the supplied hooks, not silently assumed by the core. The successful reference probes explicitly supply a chain-prefix hook and a Boolean grouping hook; the missing-hook failure cases execute unchanged Magritte classes.

This preserves the runnable upstream algorithm and its extension points rather than hiding missing selectors behind guessed defaults. Full pragma discovery, description-cache orchestration and automatic builder invocation by a platform's description provider remain separate work.

## Exact priorities

Flattening produces Fractions even for ordinary integer priorities, for example `100 + 10/1000 = 10001/100`. Both ports now support normalized exact fractions with an Int64 numerator and positive Int64 denominator. `Value::Fraction` (C++) and `Value.rational` / `.fraction` (Swift) use exact equality and numeric ordering, including comparison with finite binary64 values. Fractions with denominator one canonicalize to integers through construction/decoding. The new `priorityValue()` preserves the numeric value; the existing integer `priority()` getter remains available and rejects non-integer priorities. Priority containers compare numeric priorities exactly.

The graph/4 Value representation is:

```json
{"type":"fraction","value":{"numerator":"10001","denominator":"100"}}
```

Older graph formats reject fraction tags. Zero/negative denominators and noncanonical integer strings are rejected. Arithmetic is checked, including intermediate products, and raises on overflow; arbitrary precision is not claimed. Binary64 inputs used in priority arithmetic must fit an exact bounded ratio. This addition is required by flattening; it does not add the complete Smalltalk numeric hierarchy, NumberParser fraction grammar or Fraction parity protocol. Existing exact mixed-number ordering remains intact. The new Swift enum case requires external exhaustive switches to be updated.

## Limits and ownership

Named recursive compositions share a depth/work guard across fresh builder instances. Flattening bounds recursive expansion depth/work and field counts. Builder results retain weak reference targets, check IDs and ownership, and recheck structures returned by local steps. Native callbacks retain ordinary host execution time and exception behavior; the library is not a VM or sandbox for callback code. Reusing mutable builders, schemas or registries across threads requires caller synchronization. Runtime factory registration is synchronized; user closures are not made thread-safe automatically.

Collection targets and collections in values use existing snapshot semantics; no mutable collection identity or generic host message reflection is added. Class names remain runtime-open; executable builder factories and model/hook implementations are explicit platform bindings.

## Native usage

C++:

```cpp
magritte::ComposedDescriptionBuilder composed;
composed.environment.graph = &graph;
composed.environment.describe = descriptionForModel;
auto built = composed.buildFrom(schema, "built", &target);

magritte::DescriptionFlattener flatten;
flatten.environment = bindings; // model descriptions and the three extension protocols
flatten.model = &originalModel;
auto flat = flatten.buildFrom(schema, "flat", &target);
```

Swift:

```swift
let composed = ComposedDescriptionBuilder()
composed.environment = bindings
composed.model = originalModel
let built = try composed.buildFrom(schema, newIDPrefix: "built", target: target)

let flatten = DescriptionFlattener()
flatten.environment = bindings
let flat = try flatten.buildFromValue(schema, newIDPrefix: "flat", target: collectionValue)
```

Use `setDescriptionBuilders(container, ...)` for a Class pipeline; use environment callbacks for local protocol objects. Keep result handles and borrowed C++ model/resolver owners alive. Materialized result graphs carry descriptions and metadata, not executable hooks or factory code.

Executed on macOS arm64: all 15 CTest targets, all 15 under AddressSanitizer/UndefinedBehaviorSanitizer, and all 56 Swift tests pass. LeakSanitizer is disabled on this host; no leak-check claim is made. The builder C++ test executes 461 checks. An independent installed CMake consumer runs composition/flattening/exact-priority operations, and a separate Swift consumer type-checks the public API. All 106 fixture hashes match their mirror.
