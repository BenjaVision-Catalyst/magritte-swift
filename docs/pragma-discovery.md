# Pragma description discovery (0.17)

Both independent ports implement the headless `MAPragmaBuilder` discovery protocol through runtime method registration, identity-based dynamically scoped caches, dynamically scoped described objects and `MADescriptionContext`. Native registrations supply the method/pragmas that a Smalltalk image discovers through its compiler. Applications can register new model classes and methods without editing either library. This extends the runtime class environment; it does not introduce another schema model.

## Evidence and limits of verification

The source baseline is [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), with remote HEAD reconfirmed on 2026-10-27. The audit identified pragma discovery/cache orchestration as a missing core layer beneath the already implemented description composition/builders.

`pragma-live-methods.json` records eighteen live GT method sources captured before the user requested avoiding GT to protect another chat's timing/memory measurements. Sixteen match the pinned source ignoring whitespace; the two Object methods add only `<gsCode: nil>`. The source fingerprints preserve those differences. They are selected-method evidence, not whole-image provenance.

**Fresh live-GT behavioral validation and GT graph replay are deferred at the user's request.** No GT probes were created or executed for this phase. `pragma-scenarios.json` contains seventeen expectations derived from the pinned source, exercised independently in both native implementations. These cover inheritance, tagged and untagged overrides, duplicate inherited extensions, nil/replacement results, recursive descriptions, seeded/default/custom containers and partial failure states. These are source-backed native tests, not executed GT reference results. Native graph comparison additionally checks generated schema, context snapshots, adaptive-object values, validation and `7-Ada` text output.

## Registration and discovery

`DescriptionMethodRegistry` keys each current binding by defining class and selector. A binding declares its argument count, pragma selector/arguments and native operation. Installing it again replaces the current method; removing it restores inherited lookup. Class identities come from `ClassRegistry`. Registry mutations are synchronized and callbacks run outside its lock. Active caches keep their previously built descriptions after a recompile, just as a dynamically bound identity dictionary does.

The default Object `descriptionContainer` binding carries `magritteContainer`, returning a `MAPriorityContainer` labelled with the actual target class's label. Discovery walks the target hierarchy through Object:

- The first `magritteContainer` method with zero arguments supplies the container. All one-argument container methods are invoked with that same container; their return values are ignored.
- `magritteDescription` selectors form a set. A selector inherited from an annotated method dispatches to the most specific implementation, including an unannotated override. Duplicate annotations do not cause duplicate field getters.
- `magritteDescription:` groups extensions by the pragma's getter selector argument. Extension method selectors are sorted; inherited duplicates remain and each dispatches through the actual target class.
- Every field extension receives the **original** getter result. Its return becomes the latest result but is not passed to the next extension. A nil getter skips its extensions; a nil last result omits the field. Fields are added to the container only after the whole field pass succeeds.

Within one class, native container annotations follow registration order. Field getter selectors are enumerated in ASCII order as one deterministic realization of upstream's unordered Set. Callbacks must not depend on matching a particular VM's Set enumeration or same-class compiled-method enumeration. A custom `MAContainer` preserves that insertion order; `MAPriorityContainer` uses the existing priority protocol. Extension selector ordering is explicit upstream behavior.

Native bindings use printable ASCII identities and the existing finite Value profile for pragma arguments. Unmatched argument values never select an extension. Callbacks and registration metadata are process-local. The bridge does not compile Smalltalk methods or inspect C++/Swift source annotations; registrations provide those host reflection operations.

## C++ example

```cpp
using namespace magritte;
ClassRegistry::global().registerClass({"ExamplePerson", "Object"});
DescriptionMethodRegistry::global().install({
    "ExamplePerson", "descriptionName", 0, {{"magritteDescription", {}}},
    [](DescriptionRequest& request, std::shared_ptr<Description>) {
        auto d = std::make_shared<Description>();
        d->id = request.builder.freshId();
        d->key = "name";
        d->properties["label"] = Value("Name");
        return DescriptionCopy{d, {d}};
    }
});
auto model = std::make_shared<DictionaryModel>();
PragmaBuilder builder;
auto cache = std::make_shared<DynamicDescriptionCache>("person");
DescriptionCacheScope scope(cache);
auto result = builder.forTarget(DescriptionTarget(model, "ExamplePerson"), "unused");
// Repeated calls for this object's identity in this scope return result.root.
```

The borrowed `Model&` target initializer requires the model and optional identity token to outlive the cache. The shared-owner initializer retains the model. Callback results must retain their weak reference targets through `DescriptionCopy.retained` or an existing returned cache handle.

