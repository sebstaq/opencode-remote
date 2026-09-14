# Sidebar reveal (ChatGPT-lik)

Status: **spike körd 2026-09-14 — child-fönster räcker inte.** Referens: ChatGPT på
iPhone (iOS 26), skärmbild `IMG_2354.png`.

## Referensmaterial

- `docs/reference/chatgpt-sidebar-flow.mp4` — skärminspelning av hela flödet (19,7 s,
  1180×2556, 60 fps).
- `docs/reference/frames/flow-0*.png` — kontaktkopior, 4 fps.
- `docs/reference/frames/sidebar-open-keyboard.png` + `-zoom.png` — det avgörande
  läget: sidebaren öppen, chatten som smal kolumn till höger, tangentbordet synligt.

Vad filmen visar: hela chattpanelen — composer **och tangentbordet** — är förskjuten åt
höger och klippt av skärmkanten; vi ser bara dess vänstra ~25 %. Sidebaren står still
och dess bottenrad (Chat-pillen + kuggen) är oskymd. Chatten har rundad nedre
vänsterkant. Detta är ChatGPTs nativa app på iPhone (iOS 26).

## Tangentbordet: mätt och uttömt (2026-09-14)

Flera försök, alla med skärmdump som bevis:

1. Chatt i child-`UIWindow` med `frame.x = 330` → tangentbordet rapporterar
   `screen x=0 w=393`, dvs full bredd. Det följer scenen, inte key-window.
2. Scenen kan inte göras icke-fullskärm på iPhone: windowed apps är iPadOS 26-only,
   och `UIRequiresFullScreen` ignoreras för iOS-appar.
3. Tangentbordets fönster går inte att nå: appens scen exponerar bara
   `UIWindow` (x0), `UIWindow` (x330) och `UITextEffectsWindow` (L1.0) — ingen
   `UIRemoteKeyboardWindow`. En transform på `UITextEffectsWindow` tog (x330 i
   diagnostiken) men flyttade inte tangentbordet: det renderas utanför appens
   process.

Slutsats: systemtangentbordet kan inte flyttas från appen på iPhone/iOS 26. Enda
vägen till referensens beteende är ett **eget input-tangentbord** (`inputView`) som
ritas inuti chattpanelen — då äger vi positionen helt. Det är ett stort bygge och
förlorar systemfunktioner (diktering, layouter). Alternativet är att acceptera
fullbredd och lägga sidebarens bottenrad ovanför tangentbordet.

## Spike-resultat (2026-09-14)

Körde `OPENCODE_UI_SPIKE=window` (`App/Debug/SidebarWindowSpike.swift`): sidebaren i
huvudfönstret, chatten i ett child-`UIWindow` med `frame.x = 330`, på iPhone-simulator
iOS 26.2 (w1).

- **Chattfönstret hamnar rätt**: kolumnen ligger korrekt förskjuten till höger om
  sidebaren, med rundade vänsterhörn.
- **Tangentbordet följde inte**: det är fortfarande fullbredd och täcker sidebarens
  nedre del. Det följer **scenen**, inte den key-window vi skapade.

Slutsats: ett child-fönster med insatt frame är inte mekanismen på iPhone. Nästa
hypotes är att **scenen själv** måste vara icke-fullskärm (windowed app / requestad
scene-geometry), vilket ChatGPT i så fall använder. Om iOS 26 inte tillåter det på
iPhone är referensen byggd med ett eget input-tangentbord, och då är den praktiska
fallbacken single-window-reveal med sidebarens bottenrad ovanför tangentbordet.

## Målet

Sidebaren ska inte läggas över chatten. När man drar fram den ska **chatten glida åt
höger** och sidebaren friläggas under den — sidebaren står still (som om den låg under
chatten), chatten är ett klippt, rundat kort med skugga, och **tangentbordet följer
chatten** så att det inte täcker sidebaren.

## Varför det fungerar (mekanismen)

Tangentbordet positioneras relativt **den key-window som har fokus**, inte skärmen:

- Apples dokumentation: tangentbordets frame ligger i skärmens koordinatsystem och
  skiljer sig när appen inte är i fullskärm (Split View, Slide Over, Stage Manager);
  keyboard layout guide är "sized for what part of the keyboard is over your app's
  window" när appen inte är ensam på skärmen.
- Apple Developer Forums, *"Chaotic keyboard frame notification in windowed app in
  iOS 26"* (sep 2025): tangentbordets frame rapporterar negativt `origin.x` (t.ex.
  −247) och ibland ett **positivt** `origin.x` — "as if the keyboard starts from the
  middle of the screen". Det är exakt referensens beteende.

Slutsats: ChatGPT kör chattkolumnen i ett eget fönster som förskjuts åt höger och görs
till key-window. Sidebaren ligger kvar i huvudfönstret. Därför hamnar tangentbordet
inuti chattfönstret och täcker inte sidebaren.

## Plan

1. **Spike**: minimalt andra fönster (UIWindow) med en textruta, sidebar i
   huvudfönstret, på iPhone-simulator (iOS 26.2). Verifiera att tangentbordet hamnar i
   chattfönstret och att sidobaren är oskymd.
2. Om spiken håller: bygg om `ChatShell`: sidebaren i huvudfönstret (stilla), chatten i
   ett child-fönster vars frame = skärmen minus sidebarens bredd. Hantera key-window
   och fokus. Draget animerar chattfönstrets frame/transform.
3. Rörelse enligt `transitions-dev`/`transitions-polish`: panel open 400 ms, close
   350 ms, `cubic-bezier(0.22, 1, 0.36, 1)` (`--ease-smooth-out`), reduce-motion-guard.
   Ingen resize — bara translation, så scrollposition och composerbredd bevaras.
4. Fallback om spiken faller: reveal i ett fönster (chatten `offset(x:)`, sidebaren
   stilla). Tangentbordet blir då fullbredd och sidebarens bottenrad måste ligga ovanför
   tangentbordet i stället.

## Risker

- iOS 26:s keyboard-frame i windowed mode är rapporterad som strulig (negativ x, ibland
  höjd 0). Får inte bli en förutsättning för vår layout.
- UIKit-fönsterlager under SwiftUI: key-window och fokus, plus UI-tester över två
  fönster.
- Nuvarande UI-tester antar ett fönster och att sidebaren bara finns när den är öppen.

## Förutsättning: mjukvarutangentbordet i simulatorn

Verifierat 2026-09-14. Tangentbordet syns bara i **GUI-användarens** Simulator (här
`w1`), eftersom `com.apple.iphonesimulator` är användarens plist. Recept:

```bash
ssh w1@localhost \
  'plutil -replace ConnectHardwareKeyboard -bool NO \
     ~/Library/Preferences/com.apple.iphonesimulator.plist'
```

Per enhet: `DevicePreferences.<UDID>.ConnectHardwareKeyboard`. Verifiera sedan med
`defaults read com.apple.iphonesimulator ConnectHardwareKeyboard` (ska vara `0`), boota
enheten i w1:s Simulator, fokusera ett textfält — mjukvarutangentbordet visas.
