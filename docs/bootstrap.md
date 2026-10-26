# Memento self-description and recursive bootstrap (0.7)

This phase makes straight, cached and checked mementos first-class local targets of recursive metadata sessions, and adds a finite bootstrap over reachable descriptions. The baseline remains upstream [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e), rechecked against remote HEAD and live GT. Native code, tests and reference harnesses were independently authored.

## The memento describes its represented model

Upstream MAMemento overrides magritteDescription to return its stored description by identity. None of MAMemento, MAStraightMemento, MACachedMemento or MACheckedMemento publishes annotated cache/model/original fields in upstream or GT. The supplied description governs reading, writing and validation of the memento's represented values. A second editor can therefore edit the first editor through the same description. A metadata editor's self-description is the metadata schema it was constructed with, rather than a separate schema of editor internals.

`session.bind(id, memento)` retains and returns the **actual Memento**, with its existing cache, originals, model, validation, commit and reset behavior. `session.describe(id, memento)` returns that memento's exact description and publishes it for schemas export. The ID is a nonempty printable ASCII session identity, independent of any model/schema identity. Rebinding the same editor under that ID returns the same object. Reusing an ID for another target, colliding with its reachable descriptions, or giving the same memento two IDs in one session fails before publication. Aggregate session node limits include mementos. Local relations can resolve a bound editor and check its actual memento ancestry.

C++:

```cpp
RecursiveDescriptionModel session;
auto inner = std::make_shared<CheckedMemento>(model, appDescription);
auto schema = session.describe("editor", inner); // schema == appDescription
auto actual = session.bind("editor", inner);    // actual.get() == inner.get()
CheckedMemento outer(*actual, schema, &session.resolver());
outer.writeUsing(*score, Value(std::int64_t(8)));
if (outer.validate().empty()) outer.commit();  // stages inner's cache
if (inner->validate().empty()) inner->commit(); // applies it to model
```

Swift:

```swift
let session = RecursiveDescriptionModel()
let inner = try CheckedMemento(model: model, description: appDescription)
let schema = try session.describe("editor", inner) // schema === appDescription
let outer = try CheckedMemento(model: session.bind("editor", inner),
                               description: schema, graph: session.resolver)
try outer.write(.integer(8), using: score)
if try outer.validate().isEmpty { try outer.commit() }
if try inner.validate().isEmpty { try inner.commit() }
```

An outer editor over a straight memento writes through immediately; over cached/checked mementos it stages their caches. Each layer keeps its own validation/conflict behavior. Commit still does not implicitly validate or provide a rollback transaction. The existing pinned shouldWrite policy and collection snapshot boundary in editing.md remain unchanged. Adding/removing/replacing fields requires the existing reset protocol before reusing a cached editor.

C++ mementos continue to borrow their underlying Model and optional Graph, which must outlive every editor access; session registration does not create ownership of those borrowed objects. Swift retains the Model and holds the Graph weakly. The session retains the memento itself. Binding returns the actual object, so it does not acquire an artificial session-expiry rule: an editor can remain usable after the session ends if all its original dependencies remain valid. Underlying description/accessor adapters still enforce their own session lifetimes.

## Finite recursive bootstrap

`session.bootstrap(description)` walks the input's existing child/reference closure once by actual identity, creates a full selected metadata schema for each reachable Description, and returns an ordinary graph/4 containing the generated schemas. Traversal follows ordered children, then reference edges. Shared nodes and reference cycles terminate. Owning child cycles fail. Names are `bootstrap.<generation>.<target-id>`; the batch root describes the input root. Explicit repeated requests produce fresh generations.

`session.bootstrap(id, memento)` binds the actual editor and bootstraps its represented description graph. It does not invent annotations for the memento class. Generated schemas can later be passed to bootstrap or describeReflective explicitly. Generated metadata is not eagerly described forever within the same request. This batch API is a native convenience over the inspected upstream metadata annotations, not a claim that upstream has a bootstrap selector with this signature.

