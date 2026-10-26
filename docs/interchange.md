# Magritte description and value interchange

The libraries decode the original scalar `magritte.graph/1` profile and the relationship/collection `magritte.graph/2` profile, plus graph/3 portable behavior additions. Export preserves the decoded format. New Graph instances default to graph/3. Graph/3 extends graph/2 as described below. Graph/1 continues to reject reference descriptions, nested containers, new semantic properties and reference/typed-collection/character values, rather than silently changing the meaning of an existing format. Standalone value codecs support all the tags below; resolving a reference requires a graph.

## Description bootstrap

The supported concrete descriptions are MAContainer, MAPriorityContainer, MAStringDescription, MASymbolDescription, MAMemoDescription, MAPasswordDescription, MATokenDescription (the latter four require graph/3), MABooleanDescription, the Int64/binary64 subset of MANumberDescription (binary64 in graph/3), MAToOneRelationDescription, MAToManyRelationDescription, MAToManyScalarRelationDescription, MASingleOptionDescription and MAMultipleOptionDescription. Their shared properties, reference links, allowed classes, options and labels belong to Magritte's description objects. No separate field-schema model is introduced. Description itself implements Model; the seven-property self-description bootstrap remains partial.

The envelope has exactly `format`, `root`, `descriptions`, `objects`. Tables use unique nonempty printable non-space ASCII IDs; dictionary accessor keys and property names have the same restriction. `root` identifies a container. Every node has `id`, `class`, `properties`. Containers also have `children` (ordered description IDs); other nodes have `accessor` (graph/1 and graph/2 require exactly `class: MADictionaryAccessor`, `key: <key>`).

Graph/2 relationship nodes additionally have `reference` (a description ID) and `classes` (unique class names). Option nodes instead have `reference`, `options` (tagged values in stored order), and `labels` (entries with exactly `value` and string `label`). Empty classes/options/labels must be explicit arrays. Materialize and register the reference description before exporting; implicit reference creation and reflective class/template discovery are not implemented. Abstract MAReferenceDescription/MARelationDescription/MAOptionDescription are shared concepts, not invented concrete wire types.

Description nodes are owned by the graph and container children. Reference edges are non-owning (weak_ptr/weak), so recursive descriptions do not create ownership cycles. Each imported ID resolves to one description instance. A container may be shared or nested. Cycles through references are allowed; cycles made solely of owning child edges are rejected **before** ownership links are installed. Duplicate child IDs remain unsupported. A reference whose owner has disappeared fails explicitly.

## Object identity, class constraints and access

