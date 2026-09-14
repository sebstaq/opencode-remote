# Swift och API-kompatibilitet

Kontrollerat 2026-09-13. Detta är ett researchunderlag, inte en körd integration eller ett beslut om bibliotek.

## Slutsats

Swift behöver inget mellanlager i TypeScript. Vi kan anropa OpenCodes HTTP-API direkt och hantera dess händelseström i appen. Den viktigaste tekniska avgränsningen är vilket serverkontrakt vi stöder; att införa en backend enbart för protokollanpassning skulle flytta det arbetet till ytterligare en komponent. En separat tjänst kan senare motiveras av andra krav, exempelvis APNs eller förmedling av anslutningar, enligt [anslutningsrapporten](connection.md).

## Versionsbas

GitHubs release-API rapporterade **v1.18.30**, publicerad 2026-09-09, som senaste release vid kontrollen. Taggen löstes via commits-API:t till **3104c1428ec91f809e5ab86631300de41eb6952e**. Releasefältet `target_commitish` var ett annat värde och används därför inte som källkodens identitet. [Release](https://github.com/anomalyco/opencode/releases/tag/v1.18.30), [taggens commit](https://api.github.com/repos/anomalyco/opencode/commits/v1.18.30).

Det incheckade OpenAPI-dokumentet för releasen är OpenAPI 3.1.0 med 162 paths. Dess `info.version` är `1.0.0`, vilket alltså inte är OpenCode-programmets releaseversion. Dokumentet innehåller både de äldre routarna och `/api/*`; förekomst i schemat är inte ett löfte om stabilitet eller att alla servervarianter använder samma körväg. [Versionslåst schema](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/sdk/openapi.json).

`packages/protocol/src/api.ts` beskriver den nya ytan som experimentell, version `0.0.1`. Det officiella gränssnittets protokolldetektering provar `/global/health` först och skiljer därefter olika svar från `/api/health`; endast ett lyckat health-anrop är därför otillräckligt för att dra slutsatsen att alla önskade funktioner finns. [API-definition](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/api.ts), [officiell detektering](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/app/src/utils/server-protocol.ts).

**Förslag:** använd den dokumenterade äldre API-ytan som första kandidat och verifiera kärnflödet mot just v1.18.30 innan vi fastställer lägsta stödda version. Håll experimentella tillägg separata. Hantera versionsfel och okända händelsetyper tydligt, utan att blanda två olika sessionsmodeller eller gissa att en misslyckad skrivning kan skickas om.

## Swift-alternativ

| Alternativ | Vad vi får | Vad som fortfarande är vårt arbete |
|---|---|---|
| Egen begränsad klient med Foundation/URLSession och Codable | Direkt kontroll över de API-anrop och svar som appen faktiskt använder | Typmodeller, avkodning, fel, SSE, återanslutning och versionsanpassning |
| Apples Swift OpenAPI Generator och URLSession-transport | Genererade anrop och typer från ett versionslåst schema | Verifiera att OpenCodes schema genereras korrekt; hantera händelser, appens tillstånd och kompatibilitet |

Apples generator stöder OpenAPI 3.1 och kan generera klientkod för iOS. Den separata URLSession-transporten stöder strömning på iOS 15 och senare. Det verifierar att tekniken finns, **inte** att OpenCodes fullständiga schema redan har byggts och testats med generatorn här. [Generator](https://github.com/apple/swift-openapi-generator), [transport](https://github.com/apple/swift-openapi-urlsession).

Inget biblioteksval eller lägsta iOS-version är beslutat. En liten senare integrationskontroll bör jämföra hur mycket arbete det faktiskt är att generera de typer vi behöver mot att skriva en begränsad klient; vi behöver inte skapa ett generellt SDK eller en abstraktion för andra agentprodukter.

## Befintliga klienter att lära av

Det finns redan ett publikt native-projekt, `grapeot/opencode_ios_client`, som beskriver chatt, verktygsvisning, filgranskning och Basic Auth. Vid kontrollen löstes dess master till `4af504cad0ae2b12538f5175389e77953f48e9d4`, och trädet innehöll `Services/APIClient.swift`, `Services/SSEClient.swift` och `AppState+SSE.swift`. Detta är en relevant referens för en senare jämförelse; vi har inte byggt appen eller verifierat dess beteende och säkerhet. OpenCodes v1-serverlösenord ger omfattande installationsåtkomst och utgör inte separat behörighet per telefon; se [säkerhetsunderlaget](connection.md). [Versionslåst README](https://github.com/grapeot/opencode_ios_client/blob/4af504cad0ae2b12538f5175389e77953f48e9d4/README.md).

Det finns även `guitaripod/CodingAgentKit`, vars README beskriver en Swift-klient, händelsereducerare och URLSession-baserad SSE för OpenCode. Det är en möjlig teknisk referens, inte en vald dependency eller verifierad kompatibel lösning för vår version. [Projekt](https://github.com/guitaripod/CodingAgentKit).

## Vad detta underlag inte bevisar

Ingen Swift-kompilering, iPhone-/simulatorkörning, anslutning till användarens server eller schema-generering har gjorts. Vi har inte uppgraderat OpenCode, startat processer, ändrat Tailscale eller läst användarens konversationer och autentiseringsfiler. Slutsatsen gäller genomförbar arkitektur utifrån aktuella primärkällor; praktisk acceptans återstår.
