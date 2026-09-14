# OpenCode på iPhone – beslutsunderlag

Researchdatum: 2026-09-13. Inriktningen är en native iPhone-app i Swift/SwiftUI för personer som redan har OpenCode installerat. Appen ska kunna användas för att driva agentarbetet fullt ut. Tailscale är accepterat initialt; egen backend ska begränsas till sådant som ett konkret krav faktiskt behöver.

## Samlad bedömning

**Vi har stöd för att gå vidare med en direktansluten iPhone-klient utan egen molnbackend för kärnflödet.** OpenCode tillhandahåller redan sessioner, agentkörning, historik och API:er för interaktion. Mobilappens betydande arbete är gränssnitt, hantering av händelser, återanslutning och korrekt återgivning av serverns tillstånd. Det är genomförbarhet utifrån dokumentation och källkod, inte en färdig eller fysiskt verifierad iPhone-integration. [OpenCodes server-API](https://opencode.ai/docs/server/).

Första anslutningsvägen är **iPhone → privat HTTPS via Tailscale Serve → OpenCode på användarens dator/server**. Det kräver Tailscale på båda enheterna, rätt tailnet och godkänd VPN-konfiguration på iPhone. Tailscale Serve är en befintlig proxy på värddatorn; vi behöver inte skriva en egen motsvarighet. OpenCode kan lyssna på loopback och använda sitt serverlösenord. [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve), [Tailscale på iOS](https://tailscale.com/docs/install/ios).

## Vad vi behöver äga

| Behov | Befintligt stöd | Vårt ansvar / möjlig extra komponent |
|---|---|---|
| Agentkörning, filer, projekt och historik | Användarens OpenCode-installation | Native UI och API-klient |
| Krypterad privat fjärranslutning | Tailscale och Serve HTTPS | Anslutningsprofil, Keychain och tydlig felhantering |
| Fortsätta efter att mobilen tappat nätet | Serverkörning och läsbart tillstånd | Återanslutning, avstämning och undvika dubbla instruktioner |
| Samma pågående arbete från dator och mobil | Flera klienter kan tala med OpenCode | Ansluta till samma körande server; inte anta att två separata processer delar aktiv körning |
| Notis när något händer medan appen är stängd | Apples APNs för fjärrnotiser | Händelsekälla på datorn och en betrodd APNs-avsändare; separat möjlig tilläggstjänst |
| Ta bort kravet på Tailscale-appen | Användarhanterad HTTPS eller SSH är möjliga vägar | Mer anslutningsarbete; inte automatiskt vår egen molntjänst |
| Enkel parkoppling och återkalla en enskild telefon | Inte ett dokumenterat OpenCode-v1-flöde | En liten hjälpprocess på datorn kan äga enhetsbehörigheter om den är enda externa vägen till loopback-bunden OpenCode |
| Anslutning utan nätverkskonfiguration genom olika NAT/nät | Inte löst av enbart QR-kod eller autentisering | Utred befintlig anslutningstjänst eller förmedlingstjänst om detta blir ett krav |

Detaljer och primärkällor: [anslutning och säkerhet](connection.md), [livscykel och återanslutning](lifecycle.md).

Ingen egen databas för konversationer, kontotjänst eller agentmotor behövs för det föreslagna första flödet. Lokal lagring av anslutningsprofiler, utkast och eventuell cache är appfunktioner. Tailscale och modellleverantörerna är fortfarande externa beroenden: ingen egen molndrift betyder inte att hela lösningen är fristående från tjänster.

## Flödet vi ska utforma

Vi behöver ett sammanhängande flöde från anslutning och projektval till nytt eller befintligt samtal, val av agent/modell, instruktion med eventuell bilaga, löpande verktygsaktivitet, agentfrågor och godkännanden, granskning av ändringar och nästa instruktion. Projektets filer och kommandon körs på värddatorn. Alla frågor och godkännanden som behövs för att arbetet ska gå vidare måste vara tillgängliga i mobilens UI.

Funktionsgranskningen hittar direkt stöd för dessa kärndelar, inklusive läsbara väntande frågor/godkännanden och sessionens diff. Några gränser påverkar UI-planeringen: bilagor skickas som del av instruktionen snarare än till en separat uppladdningstjänst, och dedikerade knappar för exempelvis Git commit/push har inte egna motsvarande REST-routes utan behöver använda värddatorns befintliga kommandovägar. Det är inte i sig ett skäl att bygga en ny backend. [Versionslåst API-schema](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/sdk/openapi.json).

**Full agentanvändning är den beslutade ambitionen.** Hur omfattande manuell kodeditering, terminal och visning av körande webbsidor vi vill ha är ännu inte produktbeslut. API-granskningen skiljer därför direkta API-funktioner från sådant agenten kan utföra med sina befintliga verktyg, och från möjliga extra tjänster. Se [funktionskartan](api.md).

## Avbrott är en del av normal användning

Telefonen ska kunna lämna appen utan att appen själv måste hålla agenten vid liv. Det betyder inte att en avstängd eller sovande värddator kan fortsätta arbeta, eller att en serveromstart automatiskt återupptar ett jobb.

När appen återkommer behöver den hämta aktuella meddelanden, körstatus och väntande frågor/godkännanden. En återöppnad liveanslutning får inte ensam betraktas som bevis för att allt som hände under avbrottet har hämtats. En instruktion vars leverans är oklar ska stämmas av mot servern innan den skickas igen. Beteendet för den valda API-ytan och serverversionen beskrivs i [livscykelrapporten](lifecycle.md).

Den äldre händelseströmmen har ingen återspelningsmarkör; appen behöver kombinera livehändelser med avstämning mot läsbart servertillstånd. Källträdet innehåller också ett nyare experimentellt protokoll med lagrad händelsehistorik och skydd mot identiska upprepade instruktioner. Det är en relevant möjlighet för senare integrationstester, men att en installation svarar på en `/api`-adress bevisar inte att den kör just den nya körmotorn. [Protokolldetektering](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/app/src/utils/server-protocol.ts), [nyare sessionskontrakt](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/groups/session.ts).

Notifieringar är ett separat tillägg: vår rekommendation är att först göra aktiv användning och återkomst till appen korrekt. Att lägga till APNs senare ändrar inte behovet av OpenCode som körmiljö. Det är inte beslutat att vi ska bygga en notistjänst i första versionen. [Apples APNs-dokumentation](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).

## API-versionen måste väljas medvetet

Underlaget använder releasen **v1.18.30**, vars tagg löstes till **3104c1428ec91f809e5ab86631300de41eb6952e**. Releasen innehåller både äldre routes och en ny experimentell `/api/*`-yta; de ska inte blandas som om de vore ett enda oföränderligt kontrakt. Den nya ytan beskrivs uttryckligen som experimentell i källan. [Release](https://github.com/anomalyco/opencode/releases/tag/v1.18.30), [API-definition](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/api.ts).

Den dokumenterade äldre ytan är vår första kandidat. Lägsta stödda OpenCode-version fastställs efter en liten integrationskontroll, inte genom att anta att alla redan installerade versioner beter sig lika. Vi behöver inte stödja varje historisk version från början.

Swift kan tala HTTP direkt. Apples OpenAPI-generator är ett möjligt sätt att få typade anrop, men det är inte ännu verifierat att OpenCodes schema fungerar utan anpassningar; en begränsad handskriven klient är också möjlig. Vi har inte valt dependency eller lägsta iOS-version. [Swift och kompatibilitet](compatibility.md).

## Nästa steg som underlaget motiverar

Vi kan nu utforma appens kärnflöde samtidigt som en senare, avgränsad integrationskontroll prövar de risker som påverkar UI:t. Den kontrollen behöver en disponibel testinstallation och fysisk iPhone; den ingår inte i denna dokument- och källkodsgranskning.

| Kontroll | Vad som ska vara sant |
|---|---|
| Anslutning och projekt | Rätt server, rätt mapp och rätt samtal visas; fel version eller behörighet ger ett begripligt fel |
| Körning och skärmlås | En accepterad instruktion kan fortsätta på värddatorn när telefonen lämnar appen |
| Återkomst | UI visar serverns aktuella historik och status utan saknade eller dubbla meddelanden |
| Väntande beslut | Frågor och godkännanden som kom under frånvaron går att besvara |
| Osäker leverans | Nätavbrott efter ett skickat meddelande leder inte till en oavsiktlig dubbel körning |
| Dator och mobil | Båda kan följa samma session på samma server; ett beslut besvaras inte två gånger |
| Granskning | Bilagor, verktygsresultat och diffar återges korrekt och kan kopplas till rätt instruktion |
| Servern försvinner | Telefonen skiljer bortkoppling från avbruten körning och uppdaterar tillståndet efter återkomst |

## Underlag och begränsning

Tre Luna-agenter granskade funktionella API:er, iOS/livscykel respektive säker anslutning. Huvudagenten granskade versionsval, Swift-alternativ och slutsatserna samt sammanställde detta underlag. Alla tekniska slutsatser i rapporterna har källor eller är markerade som förslag/oprövade antaganden. Vi har inte startat användarens OpenCode, ändrat Tailscale, läst privata sessioner, anropat någon modell eller implementerat appen.

- [Funktionskarta och API-luckor](api.md)
- [iOS, sessioner och återanslutning](lifecycle.md)
- [Säker anslutning och minsta möjliga framtida tillägg](connection.md)
- [Swift, API-versioner och befintliga referensklienter](compatibility.md)
