# Editing and self-description (0.4)

This phase implements a bounded headless editing profile of MAStraightMemento, MACachedMemento and MACheckedMemento, plus class-specific metadata descriptions for all fourteen supported concrete description classes. It is not complete Magritte self-description or a UI framework. The semantic baseline remains upstream d67f318686b7779aed79416db121e257d1191f2e. The upstream memento classes, MAElementDescription and their tests were inspected; native tests and reference harnesses were independently written.

## Editing semantics

All mementos implement Model, so ordinary descriptions, validation and text writers can consume staged values. Construct one with an existing model, its MAContainer/MAPriorityContainer and an optional Graph resolver. C++ borrows both model and resolver, which must outlive the memento; it retains the container and cached field descriptions. Swift retains the model and descriptions, and holds the graph weakly; keep the graph alive when resolving references. Mutable operations require caller synchronization.

| Adapter | Read/write | Reset and commit |
| --- | --- | --- |
| StraightMemento | Reads the underlying model, substituting the description default only for raw nil. Writes immediately through shouldWrite. | Both are no-ops. |
| CachedMemento | Pulls direct fields on construction/reset. Raw values equal to undefinedValue are replaced by their defaults in the cache. Writes stage raw values; they do not validate or enforce UI flags. | Reset discards edits and pulls again. Commit pushes eligible cached values, then resets. |
| CheckedMemento | Also pulls an independent raw original map on reset, after populating the cooked cache. | Commit pushes only values changed from original that also differ from the current model; untouched externally changed fields are preserved. Successful commit resets. |

`hasChanges` compares the cache with fresh raw model values through each field's shouldWrite. Checked `hasModelChangedElsewhere` compares original with fresh raw values the same way. `hasConflict` is the conjunction of these two predicates over the whole editor, not a per-field overlap test. Even disjoint external and staged changes can conflict. On conflict, checked `validate` **resets first**, discarding pending edits, then returns an MAConflictError leaf. Otherwise it runs the normal validator over staged values. External-only changes can also cause a conflict because the old cache differs from the new raw model.

Commit does not call validate or check conflicts. Calling checked commit directly can overwrite an externally modified field when the local value differs from original and current. Invalid values can be committed. Hidden/read-only fields are skipped when pushing; read-only staged edits can still be read. Commits are not transactions: an accessor failure propagates, earlier writes remain applied, and the pending cache is not automatically reset. Portable commit order follows the container's ordered children (including priority order); upstream dictionary enumeration does not promise the same callback order.

`Description.shouldWrite(candidate, previous)` skips hidden/read-only fields, equal values, and pairs of ignorable values. Ignorable values are nil, undefinedValue, and a value equal to default when shouldCacheDefault is false. To-many relations default shouldCacheDefault to true. This is symmetric in pinned upstream: writing nil over a stored default can be ignored. The installed GT image has an older asymmetric implementation: eight of 486 recorded cases differ. Both `live` and pinned `result` are retained in editing-reference.json; native expectations deliberately use pinned upstream. editing-live-methods.json records 52 inspected methods, with this one source difference and the missing live isIgnorableValue: helper.

Local default functions remain explicit host behavior and cannot be exported. Straight evaluates one on each nil read; cached/checked evaluate cooked defaults on reset, and checked separately reads raw originals without recooking them. Raw model access and ordinary validation still do not apply defaults. General upstream lazy initialization/default copying is not implemented.

## Runtime shape and collection boundaries

Editing is limited to direct noncontainer fields with unique nonempty IDs. Nested owning container fields fail explicitly; edit referenced objects with their own mementos. Cached reads require the identical retained description object. A newly added field requires reset or an explicit cache write before reading. Checked commit of a newly staged field without an original requires reset. Replacing a descriptor object under an existing ID requires reset. Removing a child hides it from dirty comparisons, but the retained cached field may still be pushed on commit before reset drops it, matching upstream. Applications must handle detached stored values before graph export. Foreign descriptions cannot be inserted into a cache without first adding them to the container; the native API is intentionally stricter than an arbitrary Smalltalk dictionary.

Collections remain inline Value snapshots. Replacing a collection value is covered against GT. Shared mutable collection identity is not supported: live cached values can alias a model's OrderedCollection while checked originals are shallow copies. In-place mutation can therefore yield hasChanges=false and hasModelChangedElsewhere=true in GT. editing-boundaries-reference.json records that unsupported alias case; it is not an equivalence assertion for native snapshots. Object-table reference identity remains supported, including aliases/cycles and changes inside referenced objects that do not alter the reference itself. Deep copy/full copy protocols and rollback transactions remain future work.

