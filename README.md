# JsonBeef

A JSON (RFC 8259) parser and writer for the [Beef](https://www.beeflang.org/) programming language:
fully correct by default, fast, with located errors and opt-in JSONC/JSON5/JSON Lines support. The
sibling of [TomlBeef](https://github.com/mdsitton/TomlBeef), KdlBeef and XmlBeef.

**Status: planning.** Nothing parses JSON yet. The plan, requirements and research are in `docs/`:

- [`docs/plan.md`](docs/plan.md) — requirements, design, phases, open questions
- [`docs/spec-reference.md`](docs/spec-reference.md) — RFC 8259 and the extensions, rule by rule, with edge cases
- [`docs/test-suites.md`](docs/test-suites.md) — the test suites and corpora
- [`docs/implementation-survey.md`](docs/implementation-survey.md) — existing implementations in Beef and
  eight other languages
- [`bench/compare/`](bench/compare/) — the four-track benchmark of the existing implementations

## License

MIT (see `LICENSE`).
