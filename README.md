# JsonBeef

A JSON (RFC 8259) parser and writer for the [Beef](https://www.beeflang.org/) programming language:
fully correct by default, fast, with located errors and opt-in JSONC/JSON5/JSON Lines support. The
sibling of [TomlBeef](https://github.com/mdsitton/TomlBeef), KdlBeef and XmlBeef.

**Status: in development.** Done: the pull reader (`JsonReader`, memory and streams, with on-demand
`SkipValue`, `ReadRaw` and `Find`), which passes every conformance suite; the document (`JsonDocument`:
lookups, JSON Pointer, mutation, positions, PreserveStyle round trips); the writers (compact, indented,
RFC 8785); JSONC; collect-errors; and typed mapping. Sequences, JSON5 and the other extras are next
(`docs/status.md`).

```beef
[JsonObject(Naming = .CamelCase)]
class Server
{
	public String HostName ~ delete _;
	public int32 Port = 8080;
	public List<String> Tags ~ DeleteContainerAndItems!(_);
}

let server = scope Server();
Try!(JsonSerializer.ReadFile("server.json", server));   // straight from the reader, every check on
server.Port = 8443;
Try!(JsonSerializer.WriteFile(server, "server.json", .Pretty));
```

The plan, requirements, design and research are in `docs/`:

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
