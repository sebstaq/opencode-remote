# Nästa steg

## Nästa: ChatGPT-lik sidebar (reveal via fönster)

Mål: sidebaren öppnas genom att chatten glider åt höger och sidebaren friläggs under den — inte som en overlay över chatten. Referens: ChatGPT på iPhone (iOS 26), se `docs/sidebar-reveal.md`.

Kort: ChatGPT kör chattkolumnen i ett **eget fönster** som förskjuts åt höger och görs till key-window; sidebaren ligger kvar i huvudfönstret. Tangentbordet följer key-window, hamnar inuti chattfönstret och täcker därför inte sidebaren. Se `docs/sidebar-reveal.md` för mekanism, bevis och plan.

1. Spike: minimalt andra fönster (UIWindow) för en textruta + sidebar i huvudfönstret; verifiera på iPhone-simulator (iOS 26.2) att tangentbordet hamnar i chattfönstret.
2. Om spiken håller: bygg om `ChatShell` till två fönster — sidebaren i huvudfönstret (stilla), chatten i ett child-fönster vars frame = skärmen minus sidebarens bredd; key-window och fokus hanteras; draget animerar chattfönstrets frame.
3. Rörelse enligt transitions-skillen: panel open 400 ms / close 350 ms, `cubic-bezier(0.22, 1, 0.36, 1)`, reduce-motion-guard. Ingen resize, bara translation.
4. Fallback om spiken faller: reveal i ett fönster (chatten offset:ad, sidebaren stilla) — tangentbordet blir då fullbredd och sidebarens bottenrad måste ligga ovanför tangentbordet.

## Historik

MVP-omfattningen är låst (`DECISIONS.md`), anslutningen specad (`connection.md`), projektet scaffoldat (`structure.md`) och appen byggd: anslutningslager, Add computer, sessionslista, läsande chatt **och composer med live-streaming, abort samt godkännande/fråge-overlays**. Distans: signerat IPA via Diawi (`scripts/diawi.sh`).