## Swift example

```swift
try ClassRegistry.shared.registerClass(ClassInfo(name: "ExamplePerson"))
try DescriptionMethodRegistry.shared.install(DescriptionMethod(
    className: "ExamplePerson", selector: "descriptionName",
    pragmas: [DescriptionPragma("magritteDescription")]
) { request, _ in
    let d = Description(id: try request.builder.freshID(), key: "name")
    d.properties["label"] = .string("Name")
    return DescriptionCopy(root: d)
})
let model = DictionaryModel(["name": .string("Ada")])
let builder = PragmaBuilder()
let cache = try DynamicDescriptionCache(idPrefix: "person")
let result = try withDescriptionCache(cache) {
    try builder.forTarget(DescriptionTarget(model, className: "ExamplePerson"), idPrefix: "unused")
}
```

Targets retain their model and optional host identity token. Swift `DescriptionCopy.retained` exposes the ownership snapshot for graph materialization. Both ports retain the active cache with a returned handle so early recursive handles keep later graph growth alive. Reference edges themselves remain weak.

## Dynamic scope and recursion

`DynamicDescriptionCache.current` returns the bound cache or a fresh empty cache outside a scope. A builder call binds its chosen cache during construction. Outside an explicit scope each top-level call rebuilds. Keys are target object identities, not classes or equality values. C++ `DescriptionCacheScope` and Swift `withDescriptionCache` restore the previous binding even on error. Dynamic scopes are synchronous and thread-local; they are not Swift task-local async scopes. Cache/model/description mutation requires caller synchronization.

Container providers and extensions run with `DescribedObjectScope.current()` / `DescribedObject.current` bound to the target. Field getters and extensions run after that inner described-object scope unwinds, seeing any enclosing binding. The completed container is cached **after** its providers/extensions and **before** field getters, permitting self and mutual field references. Recursive container providers have no early placeholder and fail at the configured depth/work limit. A field failure leaves the cached container with its pre-existing children; a container-provider failure leaves no entry. A nil/scalar container is cached before the later `addAll:` failure, preserving the observable partial state.

Cache construction bounds targets, retained descriptions, annotations, children, depth and work with `Limits`; exceeding a limit throws without inventing a valid partial schema. Runtime registration is open, and the built-in class seed is not a registration ceiling.

## Defining context and interchange

A non-nil getter result receives `DescriptionContext(modelClass, methodSelector)` before extension execution. `modelClass` is the actual described class. `methodClass()` and `compiledMethod()` resolve the current most-specific method binding, so an inherited declaration can identify an overriding owner. Context equality/hash use its class/selector fields. Missing model class is an error when resolving methods; a known class with an absent selector has no method. Replacement descriptions do not automatically inherit the original's context. Description copies share the local context object, matching property shallow-copy behavior.

Graph/4 optionally stores a description node's `definingContext` with exactly `modelClass` (Class or nil) and `methodSelector` (Symbol or nil). Unknown classes, wrong value kinds and extra keys fail import. Older graph formats reject contexts. This snapshots context data; shared context object identity, callback code, dynamic caches and executable compiled methods are not serialized. Old fixtures retain their bytes and previously supported wire forms.

This phase ports `Object>>basicMagritteDescription`'s core discovery behavior. The broader `Object>>magritteDescription` integration with external QC builder containers, arbitrary VM notifications/reflection, UI source-navigation views, action descriptions and complete self-description discovery remain separate gaps. Pragma tag accessors are overridable for native builder specializations; this does not claim unsupported action/UI semantics.

## Executed standalone checks

On macOS arm64, all sixteen CTest targets and 61 Swift tests pass. The discovery C++ target passes 264 checks under both the ordinary build and AddressSanitizer/UndefinedBehaviorSanitizer (leak detection disabled). A separately installed CMake 0.17 consumer runs successfully; an independent Swift consumer type-checks against the public module. All 108 shared fixtures verify, and the previous 106 fixture payloads are unchanged.

To reproduce the native graph comparison after building both ports:

```sh
# In magritte-cpp:
build/magritte-pragma-tests /tmp/pragma-cpp.json
# In magritte-swift:
MAGRITTE_PRAGMA_EXPORT=/tmp/pragma-swift.json swift test --filter PragmaTests
# In magritte-cpp:
python3 tools/compare-graphs.py /tmp/pragma-cpp.json /tmp/pragma-swift.json
```

These commands use the two standalone ports and saved fixtures only. They do not contact or validate against the live GT image.
