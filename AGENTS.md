# Projektets arbetsregler

## Inriktning

Vi bygger en native iPhone-klient i Swift/SwiftUI för en befintlig OpenCode-installation. Full agentanvändning och ett bra mobilt gränssnitt är målet. Tailscale är accepterat initialt och egen backend ska bara tillkomma när ett konkret krav motiverar den.

## Dokumentation

- Läs `README.md`, `docs/DECISIONS.md` och `docs/NEXT_STEPS.md` före nya produkt- eller arkitekturbeslut.
- `docs/DECISIONS.md` skiljer fastställda beslut från förslag och öppna frågor.
- `docs/research/` är det daterade researchunderlaget med primärkällor. Källkodsfynd är inte bevis för en körd integration.
- Dokumentera nya beslut och testresultat där de hör hemma. Flytta inte ett förslag till beslutat utan stöd i användarens instruktioner.

## Implementation och verifiering

Repo:t börjar som dokumentation; ingen app, Xcode-konfiguration eller iPhone-verifiering finns ännu. Sätt upp en normal Swift/Xcode-projektstruktur med relevanta bygg- och testkommandon innan funktioner implementeras. Inför inte en agentmotor, egen konversationsdatabas eller ett generellt mellanlager utan ett verifierat behov.

Verifiera vilket OpenCode-runtime/API som faktiskt stöds. Blanda inte äldre API-routes med det experimentella V2-kontraktet. Behåll servern som källa för samtal och körstatus; skilj frånkoppling från avbruten körning.

## Motion och transitions

- När transitions eller animationer är aktuella (vybyten, modaler, dropdowns, statusbyten, listöppningar): använd den incheckade skillen i `.agents/skills/transitions-dev` (källa: https://transitions.dev/skill), och håll durations och rörelse enligt dess skala. `.agents/skills/transitions-polish` används för att aligna motion vi redan har.
- Skillen är webborienterad (CSS/React). I SwiftUI översätter vi principerna och token‑skalan, inte koden rakt av.

## UI-paritet och diff

- När användaren ber om att jämföra eller fixa gränssnittet mot designen: kör `scripts/ui-diff.sh` och rapportera SSIM‑talet plus overlayen. Verktyget bygger appen, tar en skärmbild på simulatorn och renderar wireframen i WKWebView på VM:en, så fonter och mått blir 1:1 jämförbara.
- Referensen är alltid `docs/wireframes/index.html`, renderad av verktyget (`scripts/ui/render-wireframe.swift`). Använd aldrig andra skärmbilder eller tidigare inklistrade bilder som referens.
- Diffen mäter bara designen: sidbaren matas med wireframens exempelinnehåll via DEBUG‑fixturet `OPENCODE_UI_FIXTURE=wireframe` (`SidebarFixtureView`). Rör inte fixturens innehåll när du justerar designen.
- Acceptera bara avvikelser som är native iOS‑konvention eller miljö (t.ex. hemindikator, rundade hörn, statusradens innehåll), och håll dem få. Justera SwiftUI‑måtten mot wireframens CSS‑mått, men lita på vad WebKit faktiskt renderar (t.ex. radhöjd) snarare än DOM‑tal.
- Mjukvarutangentbordet syns i simulatorn bara i GUI‑användarens Simulator (`w1`) och kräver `ConnectHardwareKeyboard=0` i `~/Library/Preferences/com.apple.iphonesimulator.plist` (`plutil -replace ConnectHardwareKeyboard -bool NO …`, per enhet `DevicePreferences.<UDID>.ConnectHardwareKeyboard`). Headless `simctl` som annan användare visar inget tangentbord. Se `docs/sidebar-reveal.md`.

## Arbetsflöde

- Prefixa shellkommandon med `rtk`.
- Arbeta på en separat branch och publicera färdiga ändringar via en review-klar pull request.
- Ändra inte användarens OpenCode-, nätverks- eller Tailscale-konfiguration som en följd av en dokumentationsuppgift.
- Lägg aldrig autentiseringsuppgifter, privata samtal, verkliga sessionsidentifierare eller APNs-nycklar i repo, loggar eller testfixturer.
- Håll rapporteringen kort och skilj tydligt mellan genomförd verifiering och planerade kontroller.
