# Semantic baseline and phased implementation

This is the first core/interchange increment, not a complete Magritte port.

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
| Nested containers, union/intersection/copy protocol | N | nested imports explicitly rejected |
| MAStringDescription | I, R | required empty string remains valid; exact UTF-8 content; no normalization |
| MABooleanDescription | I, R | false is present; integer zero is not Boolean |
| MANumberDescription | I, R (integer subset) | inclusive bounds; exact signed 64-bit values |
| Fractions, arbitrary precision integers, decimal/float, number formats | N | rejected rather than rounded; MANumberDescription is only partially implemented |
| Date/time/duration, symbol, memo/password/token/URL, class/color/icon/file/directory/block/action/table descriptions | N | unsupported class fails import; see complete inventory |
| Required/optional, custom undefinedValue | I, R | required checks nil; undefined sentinel skips kind/specific/conditions |
| Explicit defaults | I, R (property only) | raw read returns nil; defaultValue exposes declared default |
| Lazy defaults/shouldCacheDefault, default copying | N | no automatic substitution or cache |
| Read-only/hidden validation skip | I, R | flags affect interpreter, raw write still writes |
| MADictionaryAccessor | I, R | native dictionary missing read returns nil |
| MAPropertyAccessor semantics for common description properties | I, R (label/required) | Description implements Model; bootstrap describes seven common properties |
| Local pluggable native accessors | I, X | C++ callbacks / Swift closures; native tests; export fails |
| Selector/variable/identity/null/chain/composite/delegator strategies | N | no fictional cross-language selector execution |
| Native local scalar conditions | I, X | executed natively; kind errors skip conditions; nil sentinel skips them |
| MACondition selector/receiver, conjunction and negation objects | N | some have portable meanings, but are not encoded yet |
| Structured validation errors | I, R (leaf codes) | description identity, code, message; native validator accumulates leaf errors |
| Upstream nested exception trees/custom error text/validator overrides | N | unknown semantic properties fail import |
| Label/comment/group/priority/required/readOnly/visible/undefined metadata | I, R (selected properties) | retained, interpreted where stated |
| General property dictionary | I (bounded subset) | unknown semantics rejected; metadata: prefix preserves explicitly opaque consumer metadata |
| Reference identity between description nodes | I | shared child instances survive import/export |
| Relationship object identity, cycles, to-one/to-many, options | N | reference values/classes rejected, not flattened |
| Ordered value arrays | I (interchange only) | exact recursive arrays; no relation/collection description validation yet |
| Visitor traversal | I (generic callback) | bounded traversal; full upstream dispatch hierarchy N |
| Description/value JSON import/export | I, R (Person) | GT -> both ports -> GT; native fixed-point round trips |
| MAStringReader/Writer text conversion and other readers/writers | N | graph codec does not claim their semantics |
| Self-description | I, R (bootstrap subset) | label/comment/group/required/readOnly/visible/priority; self-edit affects validation |
| Complete self-description, recursive bootstrap of all descriptions/accessors | N | no completeness claim |
| Straight/cached/checked mementos, conflicts/merging | N | reference records cached default only; no native memento API |
| Native user interfaces, persistence interpreters | N | headless consumers may be added separately |
| GemStone/platform adapters | N | deferred |

## Deliberate differences and decisions

1. Descriptions have stable external IDs. Adaptive values are keyed by those IDs, so an application may explicitly adopt a replacement description graph without schema-specific mapping. Upstream keys values by description objects using Smalltalk equality. Reusing an ID asserts semantic continuity; changing an ID creates a distinct field. Adoption is explicit (`model.description = newRoot`), not an implicit migration. Removed values stay in the local model until the application handles them; export rejects undescribed values.
2. This profile accepts nonempty printable ASCII identities, accessor keys and property names. Text values support arbitrary valid UTF-8 including NUL and supplementary characters. No Unicode normalization occurs. C++ and Swift use exact string-content equality for Values.
3. When label is absent the ports return the accessor key as-is. Upstream infers a human-readable camel-case label. Use explicit labels for equivalent presentation today.
4. Native validation returns a flat collection of structured leaf errors with English generic messages. Upstream may signal nested resumable exceptions. Codes/description identities, not localized messages or nesting, are the tested contract.
5. The bootstrap's seven common properties are represented by ordinary descriptions and can be read/written/validated by the same Model/validator APIs. It is a seed for full self-description, not a separately maintained schema language.
6. Native scalar condition and accessor functions and explicit default functions are local behavior. Export rejects every such function, including on hidden nodes. No closure, VM, RPC or expression-language evaluation is introduced. `defaultFunction` is explicitly evaluated by defaultValue; neither raw reads nor validation evaluates it implicitly. Container-local conditions are currently rejected by model validation.
7. A finite allowlist of description classes, accessor forms and semantic properties is intentional for this increment. Extending that list requires implementing and testing the semantics. Opaque `metadata:` properties cannot introduce executable behavior.

## Phases and exit criteria

1. **Current increment:** audit and provenance, independent native libraries, scalar/adaptive/accessor core, bootstrap, bounded description/value interchange, shared GT-established Person fixture, runtime evolution, and explicit rejection tests. Install/package and test locally; publish precise gaps.
2. **References and collections:** implement relationship/reference/options hierarchy, identity tables, cyclic object graphs, collection ordering/uniqueness/kind/required rules, nested containers, aliasing and traversal budgets; verify against upstream tests and GT.
3. **Behavior and scalar completeness:** portable forms of existing MACondition objects (e.g. isInteger selector and conjunction/negation), broader access strategies, exact numeric domains, remaining scalar descriptions, and MAStringReader/Writer behavior. Unsupported arbitrary closures must continue to fail export.
4. **Editing and meta-model completeness:** straight/cached/checked mementos, original/cache/default rules, conflict behavior, composition/copy semantics, full self-description and bootstrap round trips. Only then assess a complete headless-core claim against the inventory.
5. **Optional interpreters:** native inspectors/presentation tools in separate targets. No networking, deployment or application-specific integration enters these core libraries.

Each phase needs independently reviewed GT results and shared fixtures, not merely agreement between the two ports. Tests in this increment are newly written behavioral tests; upstream test source was not copied.
