# Structure, tooling, lint and tests

## Folders

```
opencode-remote/
├── project.yml                 # XcodeGen, source of the app project
├── Makefile                    # generate, format, lint, build, test, e2e, measure
├── Packages/
│   └── OpenCodeAPI/            # generated client + pinned spec
│       ├── Package.swift
│       └── Sources/OpenCodeAPI/
│           ├── openapi.json            # trimmed, pinned MVP surface
│           ├── openapi-generator-config.yaml
│           └── (generated Swift code, committed)
├── App/
│   ├── Core/                   # ConnectionService, Metrics, Keychain, Reconnect
│   ├── Features/               # AddComputer, Sessions, Chat, Settings
│   ├── DesignSystem/
│   └── Resources/
├── Tests/
│   ├── IntegrationTests/       # against a real opencode serve
│   └── UITests/                # XCUITest, e2e flows
├── scripts/                    # serve-fixture, measure, diawi
└── docs/
```

## Build

- **XcodeGen** generates `OpenCodeRemote.xcodeproj` from `project.yml`. The project file is not committed. `make generate` runs before building.
- The **SwiftPM package** `Packages/OpenCodeAPI` owns the client. The spec is trimmed to the MVP surface and pinned in `Sources/OpenCodeAPI/openapi.json`.
- The client is generated **at build time** by swift-openapi-generator (build plugin) and is not committed. The first build takes a few minutes; after that it is cached.
- **XcodeGen** is fetched as a binary (brew is owned by another user in the VM): `~/tools/xcodegen/xcodegen/bin/xcodegen`, version 2.46.0.
- Xcode requires the build plugin to be approved. We therefore run `xcodebuild` with `-skipPackagePluginValidation` (in the Makefile and `scripts/measure.sh`).

## Lint and formatting: hard rules

- **swift-format** is the only tool. `make lint` runs `swift format lint --strict` on `App`, `Tests` and `Packages/OpenCodeAPI/Package.swift`. Generated code under `Packages/OpenCodeAPI/Sources/OpenCodeAPI/` is excluded.
- **No warnings in our code.** Anything that deviates is an error:
  - `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`
  - `GCC_TREAT_WARNINGS_AS_ERRORS = YES`
  - `SWIFT_STRICT_CONCURRENCY = complete`
- No `#warning`, no TODOs left as warnings. `make lint` and `make build` fail on the smallest deviation in our code.
- **Generated code is excluded.** Swift OpenAPI Generator 1.13.1 produces Swift 6.2 warnings (`public import ... not used`) in generated code we do not own. The package is therefore built without warnings-as-errors, and the formatting lint skips generated files.

## Testing: inverted pyramid

- **Integration dominates.** Tests against a real `opencode serve` (isolated data and state directory, fixture project): health, projects, sessions, message with `noReply`, `/event`, approval, plus connection and reconnect with the measurement points from `connection.md`.
- **E2E in the simulator** with XCUITest: add computer, connection, session list, open chat, send, approval. Manual tap verification is done with `axe` on the VM.
- **Performance** is measured as connect and reconnect, p50/p95, against the budgets in `connection.md`.
- **Unit tests are the exception**, only where they obviously pay off, such as backoff math and URL parsing. We gate on integration and e2e, not on unit tests.

## Fixtures and measurement

- `scripts/serve-fixture.sh` starts `opencode serve` against an isolated directory with a fixture project and pre-seeded sessions, so integration tests and measurements run against a known and harmless server.
- `scripts/measure.sh` runs repeated connection and reconnect runs and compiles p50/p95.

## Tasks

- `make generate` generates the Xcode project.
- `make format` formats the code.
- `make lint` runs the formatting lint and a warning-free build.
- `make build` builds the app for the simulator.
- `make test` runs integration and e2e.
- `make measure` runs the performance measurements.
