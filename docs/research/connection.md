# Native iPhone OpenCode client: secure connection research

Research date: 2026-09-13. Scope: transport, authentication, pairing, and operational footprint for a native SwiftUI client that controls an already-installed OpenCode server. This report does not install, configure, or change any host, Tailscale, or OpenCode state.

## Recommendation

Use Tailscale as the initial private transport. Keep the existing OpenCode server bound to loopback, protect it with its configured `OPENCODE_SERVER_PASSWORD`, and publish only that loopback port through Tailscale Serve over the private tailnet. The iPhone app requires the existing Tailscale iOS app/account for this phase; the native app stores the OpenCode credential in Keychain and talks to the `https://...ts.net` Serve URL with normal `URLSession` HTTPS. Do not use Tailscale Funnel for the initial route and do not add a custom cloud backend merely to make the connection secure.

This gives the full OpenCode API surface to the phone, so the credential must be treated as a high-privilege control credential. OpenCode's documented API includes file access, shell execution, configuration/provider changes, session control, and event streams. A future per-device token layer is therefore useful, but it should be a small host helper and pairing/relay control plane rather than a second implementation of OpenCode semantics.

## Verified current facts

### OpenCode server and authentication

The current OpenCode server documentation describes `opencode serve` as a headless HTTP server with an OpenAPI endpoint. Its defaults are port `4096`, hostname `127.0.0.1`, mDNS disabled, and no extra CORS origins. It documents `OPENCODE_SERVER_PASSWORD` for HTTP Basic Auth; the username defaults to `opencode` and can be overridden with `OPENCODE_SERVER_USERNAME`.

