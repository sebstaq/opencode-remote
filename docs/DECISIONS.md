# Beslut och öppna frågor

## Bekräftat av användaren

### Produkt

- Plattformen är **iPhone only**.
- Klienten byggs native i **Swift/SwiftUI** för iOS 17 och senare.
- Arbetnamnet är **OpenCode Remote** (repositoriet heter `opencode-remote`).
- Appen förutsätter att användaren redan har en fungerande **OpenCode-installation**.
- Ambitionen är **fullt agentarbete**: agentkörning, frågor, godkännanden, status, historik och återkomst efter avbrott ska kunna hanteras från mobilen.
- MVP ska vara **App Store-publicerbar**.

### Anslutning

- **Tailscale Serve** ger privat HTTPS mellan iPhone och användarens OpenCode-installation.
- Servern skyddas med `OPENCODE_SERVER_PASSWORD` och grund-autentisering.
- Credential lagras per anslutning i **Keychain**. Ingen kontotjänst och ingen host-helper.
- Parkoppling i MVP är **manuell inmatning av URL och lösenord**. Ingen QR-kod och inget skript.
- Flera anslutningar (**Datorer**) kan vara aktiva samtidigt. MVP visar dem separat; en gemensam vy är senare.

### API och klient

- Endast OpenCodes HTTP-API används. Ingen egen backend, ingen agentmotor och ingen egen konversationsdatabas.
- Klienten anropar den **dokumenterade äldre API-ytan**. Experimentella `/api/*` och `/experimental/*` används inte i MVP.
- Swift-klienten **genereras vid bygget** från ett trimmat, pinnat OpenAPI-urval (swift-openapi-generator som build-plugin).
- **Version:** pin mot senaste OpenCode vid byggtillfället, tillåt nyare servrar, garantera inte bakåtkompatibilitet för äldre än dagens senaste, och visa ett tydligt fel vid äldre eller okänd version (läst ur `/global/health`). Endast endpoints som finns i den pinnade specen anropas.

### MVP-omfattning (ingår)

- Lägga till, redigera och ta bort Datorer (URL och lösenord i Keychain).
- Öppna befintliga projekt samt skapa nytt projekt där API:t tillåter (mappväljare som endast visar kataloger, eller manuell sökväg).
- Lista, skapa, byta namn på, avbryta och radera sessioner.
- Välja agent och modell.
- Skicka text och bilder (kamera eller bibliotek) som en instruktion.
- Följa svar och verktygsstatus i realtid.
- Svara på frågor och godkännanden (preliminärt, se nedan).
- Visa todo och barnsessioner läs-only.
- Återstämma mot servern vid återkomst.

### MVP-omfattning (ingår inte)

- Diff- och filvisning. Granskning sker i git/GitHub efter att agenten pushat.
- Manuell filredigering.
- Shell och terminal (`/session/:id/shell`, `/pty`).
- Dela session, fork och revert/unrevert.
- Pushnotiser.
- Egen backend eller host-helper.
- Sökfält i sidebaren.

### IA och distribution

- **Sidebar och chattfönster** är huvudyta; allt annat är popup och overlay.
- Bygge sker på en **OSX-VM**. IPA distribueras via **Diawi** under utveckling och via **TestFlight** mot slutet av MVP.
- Integritet: ingen telemetri eller analytics, privacy manifest utan datainsamling, inga privata API:er.

## Preliminärt (måste undersökas vid implementation)

- Godkännande- och frågeoverläggets exakta beteende (approve/deny/always, blockeringsgrad).
- Meddelanderenderingens omfattning (reasoning, retry, kompaktering, token- och kostnadsräknare).

## Öppna frågor och att verifiera

- Kan den äldre API-ytan öppna en godtycklig mapp som nytt projekt via `directory`-parametern på `POST /session`? Avgörs i integrationskontrollen.
- Genererar det trimmade OpenAPI-urvalet ren Swift med Swift OpenAPI Generator utan anpassningar?
- Slutligt App Store-namn och bundle-id.
- Exakt lägsta OpenCode-serverversion (pin fastställs vid byggtillfället).
- Uppsättning av Tailscale på iPhone och värddator.

## Versionbas

Researchen kontrollerades 2026-09-13 mot OpenCode **v1.18.30**, med källkod på commit `3104c1428ec91f809e5ab86631300de41eb6952e`. Det är den version som ska pinnas tills en nyare verifieras.
