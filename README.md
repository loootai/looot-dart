# looot for Dart and Flutter

[![pub package](https://img.shields.io/pub/v/looot.svg)](https://pub.dev/packages/looot) [![License](https://img.shields.io/github/license/loootai/looot-dart)](LICENSE) [![Docs](https://img.shields.io/badge/docs-docs.looot.ai-12A06A)](https://docs.looot.ai)

The Dart client for the [looot](https://looot.ai) API. looot is one gateway to 300+ data
providers (email find and verify, company enrichment, SERP data, social profiles, web
scraping) with one token and one prepaid balance.

Built on `package:http`. The core has no `dart:io`, so it runs on the Dart VM, Flutter mobile
and desktop, and Flutter web. Dart 3.6 or newer.

## Install

```bash
dart pub add looot       # Flutter: flutter pub add looot
```

Create an API key at [looot.ai](https://looot.ai) (Settings, API keys) and export it:

```bash
export LOOOT_TOKEN=...
```

On the Dart VM and Flutter mobile and desktop, `Looot()` reads `LOOOT_TOKEN`. Flutter web has no
environment, so pass `Looot(token: ...)`. Do not put a token in a public web or app bundle:
call looot from your own server and keep the token there.

## Quickstart

Search, inspect, check the balance, then verify an email. `prefer` lets looot try the next provider on
a miss. This run is paid.

```dart
import 'package:looot/looot.dart';

Future<void> main() async {
  final looot = Looot(); // reads LOOOT_TOKEN
  final found = await looot.search(q: 'verify an email', limit: 3);
  final op = await looot.inspect(found.endpoints.first.endpointId!);
  print('${op.estimatedMaxCost} ${op.inputSchema}');

  final bal = await looot.balance();
  if ((bal.available ?? 0) < 0.05) {
    print('Add credit: ${bal.topUpLink?.url}');
    return;
  }

  final run = await looot.runJob(
    job: 'people.email.verify',
    input: {'email': 'jane.doe@example.com'},
    prefer: Prefer.cheapest,
    wait: 20,
  );
  print('${run.status} ${run.outcome} ${run.result}');
}
```

The full program is in [example/quickstart.dart](example/quickstart.dart). To read an
endpoint's inputs and price before a run, call `looot.inspect(endpointId)`. Browsing the catalog
is free and needs no token: `catalogOverview()` and `publicCatalog()`.

## Read the run, not the HTTP status

A run that failed is not an exception. `run` and `runJob` return it with `status: failed` and
`error` set, even when the gateway answered HTTP 201. A `completed` run can still be a `miss`.

```dart
if (run.error != null) {
  print('${run.error!.code} ${run.error!.retryHint}'); // show retryHint to the user as is
}
```

`run.isSuccess` is true for a completed run with no error.

## Errors

Every non-2xx answer throws a `LoootError`. So do a missing token, a network failure and a
timeout (`status` 0).

```dart
try {
  await looot.run(endpointId: 'icypeas-email-verify', input: {'email': 'jane@example.com'});
} on LoootError catch (e) {
  if (e.code == 'insufficient_balance') {
    print('Add credit: ${e.topUp?.url}'); // then run again with a new key
  } else if (e.retryable) {
    print('Try later, same key: ${e.retryAfterSeconds}');
  } else {
    print('${e.status} ${e.code} ${e.message} ${e.requestId}');
  }
}
```

Fields: `status`, `code`, `message`, `requestId`, `retryable`, `retryAfterSeconds`, `topUp` and the
decoded `body`. The token never appears in an error or in `toString`.

## Idempotency and retries

Every `run` and `runJob` sends an idempotency key. Pass your own, built from your record
(`lead-4821-email`), so a crashed worker replays the first run instead of paying twice. With no
key the SDK sends `sdk-<uuid v4>`.

The client retries 429, the retryable 503 codes, network errors and timeouts up to 2 times with
the same key. It waits `Retry-After` when the gateway sends it (capped at 30 s), else a short
backoff. It never retries other 4xx answers. `maxRetries: 0` turns retries off.

After a failed run, or a 402, run again with a new key. The same key only replays the first
answer.

## Options

```dart
final looot = Looot(
  token: myToken,                          // default: LOOOT_TOKEN
  baseUrl: 'http://localhost:8787',        // default: https://api.looot.ai
  timeout: const Duration(seconds: 90),    // per request, default 75 s
  maxRetries: 0,                           // default 2
  agent: 'my-app',                         // sent as X-Looot-Agent, analytics only
  client: myHttpClient,                    // a package:http Client, for tests or proxies
);
```

`token: ''` means no token, even when `LOOOT_TOKEN` is set. Free routes never send the token.
Call `looot.close()` when you are done if you did not pass your own `client`.

## Methods

| Method | Route | Token scope | Cost |
| --- | --- | --- | --- |
| `catalogOverview()` | `GET /v1/catalog/overview` | none | free |
| `publicCatalog()` | `GET /v1/public-catalog` | none | free |
| `publicCatalogItem(id)` | `GET /v1/public-catalog/{id}` | none | free |
| `comparePublicCatalog(ids)` | `POST /v1/public-catalog/compare` | none | free |
| `search()` | `GET /v1/catalog/search` | `catalog.read` | free |
| `discover(q:)` | `GET /v1/discover` | `catalog.read` | free |
| `catalogEndpoints()` | `GET /v1/catalog/endpoints` | `catalog.read` | free |
| `inspect(endpointId)` | `GET /v1/operations/{id}` | `catalog.read` | free |
| `run(endpointId:, input:)` | `POST /v1/runs` | `runs.execute` | paid |
| `runJob(job:, input:)` | `POST /v1/runs` with `job:<id>` | `runs.execute` | paid |
| `getRun(runId)` | `GET /v1/runs/{id}` | `runs.read` | free |
| `listRuns()` | `GET /v1/runs` | `runs.read` | free |
| `iterRuns()` | `GET /v1/runs`, every page | `runs.read` | free |
| `waitForRun(runId)` | `GET /v1/runs/{id}` until terminal | `runs.read` | free |
| `cancelRun(runId)` | `POST /v1/runs/{id}/cancel` | `runs.execute` | free |
| `runAttempts(runId)` | `GET /v1/runs/{id}/attempts` | `runs.read` | free |
| `balance()` | `GET /v1/balance` | `usage.read` | free |
| `whoami()` | `GET /v1/whoami` | `organizations.read` | free |
| `listTopUps()` | `GET /v1/top-ups` | `usage.read` | free |
| `ledger()` | `GET /v1/ledger` | `usage.read` | free |
| `capabilityRequest(map)` | `POST /v1/capability-requests` | any | free |
| `downloadMedia(path)` | `GET <result.media.downloadPath>` | any | free |

Results are typed classes (`Run`, `Balance`, `SearchResult`, and so on). Each keeps the decoded
body in `raw`, and `result['key']` reads any key, so a field the gateway adds later is still
reachable. Parameters left null are not sent.

`runJob` puts `prefer` into `fallback.prefer`, which turns fallback on. With neither `prefer`
nor `fallback`, a job run does not fall back. Take job ids from `catalogOverview()` or a search
row's `capability`, never guess one.

To top up, show the user `balance().topUpLink.url`. An agent token cannot open a payment.

## Develop

```bash
dart pub get
dart analyze --fatal-infos
dart test
bash scripts/leak-scan.sh .
git config core.hooksPath .githooks   # runs the leak scan before each commit
```

Tests mock HTTP with `MockClient` from `package:http/testing.dart`. No test calls the live API.

## Links

- Docs: https://docs.looot.ai
- API reference: https://docs.looot.ai/reference
- Run errors: https://docs.looot.ai/errors/run-errors
- Agent guide: https://looot.ai/skill.md
- Other SDKs: [looot-js](https://github.com/loootai/looot-js), [looot-python](https://github.com/loootai/looot-python), [looot-go](https://github.com/loootai/looot-go)

## License

MIT. See [LICENSE](LICENSE).
