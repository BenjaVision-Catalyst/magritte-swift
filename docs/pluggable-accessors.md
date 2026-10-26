# First-class pluggable accessors

Phase 0.12 implements the local `MAPluggableAccessor` protocol in both ports. The semantic baseline remains [upstream d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e), verified against upstream HEAD on 2026-10-26. Seventeen inspected live GT methods match the pinned source ignoring whitespace; `pluggable-accessors-live-methods.json` records their fingerprints. Independently authored native tests implement observed behavior without copying upstream source or test bodies.

## Audit and scope

The previous phase supported eight accessor strategies and description-level native callbacks. The latter did not represent an actual pluggable accessor: they could not participate in normal accessor chains, block-identity equality or accessor-object self-description. This phase fills that gap using the existing Magritte Accessor, Model, Description and editing protocols.

The audit also inspected MACompositeAccessor/MACompositeConflict and accessor label/name inference. Composite conflict objects require additional value/object semantics, while inferred labels remain an independently documented gap. They are not silently represented as ordinary field values or changed as part of this phase. Scalar domains, mutable collection identity and full builder/cache/interpreter protocols remain pending in the support matrix.

## Block slots and capabilities

`Accessor.pluggable` creates an accessor with independently optional `readBlock` and `writeBlock` slots. Both absent is a valid local unconfigured accessor. A read block receives the target Model and returns a Value. A write block receives the Model first and Value second. Callbacks use the native Model adapter rather than an arbitrary Smalltalk object or a generated schema-specific type. Existing native objects can expose their bound host slots or be captured using ordinary host-language ownership rules.

`canRead` and `canWrite` inspect only their corresponding block slot. They do not inspect or resolve the target, invoke callbacks, enforce flags or apply defaults. The GT fixture includes dictionary, Object and nil targets to establish this receiver-independent rule; native tests project Object/nil onto an empty Model adapter because the native Model interface requires an object. Neither a new nil-valued host-object system nor arbitrary scalar reflection is introduced.

Missing blocks fail explicitly on read/write. Exceptions from callbacks propagate. Reads and writes compose with delegators and chains through their existing APIs. Capability checks on a chain still execute intermediate getters as required by Magritte, while its terminal pluggable capability query only checks a slot. Mementos use the ordinary model access path, so staged reads, changes, validation and commit execute the same configured accessor.

## Identity, copying and equality

Native block objects retain identity separately from callable source or captured values. `accessorEqual` compares accessor strategy and block identities, including absence. Two pluggable accessors using the same read/write block objects compare equal; two separately created blocks with identical code do not. Properties and description identity remain outside existing Magritte description equality. General accessor hashing and Smalltalk source printing/decompilation are not introduced as native APIs in this phase.

Accessor value copies share the block objects and their captured state. Replacing a copied accessor's slot affects only that copy. C++ uses shared ownership of const std::function objects, which also preserves the state of mutable lambdas across shallow copies. Swift uses reference objects wrapping closures; reuse a ReadBlock/WriteBlock object when shared block identity is intended. Invocation retains the current block through a slot replacement, including when a callback clears its own slot.

`AccessorObject` provides the existing local accessor-object identity and mutable slots. Description copies create distinct live accessor objects whose block slots remain shared, following upstream MADescription postCopy. Changes to a live object's slots are observed by subsequent model reads. Callers synchronize mutable accessors and captured state; these types do not add concurrent execution guarantees. C++ Model references remain borrowed; Swift callback captures follow ARC ownership rules. Avoid retain cycles as with other native closures.

C++:

```cpp
using namespace magritte;
auto read = std::make_shared<const Accessor::ReadBlock>([](const Model& model) {
    return model.readSlot("MADictionaryAccessor", "name");
});
auto write = std::make_shared<const Accessor::WriteBlock>([](Model& model, const Value& value) {
    model.writeSlot("MADictionaryAccessor", "name", value);
});
auto accessor = Accessor::pluggable(read, write);
auto copied = accessor; // Shared blocks, independent slots.
DictionaryModel model;
accessor.write(model, Value("Ada"));
auto result = copied.read(model);
bool equal = accessorEqual(accessor, copied);
```

