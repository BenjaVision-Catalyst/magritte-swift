# Validation protocol and nested errors (0.31 / MAG-005)

Both ports implement the default upstream validator through native results and error objects. `validateDetailed` and `validateValueDetailed` return `ValidationResult`, whose optional `error` is the actual nested `ValidationIssue`. `passed` tests whether it is absent. The existing `validate` / `validateValue` APIs project that same result to ordered flat `ValidationError` leaves. They no longer maintain a separate validation algorithm.

A validation issue retains its description tag, actual error class, optional original signal text and ordered child collection. C++ uses shared pointers, optional strings and vectors; Swift uses ARC references, Optional String and Array. Shared C++ descriptions remain owned by errors after their graph/caller releases them. A C++ stack description remains a borrowed tag and must outlive its errors, like any native reference view. Swift retains every tag. Issue collections are immutable diagnostic records; tag identity and subsequent tag-label changes remain observable.

All validation issue classes inherit the registered MAValidationError hierarchy, and `isResumable` is true. Class discovery remains open: applications may register additional error subclasses. `ValidationResult.raiseIfInvalid` raises the native `ValidationFailure` retaining the exact root issue. Operational failures (unbound accessors, invalid message results, host exceptions and exhausted bounds) propagate separately. `isSatisfiedBy` returns false for validation failures and does not turn operational failures into success or false validation leaves.

```cpp
auto result = validateDetailed(*schema, model, {}, &graph);
if (result.error) {
    auto tag = result.error->tag;
    auto children = result.error->collection;
    auto leaves = result.flatErrors();
    auto text = result.error->printString();
}
```

```swift
let result = try validateDetailed(model, using: schema, graph: graph)
if let error = result.error {
    let tag = error.tag
    let children = error.collection
    let leaves = try result.flatErrors()
    let text = try error.printString()
}
```

## Source execution order

Every visible, writable description visit collects its validation errors and emits one MAMultipleErrors when any were collected, even when there is just one. Its tag is that description; its signal text is the description's label. Child visits retain their own wrappers. An extensible option's reference validation retains the reference's wrapper inside the option's wrapper. Sibling order and repeated visits to the same reference description are retained; the tree is not flattened or deduplicated.

Within a description, required checks run first. Emission resumes execution. Equality with undefinedValue then skips kind, specific checks and conditions. Equality uses the incoming object's receiver semantics, including a bound model equality message. Kind checking runs inside `tryValidation:ifPass:`: any validation error emitted during that stage prevents specific checks and conditions. Multiple relation/option outer-kind failure prevents member iteration, while member failures resume to check subsequent elements. Single relation/option superclass-kind failures resume into their remaining class/membership checks. Specific failures, such as range errors, resume into conditions.

A container first validates its actual model target, including its own conditions, then visits children when the target is non-nil. Its own undefined return or failed kind stage does not skip child visits. Invisible/read-only containers skip their entire visit. The parent reads a child before that child's visibility/read-only gate, matching MAValidatorVisitor>>visitContainer:. A scalar model entry overload retains the existing no-read gate before materializing its field value.

`ValidationContext.signal` records an error and returns its actual object, allowing native statements to continue. `tryValidation(body, ifPass)` executes ifPass only if body adds no validation error; errors already in the context do not suppress it. `include` retains a nested result and `finish` creates the visit wrapper. This explicitly models source continuation with ordinary native calls. It does not attempt to resume arbitrary thrown C++/Swift stack frames.

## Model conditions and native failures

`Condition::onModel(label, callback)` / `Condition(label:modelTest:)` receive the actual Model, including the active memento when validating an editor. Existing Value callbacks retain their Value targets. Local condition labels may be nil. Native callbacks remain local callable state and are rejected by graph export, as before.

Existing portable predicate records may now be used on containers. For actual Model receivers, nil tests and isInteger use the target's identity/class protocol; other supported unary predicates dispatch through the existing selector read binding and one-argument predicates through `binaryMessage`. Negation and conjunction retain source short-circuiting. Results must be Boolean. Receiver-index-zero model conditions are supported; model arguments and multiargument model messages require explicit native bindings instead of being silently coerced into primitive Values. This does not add an expression language or serialize callbacks.

