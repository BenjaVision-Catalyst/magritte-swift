# Described-object printing (0.24)

Both ports implement `MADescription>>readToString:`, `MAElementDescription>>printFor:on:` and `MAContainer>>print:on:` for the existing native model/Value profile. Container printing reads described fields and supports the upstream local `maPrintString` and `maPrintStringSeparator` hooks. Ordinary MAStringWriter behavior is unchanged.

## Audit and evidence

The baseline remains [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), with remote HEAD reconfirmed on 2026-10-27. The audit found that both ports offered value/model string writers but lacked these distinct printing protocols. In particular, using the container string writer as a replacement would apply different visibility/nil rules and miss the property hooks.

`printing-upstream-methods.json` records sixteen source fingerprints covering reading, printing, writing, stored-property access and copy semantics. `printing-scenarios.json` contains 54 container cases (nil/non-nil positions, false/zero/empty values, default/custom/empty separators and field formatters) and five element cases. Both ports consume the same source-derived expected outputs and callback/read traces. Further native tests cover formatter replacement during reads, retained callback identity, one-time separator capture, reader/formatter/separator failures, explicit nil settings, copies, priority order, duplicate visits, output bounds and codec boundaries.

**GT was not accessed, as requested.** This phase provides upstream-source and standalone native evidence. Fresh live-image comparison/replay remain deferred, and prior GT fixture payloads are unchanged.

## APIs

| Upstream selector | C++ | Swift |
| --- | --- | --- |
| `readToString:` | `description.readToString(model, graph, limits)` | `try description.readToString(model, graph: graph, limits: limits)` |
| `printFor:on:` | `element.printFor(model, stream, graph)` | `try element.printFor(model, on: stream, graph: graph)` |
| `print:on:` | `container.print(model, stream, graph)` | `try container.print(model, on: stream, graph: graph)` |

`PrintStream` is the minimal bounded native bridge for the write stream passed by these protocols. Create it with optional Limits, append text, and inspect `contents` (C++: `contents()`). It is not a new Magritte class or a general Smalltalk stream implementation. Stream limits also supply the limits for field enumeration, Value checks and ordinary writer fallback during printing. `readToString` uses its own Limits parameter.

C++:

```cpp
using namespace magritte;
auto name = std::make_shared<Description>();
name->id = name->key = "name";
auto root = std::make_shared<Description>();
root->id = "person";
root->className = "MAContainer";
root->children = {name};
AdaptiveModel person;
person.description = root;
person.values["name"] = Value("Ada");
name->setPrintString(std::make_shared<PrintValueBlock>([](const Value& value) {
    return "[" + std::get<std::string>(value.data) + "]";
}));
PrintStream stream;
root->print(person, stream); // stream.contents() == "[Ada]"
```

Swift:

```swift
let name = Description(id: "name", key: "name")
let root = Description(id: "person", className: "MAContainer")
root.children = [name]
let person = AdaptiveModel(description: root, values: ["name": .string("Ada")])
try name.setPrintString(PrintValueBlock { value in
    guard case .string(let text) = value else { throw MagritteError("Expected String") }
    return "[" + text + "]"
})
let stream = PrintStream()
try root.print(person, on: stream) // stream.contents == "[Ada]"
```

## Printing semantics

`readToString` performs one raw read through the supplied model and passes the result to the description's ordinary string writer. It does not apply memento/default cooking. A nil result therefore renders the description's undefined text.

Element `printFor` also performs one raw read, but writes nothing for nil. For a non-nil value it uses the ordinary writer. It does not consult `maPrintString`, matching the separate upstream element method.

Container `print` visits its direct children in their existing native enumeration order. For each child it reads the model, skips nil, and otherwise invokes that child's `maPrintString` hook if present, or its ordinary string writer. False, zero and an empty string are present values. No validation, visibility/read-only filtering or automatic default substitution is applied by this printing loop. A fallback writer retains its own existing semantics. The container's own field-print hook is not used to format the entire container.