Swift:

```swift
let read = Accessor.ReadBlock { model in
    try model.readSlot(strategy: "MADictionaryAccessor", name: "name")
}
let write = Accessor.WriteBlock { model, value in
    try model.writeSlot(strategy: "MADictionaryAccessor", name: "name", value: value)
}
let accessor = Accessor.pluggable(read: read, write: write)
var copied = accessor
let model = DictionaryModel()
try accessor.write(.string("Ada"), to: model)
let result = try copied.read(model)
let equal = try accessorEqual(accessor, copied)
copied.writeBlock = nil
```

The existing `Description.nativeRead/nativeWrite` convenience callbacks are preserved. They retain their separate direct-native-object calling convention and explicit equality/export limitations. First-class accessor users configure `description.accessor` or `description.accessorObject` instead; neither convenience API is silently converted to another representation.

## Self-description and discovery

MAPluggableAccessor is registered with superclass MAAccessor and its upstream label/abstract status. Runtime class registration remains open; this additional built-in identity is not a class-discovery ceiling. Historical registration fixtures already used this class as an added runtime identity. Their tests now count only newly introduced definitions, retaining idempotent registration when that identity is already built in.

Its actual upstream annotated self-description is empty. Both ports return that empty ordinary container, and a represented description's accessor-derived name is nil. Native block slots are configured through the local typed API, not invented metadata fields or a new Value closure type. Existing recursive adapter discovery remains the selected Value-based protocol rather than arbitrary message reflection. Class-valued metadata can name MAPluggableAccessor without encoding an executable instance.

## Interchange and bounds

Pluggable accessor instances are local executable behavior. Export rejects them, including unconfigured instances, hidden fields, nested chains/delegators and explicit accessor-object snapshots. Import rejects every MAPluggableAccessor record. No callback names, bytecode, source strings, captured state or execution endpoint is encoded. Taking an AccessorObject snapshot/materializeAccessor does not turn its blocks into portable data. The application must explicitly choose an ordinary supported accessor if it intends to export an equivalent portable description.

Read results and write inputs use the current finite Value profile and its configurable codec bounds. Invalid write inputs fail before invoking the write callback; an invalid read result fails after its callback has executed. Accessor structure and queries retain visit/depth limits. These checks do not bound callback execution time or undo callback side effects. No full Smalltalk object domain, arbitrary closure interpreter or mutable collection identity is claimed.

## Executed evidence

`pluggable-accessors-reference.json` was exported through GT MCP using real MAPluggableAccessor, MAChainAccessor, descriptions and MACachedMemento objects. It records 12 capability combinations, seven typed read/write cases with argument/identity traces, seven equality results, copy/captured-state behavior, four composed operations, three editing snapshots, missing/throwing-block failures, class discovery and the empty annotated schema. Native failure tests require explicit errors without claiming the same Smalltalk exception class or resumable exception tree.

`pluggable-accessors-replay.json` contains the reference GT MCP request. No classes or methods were compiled or modified in the image for this phase. Its registered source checkouts were inspected and left unchanged. Pure Magritte operations ran inside CCNativeMcpLease, and the controller checked each completion marker outside GT before inspecting output or making another GT call. No native Runtime/plugin resources were allocated.

After explicitly replacing the local accessor with a dictionary accessor, each port exports two descriptions and one edited adaptive object. `pluggable-accessors-roundtrip-replay.json` imports those graphs into actual GT objects, validates and reads them, writes their string representation and re-exports the supported data. `pluggable-accessors-roundtrip-reference.json` records both runs; semantic graph comparison against each native output passes. This verifies portable results after an explicit change, not closure round-trip execution.

Native-only tests additionally cover live accessor snapshots, self-clearing callbacks, mutable C++ callable state, strict import/export rejection, malformed shapes and bounded input/output. macOS arm64 validation: eleven CTest targets, all eleven with AddressSanitizer/UndefinedBehaviorSanitizer, 45 Swift tests, an installed CMake consumer and an independent Swift API import. LeakSanitizer is disabled on this host; no leak-check claim is made. Other platform intentions remain unchanged.
