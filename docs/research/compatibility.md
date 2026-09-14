# Swift and API compatibility

Checked 2026-09-13. This is a research base, not a run integration or a decision about libraries.

## Conclusion

Swift needs no middle layer in TypeScript. We can call OpenCode's HTTP API directly and handle its event stream in the app. The most important technical scoping is which server contract we support; introducing a backend purely for protocol adaptation would move that work into yet another component. A separate service may later be justified by other requirements, e.g. APNs or connection relaying, per the [connection report](connection.md).

## Version base

GitHub's release API reported **v1.18.30**, published 2026-09-09, as the latest release at the time of the check. The tag was resolved via the commits API to **3104c1428ec91f809e5ab86631300de41eb6952e**. The release field `target_commitish` had a different value and is therefore not used as the identity of the source code. [Release](https://github.com/anomalyco/opencode/releases/tag/v1.18.30), [the tag's commit](https://api.github.com/repos/anomalyco/opencode/commits/v1.18.30).

The committed OpenAPI document for the release is OpenAPI 3.1.0 with 162 paths. Its `info.version` is `1.0.0`, which is therefore not the OpenCode program's release version. The document contains both the legacy routes and `/api/*`; presence in the schema is not a promise of stability or that all server variants use the same execution path. [Version-locked schema](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/sdk/openapi.json).

`packages/protocol/src/api.ts` describes the new surface as experimental, version `0.0.1`. The official client's protocol detection tries `/global/health` first and then distinguishes different responses from `/api/health`; a successful health call alone is therefore insufficient to conclude that all desired capabilities exist. [API definition](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/protocol/src/api.ts), [official detection](https://github.com/anomalyco/opencode/blob/3104c1428ec91f809e5ab86631300de41eb6952e/packages/app/src/utils/server-protocol.ts).

**Proposal:** use the documented legacy API surface as the first candidate and verify the core flow against v1.18.30 specifically before deciding the minimum supported version. Keep experimental additions separate. Handle version errors and unknown event types clearly, without mixing two different session models or guessing that a failed write can be resent.

## Swift options

| Option | What we get | What is still our work |
|---|---|---|
| Own limited client with Foundation/URLSession and Codable | Direct control over the API calls and responses the app actually uses | Type models, decoding, errors, SSE, reconnection and version adaptation |
| Apple's Swift OpenAPI Generator and the URLSession transport | Generated calls and types from a version-locked schema | Verify that OpenCode's schema generates correctly; handle events, the app's state and compatibility |

Apple's generator supports OpenAPI 3.1 and can generate client code for iOS. The separate URLSession transport supports streaming on iOS 15 and later. That verifies the technology exists, **not** that OpenCode's complete schema has already been built and tested with the generator. [Generator](https://github.com/apple/swift-openapi-generator), [transport](https://github.com/apple/swift-openapi-urlsession).

No library choice or minimum iOS version is decided. A small later integration check should compare how much work it actually is to generate the types we need versus writing a limited client; we do not need to create a general SDK or an abstraction for other agent products.

## Existing clients to learn from

There is already a public native project, `grapeot/opencode_ios_client`, which describes chat, tool display, file review and Basic Auth. At the time of the check its master resolved to `4af504cad0ae2b12538f5175389e77953f48e9d4`, and the tree contained `Services/APIClient.swift`, `Services/SSEClient.swift` and `AppState+SSE.swift`. This is a relevant reference for a later comparison; we have not built the app or verified its behaviour and security. OpenCode's v1 server password gives extensive installation access and is not separate per-phone permission; see the [security base](connection.md). [Version-locked README](https://github.com/grapeot/opencode_ios_client/blob/4af504cad0ae2b12538f5175389e77953f48e9d4/README.md).

There is also `guitaripod/CodingAgentKit`, whose README describes a Swift client, an event reducer and URLSession-based SSE for OpenCode. It is a possible technical reference, not a chosen dependency or a verified compatible solution for our version. [Project](https://github.com/guitaripod/CodingAgentKit).

## What this base does not prove

No Swift compilation, iPhone/simulator run, connection to the user's server or schema generation has been done. We have not upgraded OpenCode, started processes, changed Tailscale or read the user's conversations and authentication files. The conclusion covers feasible architecture based on current primary sources; practical acceptance remains.