An object has exactly `id`, `description` (a container ID), and `values` (a dictionary keyed by that container's **direct child description IDs**). A nested container can therefore have a stored object reference of its own. Adaptive models read that stored value; an absent nested value reads nil and its optional subtree is skipped. It is incorrect to flatten leaf fields into the outer adaptive object's map. For native/dictionary models, the validator applies a nested container's default identity accessor to the current model. Identity Value reads require graph registration and return the same target reference; identity writes fail. The container validator can apply identity directly to the current model.

Absent values remain absent; explicit nil remains present. Neither raw reads nor validation substitutes defaults. Structurally valid but invalid described values can be imported for editing. Unknown fields and structurally invalid descriptions fail import. New descriptions can be explicitly adopted by replacing an adaptive object's description reference; stable field IDs retain their values, and validation interprets the new shape without recompilation. Removed values require explicit handling before export.

A `reference` tagged value resolves through the object table, preserving shared targets and cycles. IDs are scoped to one Graph. Portable objects are genuine MAAdaptiveModel equivalents: their class ancestry is MAAdaptiveModel, MABasicObject, Object. A Person description does **not** pretend to be a native Person class. Supported class constraints are Object, MABasicObject, MAAdaptiveModel, UndefinedObject, String, Boolean, Number, Integer, Character, Collection, SequenceableCollection, Array, OrderedCollection, Set and Bag. Unknown classes fail interchange. Integer represents the supported numeric domain, not every Smalltalk integer representation class.

For local native relationships, Graph.nativeObjects retains Model adapters under IDs. NativeModel accepts explicit native class ancestry (caller responsibility); Graph.resolve returns the actual retained adapter/portable model. Swift retains its native reference object. C++ NativeModel borrows its object pointer, which must outlive every adapter access. Any native object binding or executable callback makes graph export fail; no handwritten schema mapping or fictional portable class identity is inferred.

## Tagged values

| Value | Wire form | Meaning |
| --- | --- | --- |
| nil | `{"type":"nil"}` | monostate / Value.undefined |
| Boolean | `{"type":"boolean","value":false}` | distinct from integer zero |
| String | `{"type":"string","value":"Ada"}` | exact UTF-8 content, no normalization |
| Integer | `{"type":"integer","value":"9007199254740993"}` | exact Int64, canonical base-10 string |
| Character | `{"type":"character","value":"é"}` | exactly one Unicode scalar, not a grapheme cluster |
| Object reference | `{"type":"reference","value":"bob"}` | graph object identity, never a struct copy |
| Array | `{"type":"array","value":[...]}` | ordered, repeats retained |
| OrderedCollection | `{"type":"ordered","value":[...]}` | ordered, repeats retained; distinct from Array |
| Set | `{"type":"set","value":[...]}` | enumeration retained, equality unordered, duplicates rejected |
| Bag | `{"type":"bag","value":[...]}` | enumeration retained, equality unordered, multiplicity retained |

Integers range from -9223372036854775808 through 9223372036854775807. Plus signs, leading zeros, negative zero, exponent/fraction forms and JSON-number encodings are rejected. Larger integers, fractions, scaled decimals, dates, maps and executable values remain unsupported; graph/3 adds Float and Symbol below. Collection kinds are not interchangeable: upstream Array and OrderedCollection equality differs. Set/Bag comparisons use exact recursive value content and reference IDs, with no Unicode normalization. Strings are Smalltalk Collections for multiple-value validation: iteration produces Characters, and an empty required multiple String is empty just as an Array is.

Collections are **value snapshots** in this profile. Object identity/aliasing is preserved for object-table references; shared mutable collection identity, collection self-cycles and mutable String identity are not encoded. The GT round-trip exporter detects repeated/cyclic collection instances and refuses them rather than silently flattening aliases. A consumer needing collection-object identity must wait for a corresponding object-table extension; an inline collection cannot claim such identity.

## Validation, options and presentation

Common properties: required/readOnly/visible (Boolean), priority (integer), label/comment/group/undefined (string or nil), min/max (integer or nil, number descriptions), default/undefinedValue (any supported value), and shouldCacheDefault (Boolean). Relationship/option properties additionally include ordered, distinct, definitive, sorted, extensible where those properties apply. shouldCacheDefault defaults true for to-many relations, false elsewhere; editing mementos interpret this property as documented in editing.md; general lazy initialization remains unsupported. Unknown semantic properties fail. Explicitly opaque `metadata:` properties round-trip without executable interpretation.

Required checks nil; multiple descriptions also reject empty Collections. Values equal to undefinedValue skip kind/specific/condition validation after required checks. Hidden/read-only descriptions skip validation. Raw writes do not validate or enforce presentation flags. Numeric min/max are inclusive. Local native conditions/default/accessor functions remain local, and exporting any such function fails even on unused/hidden nodes.

Relations check the allowed **classes** of the target/elements. They do not automatically run the referenced description's validation. MAToManyScalarRelationDescription uses the same class validation rules as MAToManyRelationDescription, matching its upstream implementation. To validate a referenced object explicitly, resolve it and validate it using the appropriate container, or validate a reference Value against a container with a graph resolver.

Limited options validate membership using value equality or object identity. Listed values bypass reference validation. Extensible options validate unlisted values using their reference description; a resulting error retains the reference description's ID. Multiple options check each Collection element. `ordered`, `distinct`, `definitive` and relation `sorted` are presentation/editing metadata: the validator does not coerce, sort or deduplicate stored selections. Repeated selected values remain valid even with distinct=true, as the GT reference demonstrates.

allOptions prepares a copy of stored options. Optional single options prepend undefinedValue; allOptionsWith appends a non-nil unlisted current value only when extensible. Option sorting uses the **reference's string rendering**, not the option-label dictionary, and leaves the stored options/selection untouched. The supported scalar rendering has an explicit ASCII case-insensitive sorting boundary; non-ASCII sorting or complex-object rendering without an explicit label fails. Unsorted Unicode values remain lossless. Ties are stable in the ports; upstream tie ordering is not claimed.

Upstream optionsAndLabels uses IdentityDictionary. Portable label keys are therefore object references or immediate nil/Boolean/Character/integer values or interned Symbols (graph/3); integers are restricted to the safely immediate range -1073741824...1073741823 for label keys. String/collection/large-integer identity-sensitive keys are rejected, rather than claiming that content equality preserves their Smalltalk identity. Duplicate label keys fail import. Explicit object labels and supported scalar labels work independently of UI frameworks. Grouping accessors, custom string writers/display blocks and dynamic option sources remain unsupported and fail interchange.

## Bounds, failures and ownership

Limits remain configurable per decode/encode/validation/traversal: bytes (1 MiB), depth (64), descriptions and objects (10,000 each), JSON parser items (100,000), and work/visits (100,000). Work includes reference checks, element visits, and semantic comparison-key construction including every text byte. Large strings or repeated option comparisons can therefore hit the configurable work limit even when the input byte limit is satisfied. The parser checks depth and duplicate keys before materializing untrusted data. Typed collection decoding checks Set uniqueness without quadratic pairwise matching. Semantic comparison keys are length-delimited and preserve exact text content. Collection size is checked before validation materializes character/element arrays. Recursive extensible references terminate with an explicit depth/work error. Limits never truncate input or weaken constraints.

Import validates every reference occurrence, including defaults, opaque metadata, option values and label keys, after allocating all object identities. Unknown members, dangling IDs, duplicate IDs/classes/labels, bad property kinds, unsupported semantics, malformed JSON/UTF-8 and budget overruns fail atomically. C++ throws magritte::Error; Swift throws MagritteError or underlying Foundation/callback errors. Structured validation errors contain description ID, leaf error code and a generic message. Applying a container to an incompatible scalar can produce a model-access runtime failure in upstream; the ports throw an explicit access error rather than incorrectly reporting success or a fabricated validation result.

Mutating models/descriptions requires caller synchronization. Local owning child cycles must be broken by the caller after a failed traversal. Weak reference edges and ID-valued object links are released with the owning graph. Native bindings/functions are never silently exported. The codec preserves supported semantics and explicit presence, not JSON whitespace or table order. Set/Bag enumeration, class-list order and label-entry order are not semantic ordering; child order and stored option order are.

## Graph/3 additions

Every description node additionally requires `conditions`, an array of objects with exactly `label` (String) and `predicate`. Existing scalar/relationship/option members retain their meanings. MATokenDescription has `accessor` and `reference`, but no relation classes or option lists. Additional concrete classes are MASymbolDescription, MAMemoDescription, MAPasswordDescription and MATokenDescription. Properties added in this version are `lineCount` (Memo Integer), `separators` (Token String), `thousandsSeparator` (Number Character), and `trueString`/`falseString` (Boolean String). Boolean alias lists are class defaults, not semantic property overrides. Float bounds are accepted only in this version.

A predicate is one of:

- `{"class":"MAPluggableCondition","selector":"between:and:","receiver":{"type":"nil"},"arguments":[{"type":"integer","value":"0"},{"type":"integer","value":"5"}],"index":0}`. Index zero uses the candidate as receiver; a positive index replaces that one-based argument with the candidate. Arity and index are checked.
- `{"class":"MAConjunctiveCondition","conditions":[...predicates...]}`. Empty means true; evaluation short-circuits after checking the entire configuration.
- `{"class":"MANegationCondition","conditions":[...one predicate...]}`.

The selector allowlist, supported receiver domains, exact numeric-order policy and rejection boundaries are documented in portable-behavior.md. Unknown or ignored extra members are not permitted. Constants cannot contain object references. A description may also hold local callback conditions, but any such callback makes export fail.

Noncontainer accessor records are exactly one of: dictionary/property (`class`, `key`); selector (`class`, `readSelector`, `writeSelector`, with an empty writeSelector meaning unavailable); variable (`class`, `name`); identity (`class`); null (`class`, `uuid` tagged nil or Array of 16 byte Integers); or chain (`class`, `steps` of at least two accessor records, in execution order). Class names use the upstream MA...Accessor names. Containers retain implicit identity. Strategy names/keys are portable ASCII identities; selector and variable execution uses explicit native bindings.

Graph/3 and standalone value codecs additionally accept `{"type":"symbol","value":"ready"}` and `{"type":"float","value":"3ff8000000000000"}`. Float value is exactly 16 lowercase hexadecimal digits containing the IEEE-754 binary64 bit pattern, independent of byte order. Only finite values are accepted; signed zero is retained. Symbol/String content equality and exact Integer/Float equality apply recursively, including Set uniqueness, while identity-safe option labels distinguish those types. Float/Symbol are also allowed relation class constraints only in graph/3.

The text reader/writer APIs are separate from JSON interchange and do not validate or enforce read-only flags. They preserve the supported MAStringReader/Writer behaviors described in portable-behavior.md. Unknown configuration fails explicitly. A decoded legacy graph cannot silently export graph/3 features without an explicit format change.

## Editing and metadata (0.4)

Mementos/caches/originals are local state with no wire representation. Committed portable objects/descriptions continue to use graph/3. The expanded descriptionModelFor factory produces ordinary graph/3 descriptions, including upstream MASelectorAccessor metadata fields and auxiliary reference descriptions. Description model adapters execute only the finite metadata getter/setter profile in editing.md. No tags or graph version were added. Raw model/default behavior remains separate from memento reads; collection values retain snapshot semantics, not live GT aliasing.
