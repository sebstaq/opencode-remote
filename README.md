# OpenCode på iPhone

Plan för en native iPhone-klient för personer som redan har OpenCode installerat. Appen ska ge full åtkomst till agentarbetet från iPhone, med Swift/SwiftUI och så lite egen infrastruktur som möjligt.

## Läget nu

Projektet är i planering och `opencode-remote` är arbetsnamnet för repo:t. Researchen kontrollerades 2026-09-13 mot OpenCode **v1.18.30**, med källkod på commit `3104c1428ec91f809e5ab86631300de41eb6952e`. Den visar att en direkt iPhone-klient mot OpenCodes server är genomförbar, men ingen app, serveranslutning, Tailscale-väg eller runtime-verifiering är gjord ännu.

Första planerade flödet är iPhone → privat HTTPS via Tailscale Serve → användarens befintliga OpenCode-installation. Egen backend hålls utanför kärnflödet tills ett konkret krav motiverar den.

## Dokument

- [Beslut och öppna frågor](docs/DECISIONS.md)
- [Anslutningsspec](docs/connection.md)
- [Struktur och verktyg](docs/structure.md)
- [Acceptanskriterier: anslutning](docs/acceptance.md)
- [Mätningar](docs/measurements.md)
- [Nästa steg](docs/NEXT_STEPS.md)
- [Researchunderlag](docs/research/README.md)

Researchen skiljer mellan den dokumenterade äldre API-ytan och den experimentella `/api/*`-ytan. Vilken yta som stöds först ska avgöras genom en avgränsad integrationskontroll mot vald serverversion.

## Avgränsning

Nuvarande arbete gäller produktplanering och teknisk verifiering. Det omfattar inte implementering av iPhone-appen, drift av en ny molntjänst eller ändringar i användarens OpenCode- och nätverksmiljö.
