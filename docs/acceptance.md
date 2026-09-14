# Acceptanskriterier: anslutning

Varje kriterium ska vara körbart och mätbart. Riktig anslutning betyder fysisk iPhone över Tailscale mot en riktig OpenCode-server, inte simulator.

## Kriterier

- **AC1, anslut.** Med en riktig Tailscale-HTTPS-URL och serverlösenord blir appen `connected`, visar serverns faktiska version, och versionsgrinden accepterar minst miniminivån samt avvisar äldre med båda versionerna synliga.
- **AC2, fel lösenord.** 401 mappas till "Wrong password", och ingenting sparas i Keychain.
- **AC3, onåbar och TLS.** Onåbar host och TLS-fel ger respektive felskärm, utan krasch.
- **AC4, tid.** Kall och varm anslutning mäts på den riktiga vägen och ligger inom budgetarna i `connection.md` (p50 och p95).
- **AC5, reconnect.** Framtvingat avbrott (flygplansläge eller stoppad server) ger `reconnecting` och sedan `connected`, tid till återhämtning mäts, och ingen instruktion körs dubbelt.
- **AC6, enhet.** AC1 till AC5 körs på fysisk iPhone installerad via Diawi, över Tailscale, mot den riktiga servern.
- **AC7, säkerhet.** Lösenordet finns bara i Keychain och loggas eller skrivs aldrig ut.

## Testmiljöer

- **Lokal fixture (utan auth).** `scripts/serve-fixture.sh` startar `opencode serve` mot en isolerad katalog för integrationstester av API och klient. Ingen Tailscale.
- **Riktig väg.** `scripts/rig-host.sh up` startar `opencode serve` på hosten på loopback med serverlösenord från miljön, och aktiverar Tailscale Serve så att servern nås som `https://<host>.<tailnet>.ts.net/`. Klienten är den fysiska iPhone som redan ligger på tailnätet.
- **Simulator.** Används för funktion (simctl och axe) mot lokal eller vidarebefordrad server, aldrig som sanning om latens.

## Rig

- `scripts/rig-host.sh up|down`. `up` kräver att `OPENCODE_SERVER_PASSWORD` finns i miljön och vägrar starta en oautentiserad server. `down` tar bort Tailscale Serve-konfigurationen och stoppar servern.
- Lösenordet tillhandahålls av användaren via miljön, skrivs aldrig ut och checkas aldrig in.

## Mätning

- Alla tidsmått följer mätpunkterna i `connection.md`. Resultat redovisas som p50, p95 och max över minst 30 körningar per scenario.
