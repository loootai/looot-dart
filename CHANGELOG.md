# Changelog

## 0.1.0

First release. 2026-11-06.

- One `Looot` client for the looot REST API, built on `package:http`. No `dart:io` in the
  core, so it runs on the Dart VM, Flutter mobile and desktop, and Flutter web.
- Core methods: `catalogOverview`, `publicCatalog`, `publicCatalogItem`, `search`, `inspect`,
  `run`, `runJob`, `getRun`, `listRuns`, `cancelRun`, `runAttempts`, `balance`.
- Extended methods: `discover`, `catalogEndpoints`, `comparePublicCatalog`, `whoami`,
  `listTopUps`, `ledger`, `capabilityRequest`, `downloadMedia`.
- Helpers: `waitForRun` (polls 1 s to 5 s) and `iterRuns` (follows the cursor).
- Typed results that keep the decoded body in `raw`, so a field the gateway adds later is
  still readable.
- `LoootError` for every non-2xx answer, missing token, network error and timeout, with
  `code`, `retryable`, `retryAfterSeconds` and the 402 `topUp` link.
- Retries 429, retryable 503s, network errors and timeouts twice by default with the same
  idempotency key. `maxRetries: 0` turns them off.
- Sends `User-Agent: looot-dart/0.1.0 dart/<version>` and, with `agent`, `X-Looot-Agent`.
