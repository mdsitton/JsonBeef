# JsonBeef

A JSON (RFC 8259) parser and writer for the [Beef](https://www.beeflang.org/) programming language:
fully correct by default, fast, with located errors and opt-in JSONC/JSON5/JSON Lines support. The
sibling of [TomlBeef](https://github.com/mdsitton/TomlBeef), KdlBeef and XmlBeef.

**Status: in development.** The pull reader (`JsonReader`, memory and streams) passes every
conformance suite; the document, writers and the rest are under way (`docs/status.md`). The plan,
requirements, design and research are in `docs/`:

- [`docs/plan.md`](docs/plan.md) — requirements, design, phases, open questions
- [`docs/architecture.md`](docs/architecture.md) — how the implementation works
- [`docs/status.md`](docs/status.md) — verification baseline, feature status, open items
- [`docs/spec-reference.md`](docs/spec-reference.md) — RFC 8259 and the extensions, rule by rule, with edge cases
- [`docs/test-suites.md`](docs/test-suites.md) — the test suites and corpora
- [`docs/implementation-survey.md`](docs/implementation-survey.md) — existing implementations in Beef and
  eight other languages
- [`bench/compare/`](bench/compare/) — the four-track benchmark of the existing implementations

## License

MIT (see `LICENSE`).