The default separator is one space. A separator runs between every child position, including positions whose field values are nil; three nil children therefore print two separators. It runs before the next field read, so a failed read can leave the preceding separator in the stream. Empty/singleton containers never invoke a separator. Priority containers use the established ascending-priority native view, with the existing tie/mutation projection; repeated child objects are printed repeatedly.

The separator setting is captured once before the loop. Replacing it during printing affects a later print operation. A field formatter is selected after that field's read, so a read callback can change the formatter used immediately. Executing callbacks are retained if they replace themselves. Callback/reader errors propagate without rollback: prior output and metadata side effects remain.

## Local hooks, storage and copies

`PrintValueBlock` accepts a zero-argument or one-Value native function returning String. Install it with `setPrintString`. `PrintSeparatorBlock` accepts a zero-argument function or a function taking the actual PrintStream; install it on a container with `setPrintSeparator`. This models the upstream culled optional arguments without an evaluator or arbitrary object-valued callable protocol.

C++ hooks use shared pointers; Swift hooks are reference objects. Copying descriptions shares hook identity with independent property dictionaries, following the shallow property-copy rule. The public `printStringBlock` and `printSeparatorBlock` slots expose local identity. Clear a setting with the typed setter and null/nil; clearing removes its stored presence.

`hasProperty` recognizes installed hooks under `maPrintString`/`maPrintStringSeparator`. Value lookup cannot return a callable object and fails explicitly, as for existing local display blocks. Internal nil placeholders represent local slot presence, not serialized blocks. A checked `propertyPut` replaces the local hook with the supplied data value. A stored nil remains present: it does not select the fallback and fails when an actual invocation is required. It can remain unused for a nil field or an empty/singleton container. A nil-removing operation that would need to return an installed block fails without removing it; use the typed clear operation instead. Existing no-announcer write boundaries still apply.

## Bounds, interchange and remaining scope

PrintStream checks cumulative UTF-8 output bytes and work (one unit per append plus output bytes) before appending. A failed append leaves that append unapplied; earlier text remains. C++ rejects invalid UTF-8. Appending the stream's current contents is supported. Byte limits measure output text, not a temporary JSON envelope. Existing item/depth/work limits check the field snapshot and local Values. Native callbacks are not preempted and callers synchronize mutable model/description/stream state.

As with the existing enumeration profile, structurally mutating the source container during printing is unsupported. The bounded native snapshot retains child identity; this is not a claim of full Smalltalk backing-collection mutation behavior. Arbitrary Smalltalk stream operations, arbitrary callable objects, Grease object printing and scalar domains outside the current writer profile remain separate gaps.

Printing hooks are local executable state. Import/export rejects both hook names in every graph version, including explicit nil, and rejects actual hooks on every node, including hidden nodes. Clearing hooks explicitly permits an ordinary graph snapshot. No graph version, Value tag, semantic wire property, annotated self-description field, runtime class registry entry or application dependency is added. Supported descriptions/objects remain usable for printing after a normal graph round trip; closures are not serialized.

## Executed standalone checks

On macOS arm64, all 23 CTest targets and 90 Swift tests pass. The focused C++ printing target passes 168 checks in ordinary and AddressSanitizer/UndefinedBehaviorSanitizer builds (leak detection disabled). An independently installed CMake 0.24 consumer runs, and an independent Swift consumer type-checks. All 122 shared fixture checksums verify; the previous 120 payloads remain unchanged. Both ports export equivalent ordinary graphs, reimport them and print `A B C`.

```sh
# In magritte-cpp:
build/magritte-printing-tests /tmp/printing-cpp.json
# In magritte-swift:
MAGRITTE_PRINTING_EXPORT=/tmp/printing-swift.json swift test --filter PrintingTests
# In magritte-cpp:
python3 tools/compare-graphs.py /tmp/printing-cpp.json /tmp/printing-swift.json
```

All checks use standalone code and saved fixtures, with no GT connection.
