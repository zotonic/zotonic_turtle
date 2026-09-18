# License and attribution review

Checked on 2026-09-18. Scope: this application's source, test runners, vendored
fixtures, notices and declared non-OTP dependencies.

- All 6 Erlang source/test files have Marc Worrell's 2026 copyright and
  Apache-2.0 headers. The full Apache license and application metadata agree.
  The placeholder text in the Apache license's explanatory appendix is part of
  the standard license, not an unfinished project copyright notice.
- The implementation was written for Zotonic; no Elixir or Java implementation
  source was copied or transliterated. Reference projects and specifications
  are identified in [NOTICE](NOTICE) and [README.md](README.md).
- 431 vendored upstream files were compared byte-for-byte with commit
  `369a90d1a60c021b746df2e411da0ff36258a758` from the recorded archive.
  Their original notices are preserved.
- Fixture data remains separately licensed. Both W3C license texts are included;
  the BSD option is used for development testing. See
  [fixture provenance](https://github.com/zotonic/zotonic_turtle/blob/main/test/data/w3c-turtle/SOURCE.md).
- Declared dependencies `zotonic_rdf`, `zotonic_jsonld` identify Apache-2.0 in their
  checked-out license files and application metadata. They are dependencies,
  not source copied into this application; this review does not replace their
  notices or audit a future release's complete transitive dependency graph.

When distributing fixtures, include their original notices and accompanying
license/provenance files. Regression results from the local runner are not a
W3C conformance certification or endorsement. No parser behavior was changed
by this review.