Sources: [OpenCode server docs](https://dev.opencode.ai/docs/server/) and the [v1.18.30 server source](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/opencode/src/server/auth.ts). The tagged source reads only the password and username environment variables, validates that single pair, and emits a `Basic` Authorization header. I found no documented per-device token, pairing, or credential-revocation API in this v1 server surface. The current [v1.18.30 release](https://github.com/anomalyco/opencode/releases/tag/v1.18.30) is the relevant released baseline.

The server's [tagged API documentation](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/web/src/content/docs/server.mdx) lists the API exposed after authentication, including `/file`, `/session`, `/session/:id/shell`, `/config`, `/provider`, `/auth/:id`, and SSE event endpoints. A native client should assume that possession of the OpenCode Basic credential is equivalent to control of the installation.

### Tailscale Serve versus Funnel

Tailscale Serve proxies a local service to devices in the same tailnet. The current command reference documents `tailscale serve --bg 4096` (or an equivalent target) and an HTTPS URL under the device and tailnet `ts.net` names. Serve can proxy a service listening on `http://127.0.0.1:<port>`; it terminates HTTPS at the Tailscale daemon and keeps the service private to the tailnet. Tailscale says that tailnet access-control rules apply to Serve.

Sources: [Serve overview](https://tailscale.com/docs/features/tailscale-serve), [Serve CLI](https://tailscale.com/docs/reference/tailscale-cli/serve), and [Serve examples](https://tailscale.com/docs/reference/examples/serve).

Funnel is a different security boundary: it publishes a service to the public internet. Tailscale's documentation explicitly recommends Serve for tailnet-only sharing and warns that anyone with a Funnel URL can access the exposed service. Funnel also has a public relay and no tailnet-only identity boundary. It is not appropriate for the first connection recipe for an API that can execute shell commands and read project files.

Tailscale HTTPS certificates are publicly visible in Certificate Transparency logs, including the machine name. Avoid sensitive names before enabling the HTTPS certificate feature. Tailscale states that certificate and ACME private keys are generated and stored locally; Tailscale does not see them. Source: [Enabling HTTPS](https://tailscale.com/docs/how-to/set-up-https-certificates).

### iPhone requirements

Tailscale's iOS documentation requires iOS 15 or later, the App Store client, a user-approved VPN configuration, and a login through a supported SSO provider. The app also uses push notifications to alert users about reauthentication and key expiry. Source: [Install Tailscale on iOS](https://tailscale.com/docs/install/ios).

For the native app, use the system URL loading stack and leave ATS enabled. Apple documents ATS as requiring HTTPS and applying TLS/certificate checks; it cautions that loosening ATS reduces security. A valid Tailscale Serve `https://...ts.net` URL should use the normal trust path and should not require `NSAllowsArbitraryLoads` or a self-signed-certificate exception. Source: [NSAppTransportSecurity](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity).

Store the OpenCode username/password, or any future device token/private key, in Keychain. Apple describes Keychain Services as encrypted storage for passwords and cryptographic keys and recommends it instead of app-managed encryption. Source: [Keychain Services](https://developer.apple.com/documentation/security/keychain-services) and [Adding a password to the keychain](https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain).

Local Network privacy is required for direct LAN connections and Bonjour/mDNS discovery. Apple says that outgoing TCP/UDP connections to local-network addresses and local DNS/Bonjour operations require the user permission introduced in iOS 14, with `NSLocalNetworkUsageDescription` and, for Bonjour service types, `NSBonjourServices`. Apple defines the local network around Wi-Fi/Ethernet broadcast-capable interfaces and excludes cellular and VPN from that definition. Therefore a pure Tailscale URL over the phone's VPN is not expected to need the Local Network prompt, but Apple's docs do not certify Tailscale specifically; verify this on a physical iPhone. If LAN fallback or mDNS is added, include the plist keys and permission-denied/retry states. Source: [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

## Initial connection recipe (proposal based on the verified facts)

1. User already has OpenCode installed and running on the host. Run the existing server in its normal project context with a fixed port and a strong password; leave the listener at `127.0.0.1` unless the installation already requires another binding. Do not place the password in a URL, QR payload, logs, analytics, or app preferences.
2. On that same host, publish only the loopback port through `tailscale serve --bg 4096`. Use the resulting private `https://<machine>.<tailnet>.ts.net` URL. Do not use Funnel.
3. In Tailscale grants/ACLs, allow only the intended iPhone/device (or its user identity) to reach the host's Serve endpoint. Keep the host firewall and OpenCode loopback bind in place; tailnet policy is an additional gate, not a substitute for the application password.
4. In SwiftUI, use `URLSession` for HTTPS and Basic Auth. Save credentials in Keychain. Use a single authenticated connection layer for REST, SSE, and any WebSocket endpoint needed by the generated OpenCode SDK. Never implement a certificate delegate that blindly accepts an invalid certificate; Apple recommends default server-trust evaluation in the normal case. Source: [Handling an authentication challenge](https://developer.apple.com/documentation/foundation/handling-an-authentication-challenge) and [Performing manual server trust authentication](https://developer.apple.com/documentation/foundation/performing-manual-server-trust-authentication).
5. On a real iPhone, test with Tailscale connected and disconnected, cellular and Wi-Fi, expired/incorrect password, revoked Tailscale device access, app background/foreground, SSE reconnect, and host shutdown. A failed Tailscale route must not be reported as an OpenCode authentication failure.

No custom backend is needed for this transport. The operational dependencies are the existing OpenCode process, the host's Tailscale client, the user's Tailscale iOS client/account, tailnet policy, and the OpenCode Basic credential.

## Smallest future upgrade without requiring Tailscale on the phone

Secure transport does not require our cloud. A user-managed HTTPS reverse proxy can terminate a public certificate in front of a loopback-bound helper/OpenCode server, and an SSH tunnel can provide a user-managed private path. Tailscale Serve is already the lower-operations private HTTPS option for users who accept the existing Tailscale iOS app requirement. These paths have networking and certificate-management costs, but those costs are independent of whether a hosted OpenCode backend exists.

Per-device pairing and revocation can also be implemented entirely on the host. The smallest such upgrade is a loopback host helper:

- The helper is the only component that knows the OpenCode Basic password and proxies HTTP, SSE, and WebSocket traffic to the loopback OpenCode server.
- A local one-time pairing flow, such as a QR code shown by the helper or an explicit local command, gives the app a short-lived nonce. The app generates a device key pair; the helper stores the public key or a protected token hash and issues a per-device credential.
- The helper gates every request, maps an accepted device credential to OpenCode's single Basic credential, and revokes individual devices locally. OpenCode remains unchanged and cannot be reached around the helper because it stays on loopback.
- Revoking the underlying OpenCode password remains the emergency action for the whole installation because OpenCode v1 has one shared server credential.

This host-only helper is the minimal future security upgrade and does not need a hosted control plane. It still needs a user-managed reachable path, such as Tailscale, HTTPS port forwarding, or SSH, and a pairing ceremony that reaches the host.

A hosted rendezvous service or relay is only a candidate for zero-network-configuration onboarding across NAT, changing home networks, or restrictive firewalls. It is not required for security, pairing, or revocation, and it is not selected for the minimal scope. If later chosen, the backend should initially handle only installation/device identifiers, short-lived pairing state, revocation state, and relay routing; it should not store source, prompts, session transcripts, or provider keys. A relay that merely forwards OpenCode's one Basic password does not provide per-device revocation. End-to-end encrypted relay frames are a deferred design option with additional key rotation, recovery, and debugging work.

Direct and relay paths have different costs:

| Path | What it buys | Main cost |
| --- | --- | --- |
| User-managed HTTPS or SSH | No hosted data path and no service dependency; can support a host-only helper | Port forwarding/NAT, DNS, certificates, or a user-managed tunnel and pairing ceremony |
| Hosted rendezvous/relay (deferred candidate) | Can discover and reach the host behind NAT with little network configuration | Requires our backend and relay; TLS termination could expose traffic unless an end-to-end protocol is added |
| Tailscale Funnel | Phone need not run Tailscale | Public internet exposure; the configured OpenCode/ helper authentication still applies, while anyone can attempt the public URL; unsuitable as the default for this high-privilege API |

The future decision is therefore to defer hosted rendezvous/relay and first evaluate whether host-only pairing plus a user-managed path meets the onboarding requirement. Choose a hosted relay only if avoiding all user network configuration across NAT is a product requirement; that would be a connectivity and operations decision, not a prerequisite for a secure connection.

Push is a separate requirement. Apple documents that remote notifications require the app's device token to be sent to a provider server, which then authenticates to APNs and sends the payload. A secure direct or relay transport cannot by itself provide reliable iOS push while the app is suspended. Source: [Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns) and [Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns).

## Uncertainties and boundaries

- OpenCode's v1.18.30 docs/source establish Basic Auth and the API surface, but do not establish a supported per-device pairing or revocation mechanism. Any pairing UX in a native app is therefore a proposal around OpenCode, not an OpenCode feature.
- Whether iOS presents Local Network permission for a Tailscale-routed `ts.net` URL needs physical-device verification; Apple's classification of VPN traffic supports the expectation but does not name Tailscale.
- Tailscale Serve provides the private transport and tailnet policy gate, but it does not replace OpenCode application authentication. Tailscale's own docs say that a service must be running on the destination device and that access-control rules govern connectivity.
- An end-to-end encrypted relay would reduce relay plaintext exposure but adds protocol, key rotation, recovery, and debugging work. It should not be smuggled into the minimal first release.