The whole generated batch is staged and checked for identities, graph validity and configured byte/node/depth/work bounds before publishing any generated schema or advancing the generation. A valid input can remain bound after failure. New batches become part of `schemas()` alongside other published schemas. Reading accessor metadata may still establish live AccessorObject bindings on the original descriptions, as documented in reflection.md.

Memento self-description publication keeps the original mutable schema identity. `schemas()` follows its current reachable closure, including fields added after publication. It also follows the current closure of generated metadata while retaining the previously published schema nodes. It rejects later identity collisions, missing reference owners and owning cycles using shared traversal bounds. Swift's `schemas()` is now throwing; use `try session.schemas()` to handle such invalid mutations. The returned Graph retains the same Description instances; it is not an immutable deep snapshot. Actual graph encoding performs the existing semantic/wire checks.

## Classes and interchange

MAMemento, MAStraightMemento, MACachedMemento and MACheckedMemento join the class-value registry, bringing `portableClasses()` to 65 names. bootstrap-class-registry.json records the current registry; the historical class-registry.json remains the 61-name 0.6 reference profile. The older describeReflective profile retains its 61 class-option choices for fixture/schema compatibility. The new bootstrap schemas expose all 65 choices for relation classes. Interpreter choices remain limited to the actually implemented interpreter classes. A registry Class value never creates an arbitrary host object.

Graph/4 already has the required Class tag and finite relation class constraints; no new format or object kind is introduced. Memento objects, caches and originals stay local. Exporting a resolver containing bound editors fails. Exported schemas are ordinary Magritte descriptions, and committed adaptive objects remain ordinary objects. Before exporting a published application schema carrying live accessor objects, explicitly materialize its accessors. Snapshot boundaries and all earlier unsupported executable/collection identity domains remain in force.

## Executed evidence

bootstrap-reference.json and bootstrap-replay.json record:

- All 65 names resolving to actual GT Classes, plus the absence of memento annotations.
- Three actual memento classes, each checked at seven points: initial, inner write, outer commit, inner commit, external write, validate, reset. Model/description identity, ancestry and checked conflicts are included.
- A 74-description metadata batch for an application Container, Number field and relation back to the application schema. The reference cycle is deliberate; its class constraint accepts actual mementos.
- Every selected metadata getter and validation result, and nested checked mementos staging/committing a Number minimum from 0 to 7 through the existing metadata schema.

Twelve live method fingerprints match pinned upstream ignoring whitespace in bootstrap-live-methods.json. Existing reflection annotation fingerprints remain applicable. Native tests add ID/alias collisions, aggregate editor bounds, failure after staging multiple schemas, byte limits without advancing generation, subsequent owning cycles/ID collisions and fresh explicit recursion. These are native protocol/lifetime checks, not extra GT equivalence claims.

Each port exports 78 descriptions and one adaptive object after the metadata edit and a later field addition. GT reconstructs the graph, validates the application and three metadata schemas, creates an actual checked metadata memento using an imported schema, changes the minimum to 8 and back to 7, and reexports semantically equivalent data. bootstrap-roundtrip-reference.json/replay record this check. Use `magritte-bootstrap-tests /private/tmp/magritte-cpp-bootstrap-native.json` and `MAGRITTE_BOOTSTRAP_EXPORT=/private/tmp/magritte-swift-bootstrap-native.json swift test` to generate inputs.

The current suite has six CTest targets and 37 Swift tests, with C++ Debug, ASan/UBSan, fixture checks and an installed CMake consumer checked on macOS arm64. LeakSanitizer is unavailable here. All GT reference runs use CCNativeMcpLease and an external completion marker checked after release. They allocate no native Runtime resources and change no persistent Smalltalk source. No GT-registered checkout is modified. Full reflective class discovery, arbitrary messages, mutable collection-object identity, all platform scalar types and complete hierarchy bootstrap remain outside this selected headless profile.
