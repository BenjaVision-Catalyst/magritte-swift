# Semantic baseline and phased implementation

The scalar, relationship/collection, portable behavior, editing, recursive metadata, composition and class/accessor reflection phases are implemented for the documented profiles. This is still not a complete Magritte port; see [relationship evidence](relationships.md) and [portable behavior evidence and boundaries](portable-behavior.md) and [editing/self-description evidence](editing.md) and [recursive composition evidence](composition.md) and [class/accessor reflection evidence](reflection.md).

The authoritative upstream is [magritte-metamodel/magritte](https://github.com/magritte-metamodel/magritte), revision **d67f318686b7779aed79416db121e257d1191f2e** (2025-04-29). Paths below resolve against that commit. The target is its headless Magritte model, not an application-specific schema system. The graph representation serializes instances of that description hierarchy; there is no second field-schema model.

## Reading and provenance

Reviewed the upstream README, FEATURES, baseline package, model hierarchy and its tests. `upstream-inventory.json` records every class and selector in `source/Magritte-Model` at the pinned revision; this inventory is a source audit, not a coverage claim. Focused semantic references:

| Area | Upstream source and tests inspected |
| --- | --- |
| Properties, required, undefined, read-only, visibility, self-description | MADescription, MAElementDescription, MATPropertyOwner; MADescriptionTest, MAElementDescriptionTest |
| Composition and ordering | MAContainer, MAPriorityContainer; MAContainerTest, MAPriorityContainerTest |
| Scalar kinds and range | MAStringDescription, MABooleanDescription, MANumberDescription, MAMagnitudeDescription; corresponding description tests |
| Native access | MAAccessor, MADictionaryAccessor, MAPropertyAccessor, MASelectorAccessor; accessor tests |
| Adaptive objects | MAAdaptiveModel and MAAdaptiveModelTest |
| Validation | MAValidatorVisitor, MAValidationError and subclasses; required/kind/condition/range tests in description tests |
| Conditions | MACondition, MAPluggableCondition, MAConjunctiveCondition, MANegationCondition |
| References and options | MAReferenceDescription, MARelationDescription, MAToOneRelationDescription, MAToManyRelationDescription, MAOptionDescription and single/multiple subclasses |
| Interpreters | MAVisitor, MAReader, MAWriter, MAStringReader, MAStringWriter |
| Editing | MAMemento, MAStraightMemento, MACachedMemento, MACheckedMemento; MAMementoTest |

Original publications consulted:

- Lukas Renggli, [Magritte – Meta-Described Web Application Development](https://scg.unibe.ch/assets/archive/masters/Reng06a.pdf), 2006, chapter 2, especially sections 2.2–2.4 and the accessor/condition/memento class reference. The original README's older host was unavailable; this is the university archive copy.
- Lukas Renggli, Stéphane Ducasse, Adrian Kuhn, [Magritte – A Meta-Driven Approach to Empower Developers and End Users](https://scg.unibe.ch/archive/papers/Reng07aMagritte.pdf), 2007, sections 2–4. Runtime metamodel editing, adaptive objects, shared descriptions, and generic interpreters motivate this architecture. Publications establish design intent; the pinned source establishes current behavior when historical examples differ.

The running GT image was inspected only through GT MCP. The relevant installed classes are in Magritte-Model, but package membership alone does not establish upstream provenance. `conformance/live-methods.json` identifies the exact inspected live methods by source hash. No installed Magritte Git revision was exposed by the image's IceRepository registry. In particular, the installed MAValidatorVisitor uses `sameContentAs:` for undefined checks, where pinned upstream uses `=`; aggregate error handling is arranged differently. This increment checks the shared scalar behavior and flattened leaf error classes, not equivalence of either entire implementation. Extension selectors seen in the image, including serialization and UI stencils, are excluded.

## Support matrix (both ports)

I = implemented; R = executed against the live reference for the stated subset; N = not yet implemented; X = not portable through this interchange profile. Native-only tests are distinct from R.

| Feature | State | Evidence / boundary |
| --- | --- | --- |
| MAContainer insertion order | I, R | reference containerOrder; graph child identities preserved |
| MAPriorityContainer ascending order | I, R | reference priorityOrder; ties stable in ports, upstream tie policy not claimed |
| Container add/remove | I | mutate children; no complete Smalltalk collection protocol |
| Nested containers | I, R | identity access for native models; stored child values for adaptive models |
| Concatenation/union/intersection/select/collect/copy protocol | I, R (profile) | equality-class composition, selective reference copies and shared container children; range/exclusion/empty copies; full collection protocol N |
| MAStringDescription | I, R | required empty string remains valid; exact UTF-8 content; no normalization |
| MABooleanDescription | I, R | false is present; fixed options, aliases and configurable true/false text |
| MANumberDescription | I, R (Int64/binary64) | inclusive bounds; finite floats; documented exact mixed-order policy |
| Fractions, arbitrary precision integers, scaled decimals, full NumberParser grammar | N | explicit rejection; MANumberDescription remains partial |
| Symbol, Memo, Password and Token descriptions | I, R | graph/3 scalar kinds, masking and token text conversion |
| Date/time/duration, URL, color/icon/file/directory/block/action/table descriptions | N | unsupported class fails import; see complete inventory |
| Required/optional, custom undefinedValue | I, R | required checks nil; undefined sentinel skips kind/specific/conditions |
| Explicit defaults | I, R (property only) | raw read returns nil; defaultValue exposes declared default |
| shouldCacheDefault | I, R | editing default filtering, including pinned/live difference; see editing.md |
| Memento default substitution/cache | I, R | straight nil/default and cached sentinel/default cooking; raw models unchanged |
| General lazy initialization/default copying | N | mutable collection identity and full copy protocol unsupported |
| Read-only/hidden validation skip | I, R | flags affect interpreter, raw write still writes |
| MADictionaryAccessor | I, R | native dictionary missing read returns nil |
| Description property/selector accessors | I, R (selected fields) | retained seven-property bootstrap plus class-specific selector metadata graphs |
| Local pluggable native accessors | I, X | C++ callbacks / Swift closures; native tests; export fails |
| Selector/variable/identity/null/chain strategies | I, R (profile) | graph/3 strategies and explicit host bindings; delegator added in graph/4; other composite protocols N |
| Native local scalar conditions | I, X | executed natively; kind errors skip conditions; nil sentinel skips them |
| MACondition selector/receiver, conjunction and negation objects | I, R (finite protocol) | labelled bounded graph/3 data; arbitrary messages/blocks and container conditions X |
| Structured validation errors | I, R (leaf codes) | description identity, code, message; native validator accumulates leaf errors |
| Upstream nested exception trees/custom error text/validator overrides | N | unknown semantic properties fail import |
| Common and relation/option metadata | I, R (selected properties) | ordered/distinct/definitive/sorted/extensible retained; no invented coercion/uniqueness rules |
| General property dictionary | I (bounded subset) | unknown semantics rejected; metadata: prefix preserves explicitly opaque consumer metadata |
| Reference identity between description nodes | I | shared child instances survive import/export |
| Relationship object identity, cycles, to-one/to-many/scalar-to-many | I, R | graph/2 explicit references and class constraints; no automatic validation cascade |
| Static single/multiple options | I, R | membership/extensibility/prepared lists/identity-safe labels |
| Dynamic options, grouping, arbitrary renderers/classes | N, X (current wire) | explicit failures; local native class bindings supported separately |
| Mutable collection-object identity | N, X (current wire) | inline collections are value snapshots; object references retain identity |
| Array/OrderedCollection/Set/Bag values | I, R | kind/order/multiplicity/equality and relation/option validation; Character bridge for String collections |
| Visitor traversal | I (generic graph callback) | bounded composition/reference traversal, cycles terminate; full upstream dispatch hierarchy N |
| Description/value JSON import/export | I, R | graph/1–4; GT -> both ports -> GT, aliases/cycles/nested objects/collections |
| MAStringReader/Writer text conversion | I, R (profile) | scalars/options/tokens; writers also containers/relations; other interpreters N |
| Self-description | I, R (selected class-specific profile) | fifteen supported classes in reflective profile; staged metadata edits govern subsequent model validation |
| Recursive description self-description | I, R (selected profile) | lazy bounded sessions; children/reference/name/optionsTextual; three metadata levels and imported-schema edits |
| MAClassDescription and class-valued metadata | I, R (finite registry) | 61 classes; interpreter options limited to implemented choices; graph/4 |
| Accessor/condition self-description | I, R (selected profile) | eight accessor classes; three conditions have no annotated fields; actual local accessor identity and memento edits |
| Complete hierarchy/memento self-description and arbitrary reflection | N | supported annotation selections remain explicit; no class discovery or arbitrary message execution |
| Straight/cached/checked mementos, conflicts/merging | I, R (direct field profile) | 48 scenarios/201 snapshots; raw commit, destructive conflict reset, checked selective push; collection alias gap in editing.md |
| Native user interfaces, persistence interpreters | N | headless consumers may be added separately |
| GemStone/platform adapters | N | deferred |

## Deliberate differences and decisions

1. Descriptions have stable external IDs. Adaptive values are keyed by those IDs, so an application may explicitly adopt a replacement description graph without schema-specific mapping. Upstream keys values by description objects using Smalltalk equality. Reusing an ID asserts semantic continuity; changing an ID creates a distinct field. Adoption is explicit (`model.description = newRoot`), not an implicit migration. Removed values stay in the local model until the application handles them; export rejects undescribed values.
2. This profile accepts nonempty printable ASCII identities, accessor keys and property names. Text values support arbitrary valid UTF-8 including NUL and supplementary characters. No Unicode normalization occurs. C++ and Swift use exact string-content equality for Values.
3. When label is absent the ports return the accessor key as-is. Upstream infers a human-readable camel-case label. Use explicit labels for equivalent presentation today.
4. Native validation returns a flat collection of structured leaf errors with English generic messages. Upstream may signal nested resumable exceptions. Codes/description identities, not localized messages or nesting, are the tested contract.
5. The bootstrap's seven common properties are represented by ordinary descriptions and can be read/written/validated by the same Model/validator APIs. It is a seed for full self-description, not a separately maintained schema language.
6. Native scalar condition and accessor functions and explicit default functions are local behavior. Export rejects every such function, including on hidden nodes. No closure, VM, RPC or expression-language evaluation is introduced. `defaultFunction` is explicitly evaluated by defaultValue and by memento default/filter operations; raw models and their ordinary validation do not evaluate it implicitly. Container-local conditions are currently rejected by model validation.
7. Graph/2 adds the audited relationship/option hierarchy; identity is independent of a description’s label or shape. Imported class names refer to real supported native equivalents, not schema IDs. See relationships.md for phase evidence and interchange.md for remaining boundaries.

8. A finite allowlist of description classes, accessor forms and semantic properties is intentional for this increment. Extending that list requires implementing and testing the semantics. Opaque `metadata:` properties cannot introduce executable behavior.

## Phases and exit criteria

1. **First slice (delivered):** audit and provenance, independent native libraries, scalar/adaptive/accessor core, bootstrap, bounded description/value interchange, shared GT-established Person fixture, runtime evolution, and explicit rejection tests. Install/package and test locally; publish precise gaps.
2. **References and collections (delivered for the documented profile):** explicit reference graphs, static relationship/options hierarchy, object IDs/cycles, collection kind/equality/required rules, nested containers and bounded operations are implemented and checked against upstream source and GT. Remaining dynamic/reflective and collection-identity facilities are explicitly tracked in relationships.md, not claimed complete.
3. **Portable behavior (delivered for the documented profile):** finite MACondition objects, broader access strategies, Symbol/Memo/Password/Token descriptions, finite binary64 and MAStringReader/Writer operations. Full numeric/scalar domains remain future work; arbitrary executable behavior continues to fail export.
4. **Editing (delivered for the documented profile), meta-model completeness (pending):** straight/cached/checked mementos, original/cache/default rules, conflict behavior and selected class-specific metadata editing are implemented and checked against GT/upstream. Selected recursive description metadata and composition/copy semantics are delivered in 0.5. The 0.6 class/accessor reflection profile is delivered; full mutable collection identity, arbitrary reflection and memento metadata remain future work. Only then assess a complete headless-core claim against the inventory.
5. **Optional interpreters:** native inspectors/presentation tools in separate targets. No networking, deployment or application-specific integration enters these core libraries.

Each phase needs independently reviewed GT results and shared fixtures, not merely agreement between the two ports. Tests in this increment are newly written behavioral tests; upstream test source was not copied.

Phase 0.3 adds Symbol, Memo, Password and Token descriptions and finite binary64, with text conversion and portable condition/accessor forms checked against live GT. Arbitrary integers/rationals/scaled decimals and date/time/color/URL/file descriptions remain N (Class is added in 0.6). Read portable-behavior.md for the two explicit GT/pinned-source or VM-dependent numeric policies; no complete scalar-domain claim is made.

Phase 0.4 adds the bounded editing and class-specific self-description profiles. The eight shouldWrite matrix differences from installed GT intentionally follow the pinned upstream symmetric rule; mutable collection alias behavior remains unsupported. editing.md records both boundaries and the live evidence.

Phase 0.5 implements recursive description metadata sessions and selective composition/copy semantics for the current hierarchy. composition.md records the live GT evidence, supported annotation selection and explicit label/class-list/SortedCollection projections. This is not a complete reflective metamodel or graph deep-clone claim.

Phase 0.6 implements MAClassDescription, finite class values and class-valued relation/interpreter metadata, plus live accessor-object editing and faithful condition self-description. reflection.md records the 26 source matches, GT schema/getter/editing evidence, graph/4 round trips and explicit identity/registry limits.
