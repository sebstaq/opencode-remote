# Anslutning: tillstånd, mätpunkter, budgetar och reconnect

## Syfte

Beskriver hur appen ansluter till en **Computer** (en OpenCode-server), vad "ansluten" betyder, exakt vad som mäts, vilka budgetar vi siktar på och hur reconnect fungerar. Gäller den första implementationsskivan (Add computer, sessionslista, chatt) och ligger till grund för mät- och optimeringsarbetet.

## Begrepp

- **Computer:** en anslutningsprofil, alltså Tailscale-HTTPS-URL plus serverlösenord i Keychain.
- **Anslutning:** en aktiv HTTP-session med keep-alive mot en Computer.
- **Projekt och sessioner:** servermodell enligt `DECISIONS.md`.
- En Dator är en maskin och aldrig ett projekt.

## Tillstånd och övergångar

Tillstånd: `idle`, `connecting`, `connected`, `reconnecting`, `offline`.

- `idle` → `connecting`: användaren sparar eller öppnar en Computer, eller appen startar med en vald Computer (prefetch).
- `connecting` → `connected`: `/global/health` svarar 200 och versionen stöds.
- `connecting` → `offline`: fel (onåbar, TLS, 401, för låg version eller timeout).
- `connected` → `reconnecting`: nätet tappas, ett anrop misslyckas eller SSE-strömmen bryts.
- `reconnecting` → `connected`: health och version ok igen.
- `reconnecting` → `offline`: efter max antal försök, eller vid icke-återhämtningsbart fel (401, för låg version).
- `offline` → `connecting`: manuellt "Try again" eller att nätet kommer tillbaka via `NWPathMonitor`.

Invariant: **"ansluten" är inte samma sak som "data laddad"**.

## Definitioner

- **Ansluten:** senaste health-anropet svarade 200 och versionen är minst den pinnade miniminivån.
- **Data laddad:** projekt och sessioner för aktiv Computer har hämtats efter senaste anslutningen.
- **Server som sanning:** servern äger sessioner och körstatus. Vi cachar inget som sanning.

## Anslutningssekvens (Add computer till ansluten)

1. Parsa URL. Endast `https` accepteras, `http` avvisas.
2. Validera att lösenordsfältet inte är tomt.
3. `GET /global/health` med grund-autentisering och timeout.
4. Parsa `{ healthy, version }` och jämför mot pinnad minversion.
5. Vid ok: spara profilen i Keychain, markera `connected` och hämta därefter projekt och sessioner.
6. Vid fel: mappa till feltyp, visa i formuläret och spara inget.

Mätpunkter (monotona tidsstämplar):

- `t0`, användaren trycker Save eller prefetch startar
- `t_dns`, `t_tcp`, `t_tls` (start/slut per fas)
- `t_request_sent`
- `t_ttfb`, första byte
- `t_response_end`
- `t_health_parsed`
- `t_version_ok`
- `t_sessions_loaded`
- `t_connected` = `t_version_ok`
- `t_ready` = `t_sessions_loaded`

## Instrumentering

- `URLSessionTaskMetrics` per task: DNS, TCP, TLS, TTFB och total.
- `os_signpost` (Points of Interest) per tillståndsövergång och milstolpe, som intervall.
- En ringbuffert i appen med mätposter (tillstånd, milstolpe, millisekunder) som kan exporteras i debug och TestFlight för p50/p95.
- Mätlagret ligger runt den genererade klienten, inte inuti den.

## Budgetar (förslag, ska justeras)

Varma anslutningar (keep-alive och återanvänd TLS), över Tailscale:

- health TTFB: p50 < 120 ms, p95 < 300 ms
- tid till `connected`: p50 < 300 ms, p95 < 800 ms
- tid till `ready`: p50 < 700 ms, p95 < 1,5 s

Kalla anslutningar (ingen session eller keep-alive):

- `connected`: p50 < 800 ms, p95 < 2 s
- `ready`: p50 < 1,5 s, p95 < 3 s

Reconnect efter framtvingat avbrott:

- tid till `connected` igen: p50 < 1 s, p95 < 3 s vid första försöket
- inga dubbla instruktioner; ett skickat meddelande får aldrig köras två gånger

Lokal server (loopback eller simulator) används som baslinje för att separera nätkostnad från Tailscale-kostnad.

## Reconnect-policy

- `NWPathMonitor`: vid `satisfied`, försök återansluta direkt. Vid `unsatisfied`, gå till `reconnecting` eller `offline`.
- Backoff: 0,5 s, 1 s, 2 s, 4 s, 8 s som tak, med jitter på omkring 20 procent. Återställs efter lyckad anslutning.
- SSE (`/event`): håll strömmen öppen. Vid brott, återanslut med backoff och kör alltid en resync (status, meddelanden och väntande beslut) efter återanslutning.
- Foreground: vid appstart och återkomst körs connect-sekvensen och en resync. En återöppnad socket får inte ensam räknas som att allt är hämtat.
- Icke-återhämtningsbart (401 eller för låg version): stanna i `offline` och kräv användaråtgärd.

## Optimeringskrav

- En `URLSession` per Computer med keep-alive, och TLS-session resumption.
- Parallellisera oberoende anrop (projekt, sessioner, status) efter `connected`, undvik sekventiella rundturer.
- Prefetch: vid appstart, anslut direkt till senast använda Computer utan att blockera UI.
- Håll SSE öppen i stället för att polla.
- Hämta inte hela historiken i onödan. Ta senaste och paginera bakåt.
- Använd HTTP/2 om servern erbjuder det (Tailscale Serve och OpenCode), annars keep-alive.

## Felkatalog och UI

- Ogiltig eller icke-https-URL: inline i formuläret.
- Onåbar eller timeout: "Can't reach the computer".
- TLS-fel: samma felskärm med annan text.
- 401: "Wrong password".
- För låg version: "Server version not supported", med båda versionerna synliga.

Felen mappar mot felskärmarna i wireframen.

## Mätmetod

- Funktionell kontroll i simulatorn (simctl och axe), men det är inte sanningen om latens.
- Latenssanning på fysisk iPhone via Diawi mot en riktig Tailscale-ansluten OpenCode-server.
- Repeterade körningar: minst 30 per scenario, redovisa p50, p95 och max.
- Scenarier: kall start, varm start, reconnect efter flygplansläge, reconnect efter serveromstart, samt latens och paketförlust via Network Link Conditioner eller `tc netem`.
- Baslinje mot lokal server för att isolera Tailscale-kostnaden.

## Öppna frågor

- Exakta budgetar. Siffrorna ovan är förslag.
- Tailscale Serve-hoppets faktiska kostnad. Måste mätas.
- Om HTTP/2 erbjuds via Tailscale Serve och OpenCode.
- Timeoutvärden för health och tak för reconnect.
- Hur mycket historik som hämtas initialt.
