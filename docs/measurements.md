# Mätningar: anslutning

Alla mätningar körs i simulatorn i OSX-VM:en mot en riktig OpenCode-server över Tailscale (`https://<machine>.<tailnet>.ts.net`, konfigureras i `.env`, se `.env.example`), med serverns lösenord. Appen mäter själv med `URLSessionTaskMetrics` och `os_signpost`, och varje försök loggas med tidsstämpel.

## Definitioner

- **Kall anslutning**: första anslutningen i en process, ny `URLSession`, full DNS/TCP/TLS.
- **Varm anslutning**: efterföljande anslutningar på samma session, keep-alive och återanvänd TLS.
- **Resume**: appen kommer tillbaka till förgrunden och verifierar anslutningen direkt.
- **Reconnect**: tid från att avbrottet upptäckts till att anslutningen är återställd.

## Resultat (2026-09-13)

| Mätning | Resultat |
|---|---|
| Kall anslutning (10 starter) | min 557,1 ms, p50 640,2 ms, p95 795,8 ms, max 854,4 ms |
| Varm anslutning | min 11,8 ms, p50 52,7 ms, p95 103,8 ms, max 147,1 ms |
| Resume från bakgrund | ~16 ms |
| Reconnect (15 nedsläpp) | min 513,7 ms, p50 529,4 ms, max 665,2 ms |
| Lyckade försök | 20/20 (connect), 15/15 (reconnect) |

Kall anslutning domineras av TLS (DNS och TCP är försumbara mot Tailscale). Resume är i praktiken gratis eftersom TCP/TLS återanvänds.

## Budgetar och status

| Scenario | Mål (p50 / p95) | Status |
|---|---|---|
| Kall anslutning | < 1 s / < 2 s | inom mål |
| Varm anslutning | < 100 ms / < 300 ms | inom mål |
| Resume | < 100 ms / < 300 ms | inom mål |
| Avbrottsdetektion | < 2 s | heartbeat 2 s |
| Reconnect efter nåbart igen | < 1 s / < 3 s | inom mål (p50 0,55 s) |

## Så körs mätningen

```sh
doppler run --project conduit --config dev -- scripts/measure.sh
```

Förutsätter `SIMULATOR_UDID`, `XCODE_DERIVED` och `MEASURE_URL` i VM:ens miljö (sätts i `scripts/vm/measure-connect.sh`-anropet), samt lösenord via Doppler (`conduit/dev` för SSH, `opencode-remote/dev` för servern).

## Kvar

Reconnect mäts isolerat som gapet från sista misslyckade försöket till första lyckade, alltså appens egen fördröjning efter att servern är nåbar igen (bunden av backoff‑taket på 0,5 s). Kallstart mäts över flera appstarter, reconnect över flera nedsläpp. Resume är mätt manuellt; att automatisera bakgrund/förgrund är en mindre kvarstående uppgift och påverkar inte arkitekturen.