Limits apply to field traversal, configuration, values, aggregate cache writes, comparisons and commit work; violations throw without silently truncating state. Runtime callbacks can fail or mutate state, so callers should avoid reentrant editing and coordinate changes themselves.

## Expanded metadata descriptions

The existing `descriptionModel()` seven-property bootstrap is retained. New `descriptionModelFor(target)` returns a Graph owning an ordinary MAContainer and upstream MASelectorAccessor descriptions. Keep that graph alive because auxiliary reference edges are weak. The factory includes:

| Classes | Described properties |
| --- | --- |
| All supported classes | type (read-only), label, comment, group, priority (required), readOnly, visible, undefined, undefinedValue; required except Boolean, whose upstream override returns nil |
| Element classes except options | default, described using the target's concrete description class |
| Number | min, max |
| Boolean | trueString, falseString |
| Memo | lineCount, constrained to integer >= 1 |
| Token | separators |
| Options | sorted, extensible |
| To-many relations | ordered, definitive, sorted |
| Multiple options | distinct, ordered |

These graphs match the selected upstream metadata methods, including defaults, ordering, labels, reference descriptions and constraints. Getter/setter execution uses a finite set of description selectors; no reflective message evaluator is added. Derived type has no raw setter; its read-only description causes staged edits to be ignored on commit. A constant default setter replaces any local default function. Container default getters return undefinedValue, as upstream MADescription does. An absent label uses the accessor name as-is; Smalltalk's camel-case inflection remains outside the profile.

Structural children/reference/classes/options/accessor/condition editing, the name/display/reader/writer/validator descriptions, complete recursive bootstrap and metadata descriptions of accessors/conditions/mementos remain unimplemented. shouldCacheDefault is accessible as an explicit supported selector but has no invented annotation field. Do not interpret this selected factory as the entire upstream magritteDescription.

C++ example (graph owns the editor's field descriptions):

```cpp
magritte::CheckedMemento editor(model, container, &graph);
editor.writeUsing(*field, magritte::Value("Edited"));
if (editor.validate().empty()) editor.commit();
auto metadata = magritte::descriptionModelFor(*field);
magritte::CheckedMemento metaEditor(*field, metadata.descriptions.at(metadata.root), &metadata);
metaEditor.writeUsing(*metadata.descriptions.at(metadata.root + ".required"), magritte::Value(true));
if (metaEditor.validate().empty()) metaEditor.commit();
```

Swift uses the same objects independently:

```swift
let editor = try CheckedMemento(model: model, description: container, graph: graph)
try editor.write(.string("Edited"), using: field)
if try editor.validate().isEmpty { try editor.commit() }
let metadata = try descriptionModelFor(field)
let metaEditor = try CheckedMemento(model: field, description: metadata.descriptions[metadata.root]!, graph: metadata)
try metaEditor.write(.boolean(true), using: metadata.descriptions[metadata.root + ".required"]!)
if try metaEditor.validate().isEmpty { try metaEditor.commit() }
```

Editing sessions, caches and originals are local interpreter state and are not serialized. Metadata descriptions themselves use existing graph/3 selector and reference records. Committed portable descriptions/model values export through the ordinary codec; no graph version or tags were added.

## Executed evidence

editing-reference.json records 48 live GT scenarios with 201 snapshots, covering all three mementos, validation/reset/commit, defaults/sentinels, flags, conflicts and convergence, references, collection replacement, and added/removed fields. Its separate 486-case write matrix preserves the eight pinned/live differences. self-description-reference.json checks all fourteen supported classes, complete selected metadata graphs, initial/staged/final reads, validation and actual metadata commits. Changing Number minimum through its self-description changes validation of a subsequent value.

Both native tests also edit a Number description and then its active model through checked mementos: minimum becomes 7, old score 2 fails, score 8 passes and commits. GT reconstructs each native graph (13 descriptions, two cyclic/aliased objects), asserts the edited constraint and values, validates the model and reexports equivalent graphs. editing-roundtrip-reference.json records that result. Replay requests are retained next to the reference JSON. Native-only tests check callback/default evaluation counts, identity restrictions, bounds and partial commit failures; Swift also checks model retention. These are distinct from live-GT evidence. Debug CTest, C++ ASan/UBSan, Swift package tests and an external CMake install consumer are exercised on macOS arm64. LeakSanitizer is unavailable in this macOS runtime; sanitizer tests run with detect_leaks=0.

Generate round-trip inputs with `magritte-editing-tests /private/tmp/magritte-cpp-editing-native.json` and `MAGRITTE_EDITING_EXPORT=/private/tmp/magritte-swift-editing-native.json swift test`. Run replay requests through GT MCP under the lease/marker workflow in conformance.md. Pure reference runs allocate no native Runtime resources and leave persistent Smalltalk source untouched.