The default interpreter profile remains MAValidatorVisitor. Description-selected custom validator/reader/writer instances remain MAG-006. Native models representing collections/magnitudes/options through values must supply the existing explicit Value adapters; the validator does not invent storage or enumerate a generic Model.

## Nil signal text and printing

An explicit nil configured error message is emitted as nil `signalText`, preserving its presence and distinction from an absent setting. The supporting Pharo Exception>>messageText protocol returns an empty String when its stored text is nil. `messageText` and flat leaf `message` follow that verified behavior; they are not arbitrary fallback messages. A nil local condition label and a checked-memento conflict message follow the same rule.

A leaf prints its current description label plus ': ' if that label is non-nil, then its computed message text. An empty label still prints the separator. A nil label omits the prefix. A MAMultipleErrors prints its children separated by carriage returns and does not prepend its own label. Its original group signal text is retained independently from printing.

Mementos consume the same nested result. A checked conflict resets first and returns a direct MAConflictError tagged with the editor's description; it does not run ordinary validation or add a visit wrapper on that conflict path. Regular memento validation retains the normal container/field nesting. The flat compatibility methods preserve their previous leaf record shape, including String message fields.

## Bounds, ownership and interchange

Limits apply to description traversal, values, callbacks, error collection, projection and printing. Shared native issue/tag identities are retained; no tracing heap or VM exception mechanism is introduced. Validators, contexts, descriptions and their tags are synchronous mutable-model facilities. Swift ValidationFailure uses unchecked Sendable solely to satisfy Swift.Error's contract; it does not make its retained live description safe to access concurrently. Callers must keep model access within their synchronization context.

Description/value interchange is unchanged. Container conditions use the existing portable condition records. Live error objects, exception frames and native callbacks are not added as Value tags or serialized model state. Shared fixture reports are test projections of Magritte error class/tag/text/collection data, not a new schema language or public error codec.

## Evidence

The target is [magritte-metamodel/magritte d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model). `validation-protocol-upstream-methods.json` fingerprints 32 consulted Magritte methods, supporting [Pharo Exception](https://github.com/pharo-project/pharo/blob/81f614957ca93536d2483a0f64480456b0350451/src/Kernel/Exception.class.st) message/signal methods and the [Grease GRError hierarchy](https://github.com/SeasideSt/Grease/blob/fe9076b72ed63b4a39ad644d41db59c3ffbcf1bf/repository/Grease-Core.package/GRError.class/properties.json). Kernel/Grease evidence is distinguished from Magritte and from whole-image provenance.

`validation-protocol-scenarios.json` contains 24 independently authored source expectations covering nested wrappers, kind/required/undefined/condition order, registered families, relation/option continuation, reference errors, nil text/labels, container gates and nil targets. Both ports replay the cases, round-trip their graphs and replay each other's exports. Native tests check exact tag/issue ownership, model callback targets, child-read timing, native continuation, operational failures, limits and memento reset/conflict/regular paths.

All earlier 135 shared payloads are byte-unchanged; there are now 137. Two old native nil-message rejection assertions now check the emitted empty computed text. The historical portable-invalid container-condition row now imports and retains its conditions; its original fixture bytes remain available. These are explicit source-profile advances, not new live-GT equivalence claims. GT was not accessed.

On macOS arm64, all 30 CTest suites pass in debug and ASan/UBSan builds, and all 114 Swift tests pass. Cross-port replay passes 784 C++ protocol checks and equivalent Swift assertions; exported graphs and reports compare semantically. Both mirrors verify 137 payloads. An installed CMake 0.31 consumer and an independently linked Swift executable exercise the public result, exception, tag, nil-message and continuation APIs. ASan runs with `detect_leaks=0` because LeakSanitizer is unavailable on this host; native weak-reference tests verify tag release. GT was not used.
