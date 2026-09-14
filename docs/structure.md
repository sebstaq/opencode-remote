# Struktur, verktyg, lint och test

## Mappar

```
opencode-remote/
├── project.yml                 # XcodeGen, källa till app-projektet
├── Makefile                    # generate, format, lint, build, test, e2e, measure
├── Packages/
│   └── OpenCodeAPI/            # genererad klient + pinnad spec
│       ├── Package.swift
│       └── Sources/OpenCodeAPI/
│           ├── openapi.json            # trimmad, pinnad MVP-yta
│           ├── openapi-generator-config.yaml
│           └── (genererad Swift-kod, incheckad)
├── App/
│   ├── Core/                   # ConnectionService, Metrics, Keychain, Reconnect
│   ├── Features/               # AddComputer, Sessions, Chat, Settings
│   ├── DesignSystem/
│   └── Resources/
├── Tests/
│   ├── IntegrationTests/       # mot en riktig opencode serve
│   └── UITests/                # XCUITest, e2e-flöden
├── scripts/                    # serve-fixture, measure, diawi
└── docs/
```

## Bygge

- **XcodeGen** genererar `OpenCodeRemote.xcodeproj` från `project.yml`. Projektfilen checkas inte in. `make generate` körs innan bygge.
- **SwiftPM-paketet** `Packages/OpenCodeAPI` äger klienten. Specen är trimmad till MVP-ytan och pinnad i `Sources/OpenCodeAPI/openapi.json`.
- Klienten genereras **vid bygget** av swift-openapi-generator (build-plugin) och checkas inte in. Första bygget tar några minuter, därefter är det cachat.
- **XcodeGen** hämtas som binär (brew ägs av en annan användare i VM:en): `~/tools/xcodegen/xcodegen/bin/xcodegen`, version 2.46.0.
- Xcode kräver att build-pluginen godkänns. Vi kör därför `xcodebuild` med `-skipPackagePluginValidation` (ligger i Makefile och `scripts/measure.sh`).

## Lint och formatering: hårda regler

- **swift-format** är enda verktyget. `make lint` kör `swift format lint --strict` på `App`, `Tests` och `Packages/OpenCodeAPI/Package.swift`. Genererad kod under `Packages/OpenCodeAPI/Sources/OpenCodeAPI/` undantas.
- **Inga varningar i vår kod.** Allt som avviker är ett fel:
  - `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`
  - `GCC_TREAT_WARNINGS_AS_ERRORS = YES`
  - `SWIFT_STRICT_CONCURRENCY = complete`
- Inga `#warning`, inga TODO som lämnas som varning. `make lint` och `make build` failar på minsta avvikelse i vår kod.
- **Genererad kod är undantagen.** Swift OpenAPI Generator 1.13.1 ger Swift 6.2-varningar (`public import ... not used`) i genererad kod som vi inte äger. Paketet byggs därför utan warnings-as-errors, och formateringslinten hoppar över genererade filer.

## Test: inverterad pyramid

- **Integration dominerar.** Tester mot en riktig `opencode serve` (isolerad data- och state-katalog, fixture-projekt): health, projekt, sessioner, meddelande med `noReply`, `/event`, godkännande, samt anslutning och reconnect med mätpunkterna från `connection.md`.
- **E2E i simulator** med XCUITest: add computer, anslutning, sessionslista, öppna chatt, skicka, godkännande. Manuell klickverifiering sker med `axe` i VM:en.
- **Prestanda** mäts som connect och reconnect, p50/p95, mot budgetarna i `connection.md`.
- **Enhetstester är undantag**, bara där de uppenbart lönar sig, till exempel backoff-matematik och URL-parsing. Vi grindar på integration och e2e, inte på enhetstester.

## Fixturer och mätning

- `scripts/serve-fixture.sh` startar `opencode serve` mot en isolerad katalog med ett fixture-projekt och förseedade sessioner, så integrationstester och mätningar går mot en känd och ofarlig server.
- `scripts/measure.sh` kör repeterade anslutnings- och reconnect-körningar och sammanställer p50/p95.

## Uppgifter

- `make generate` genererar Xcode-projektet.
- `make format` formaterar koden.
- `make lint` kör formateringslint och ett varningsfritt bygge.
- `make build` bygger appen för simulator.
- `make test` kör integration och e2e.
- `make measure` kör prestandamätningarna.
