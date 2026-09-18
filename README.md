# zotonic_turtle

An Erlang RDF 1.1 Turtle parser and generator using the document and triple maps
from `zotonic_rdf`. Standard output prefixes come exclusively from
`zotonic_rdf:namespaces/0`, including the Zotonic predicate namespace. The parser
never fetches IRIs or reads referenced files: prefix/base directives only resolve
identifiers.

## Quick start

```erlang
Turtle = <<"@prefix schema: <https://schema.org/> . "
           "<https://example.org/alice> schema:name \"Alice\" .">>,
{ok, Documents} = zotonic_turtle:parse(Turtle),
{ok, Output} = zotonic_turtle:generate(Documents),
{ok, Triples} = zotonic_turtle:parse_triples(Turtle),
{ok, Output2} = zotonic_turtle:generate_triples(Triples).
```

## API

All operations return `{ok, Result}` or `{error, Reason}`. `decode/1` and
`encode/1` alias document parsing and generation.

`parse/1,2` accepts UTF-8 iodata and returns a list of standard Zotonic document
maps with a standard `@context`. Explicit datatypes and lexical values survive;
blank-only graphs, shared blank nodes, and cycles are retained as separate
identified documents. RDF collections remain their underlying first/rest graph.

`parse_triples/1,2` returns flat binary-keyed RDF triple maps with expanded IRIs.
The parser accepts prefix/base directives in both Turtle and SPARQL spelling,
Unicode IRIs and names, short/long quoted strings, language/datatype literals,
numeric/boolean literals, predicate/object lists, blank-node property lists,
and collections. Syntax errors include a line number where available.

## Parsing options

| Option | Meaning | Default |
| --- | --- | --- |
| `base` | Binary IRI used to resolve relative IRIs. | No base. |
| `prefixes` | Map of initial binary prefix names to namespace IRIs. | Empty map. |
| `max_depth` | Maximum nesting of collections and blank-node property lists. | `128`. |

Relative IRIs need a base. To accept undeclared standard prefixes explicitly, pass
`#{prefixes => zotonic_rdf:namespaces()}`.

## Generation and format limits

`generate/1,2` accepts Zotonic/JSON-LD document maps. It uses `zotonic_jsonld` to
resolve the entire input context before RDF conversion, and accepts that
application's expansion options. External JSON-LD contexts are disabled by
default. Set `allow_external_contexts => true` explicitly to enable fetching or
custom loader callbacks; set it to `false` to disable them. The `contexts` option
can supply context documents in memory without enabling external loading.
These options apply to document generation; Turtle parsing itself performs no
external loading, regardless of IRI scheme.

```erlang
{ok, Output} = zotonic_turtle:generate(Documents, #{allow_external_contexts => true}).
```

`generate_triples/1` accepts expanded RDF triples directly. The writer emits sorted prefix declarations and one triple per
line, preserving literal lexical forms. It uses full IRIs where a standard
prefixed name cannot represent the IRI.

Turtle represents a single RDF graph. Named graphs, JSON-LD directional literals
and `@json` conversion are rejected explicitly. TriG and RDF 1.2 triple terms are
not part of this RDF 1.1 implementation.

## JSON-LD interoperability

Both applications use the same document maps, so conversion needs no intermediate
string format:

```erlang
{ok, Documents} = zotonic_turtle:parse(Turtle),
{ok, Json} = zotonic_jsonld:generate(Documents),
{ok, ParsedDocuments} = zotonic_jsonld:parse(Json),
{ok, TurtleAgain} = zotonic_turtle:generate(ParsedDocuments).
```

## Build and test

The Makefile downloads a local rebar3 when needed (requires curl). To use an
existing installation, pass its absolute path, for example
`make REBAR="$(command -v rebar3)"`. GNU make is required; on systems whose
default make is not GNU make, the wrapper uses `gmake`. GitHub Actions runs
compilation, EUnit (including the vendored W3C cases), XRef and Dialyzer on
OTP 27, 28 and 29 for pushes and pull requests to `main`.

Requires Erlang/OTP 25 or later and rebar3. The dependency requirements include
`zotonic_rdf` 1.2.0 and `zotonic_jsonld` 1.0.0; JSON-LD requires
`jsxrecord` 2.3.0 or later within the 2.x series. For local JSON-LD development,
place that application in rebar3's `_checkouts` directory.

```sh
make
make test
make xref
make dialyzer
make doc
```

`make doc` generates ExDoc documentation in `doc/`, with the README as its
landing page. `make edoc` remains available for EDoc output.

The 313 W3C RDF 1.1 Turtle tests are vendored in
[`test/data/w3c-turtle`](https://github.com/zotonic/zotonic_turtle/blob/main/test/data/w3c-turtle/SOURCE.md), with the original manifest,
input/output fixtures and license. `turtle_w3c_tests` runs them by default, checks
positive and negative syntax, compares evaluation results modulo blank-node IDs,
and verifies writer round trips. `W3C_TURTLE_TESTS` can select another fixture
checkout. Application tests also cover document conversion and JSON-LD round trips.

## License and provenance

Copyright 2026 Marc Worrell. The Erlang implementation and test runners use
[Apache-2.0](LICENSE); see [NOTICE](NOTICE) for attribution and references.
This is an implementation written for Zotonic, not a port or direct
transliteration of Jena or RDF.ex. Those projects provided API and serialization
references; their implementation source is not included.

The vendored W3C fixtures retain their original copyright notices and their
separate [W3C licensing](https://github.com/zotonic/zotonic_turtle/blob/main/test/data/w3c-turtle/LICENSE.md). The full
[W3C 3-clause BSD terms](https://github.com/zotonic/zotonic_turtle/blob/main/test/data/w3c-turtle/LICENSE-W3C-BSD.txt) and
[source details](https://github.com/zotonic/zotonic_turtle/blob/main/test/data/w3c-turtle/SOURCE.md) are included alongside them.

The [completed license review](LICENSE_REVIEW.md) records the checked source
headers, dependency metadata, pinned fixture revisions and redistribution notices.
The fixtures are used under the BSD option for development testing; local test
results do not constitute W3C conformance certification or endorsement.

## References

The implementation follows the [W3C Turtle grammar](https://www.w3.org/TR/turtle/).
API and serialization examples were checked in [Apache Jena](https://jena.apache.org/documentation/io/)
and Elixir's [RDF.ex](https://github.com/rdf-elixir/rdf-ex).
