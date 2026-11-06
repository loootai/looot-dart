import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:looot/looot.dart';
import 'package:test/test.dart';

// A fake token shaped like nothing real, so the leak scan stays clean.
const fakeToken = 'test-token-not-real';

class Recorder {
  final List<http.Request> requests = [];
  final List<http.Response Function(http.Request)> script;
  Recorder(this.script);

  MockClient get client => MockClient((req) async {
        requests.add(req);
        final i = requests.length - 1;
        final fn = script[i < script.length ? i : script.length - 1];
        return fn(req);
      });
}

http.Response json(Object body, [int status = 200, Map<String, String>? h]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json', ...?h});

Looot make(Recorder r,
        {String? token = fakeToken,
        int maxRetries = 2,
        List<Duration>? sleeps}) =>
    Looot(
      token: token,
      client: r.client,
      maxRetries: maxRetries,
      sleep: (d) async => sleeps?.add(d),
    );

void main() {
  group('headers and auth', () {
    test('catalogOverview sends topic, no Authorization, right headers',
        () async {
      final r = Recorder([
        (_) => json({'revision': '1', 'jobs': []})
      ]);
      final out = await make(r).catalogOverview(topic: 'email');
      final req = r.requests.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/v1/catalog/overview');
      expect(req.url.queryParameters, {'topic': 'email'});
      expect(req.headers.containsKey('Authorization'), isFalse);
      expect(req.headers.containsKey('Content-Type'), isFalse);
      expect(req.headers['Accept'], 'application/json');
      expect(
          req.headers['User-Agent'], matches(r'^looot-dart/0\.1\.0 dart/\d'));
      expect(req.headers.containsKey('X-Looot-Agent'), isFalse);
      expect(out.revision, '1');
    });

    test('free routes send no Authorization even with a token', () async {
      final r = Recorder([
        (_) => json({'items': []}),
        (_) => json({'catalogItemId': 'x'}),
        (_) => json({'items': []}),
      ]);
      final c = make(r);
      await c.publicCatalog(q: 'a');
      await c.publicCatalogItem('x');
      await c.comparePublicCatalog(['a', 'b']);
      for (final req in r.requests) {
        expect(req.headers.containsKey('Authorization'), isFalse);
      }
      expect(r.requests[2].method, 'POST');
      expect(r.requests[2].url.path, '/v1/public-catalog/compare');
      expect(jsonDecode(r.requests[2].body), {
        'catalogItemIds': ['a', 'b']
      });
      expect(r.requests[2].headers['Content-Type'], 'application/json');
    });

    test('token routes send Bearer and X-Looot-Agent when set', () async {
      final r = Recorder([
        (_) => json({'available': 1})
      ]);
      final c =
          Looot(token: '  $fakeToken ', client: r.client, agent: 'my-app');
      await c.balance();
      expect(r.requests.single.headers['Authorization'], 'Bearer $fakeToken');
      expect(r.requests.single.headers['X-Looot-Agent'], 'my-app');
    });

    test('agent name is cut at 64 characters', () async {
      final r = Recorder([(_) => json({})]);
      await Looot(token: fakeToken, client: r.client, agent: 'a' * 80)
          .balance();
      expect(r.requests.single.headers['X-Looot-Agent'], 'a' * 64);
    });

    test('missing token raises and sends nothing', () async {
      final r = Recorder([(_) => json({})]);
      for (final t in ['', '   ']) {
        // An explicit blank token means none, even when LOOOT_TOKEN is set.
        final c = Looot(token: t, client: r.client);
        await expectLater(
          c.balance(),
          throwsA(isA<LoootError>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.code, 'code', 'missing_token')
              .having((e) => e.message, 'message',
                  'GET /v1/balance needs a token: set LOOOT_TOKEN or pass token')),
        );
      }
      expect(r.requests, isEmpty);
    });

    test('base url override strips trailing slashes', () async {
      final r = Recorder([(_) => json({})]);
      await Looot(
              token: fakeToken,
              baseUrl: 'http://localhost:8787///',
              client: r.client)
          .balance();
      expect(
          r.requests.single.url.toString(), 'http://localhost:8787/v1/balance');
    });

    test('token never shows in toString', () {
      final c = Looot(token: fakeToken);
      expect(c.toString(), isNot(contains(fakeToken)));
    });
  });

  group('routes and encoding', () {
    test('search maps params, lowercase booleans, drops nulls', () async {
      final r = Recorder([
        (_) => json({
              'query': 'q',
              'total': 1,
              'nextOffset': null,
              'endpoints': [
                {'endpointId': 'e1', 'estimatedPrice': 0.0019, 'extra': 1}
              ]
            })
      ]);
      final out = await make(r).search(
          q: 'verify an email',
          prefer: Prefer.cheapest,
          maxPriceMicros: 5000,
          keyless: true,
          verified: false);
      final req = r.requests.single;
      expect(req.headers['Authorization'], 'Bearer $fakeToken');
      expect(req.url.queryParameters, {
        'q': 'verify an email',
        'prefer': 'cheapest',
        'maxPriceMicros': '5000',
        'keyless': 'true',
        'verified': 'false',
      });
      expect(req.url.query, isNot(contains('limit')));
      expect(out.endpoints.single.endpointId, 'e1');
      expect(out.endpoints.single.raw['extra'], 1);
      expect(out.nextOffset, isNull);
    });

    test('path segments are encoded as one segment', () async {
      final r = Recorder([
        (_) => json({}),
        (_) => json({}),
        (_) => json({}),
        (_) => json({}),
        (_) => json({})
      ]);
      final c = make(r);
      await c.getRun('a/b');
      await c.inspect('job:people.email.find');
      await c.cancelRun('a/b');
      await c.runAttempts('a/b');
      await c.publicCatalogItem('x/y?z');
      expect(r.requests[0].url.path, '/v1/runs/a%2Fb');
      expect(r.requests[1].url.path, '/v1/operations/job%3Apeople.email.find');
      expect(r.requests[2].url.path, '/v1/runs/a%2Fb/cancel');
      expect(r.requests[2].method, 'POST');
      expect(r.requests[2].body, isEmpty);
      expect(r.requests[2].headers.containsKey('Content-Type'), isFalse);
      expect(r.requests[3].url.path, '/v1/runs/a%2Fb/attempts');
      expect(r.requests[4].url.path, '/v1/public-catalog/x%2Fy%3Fz');
    });

    test('every method hits its route', () async {
      final r = Recorder([(_) => json({})]);
      final c = make(r);
      await c.discover(q: 'x');
      await c.catalogEndpoints(facets: true);
      await c.getRun('r1', fields: ['a.b', 'c'], maxItems: 3);
      await c.listRuns(status: 'completed', limit: 5, includeResult: true);
      await c.whoami();
      await c.listTopUps();
      await c.ledger();
      await c.capabilityRequest({'description': 'need X'});
      expect([
        for (final q in r.requests) '${q.method} ${q.url.path}'
      ], [
        'GET /v1/discover',
        'GET /v1/catalog/endpoints',
        'GET /v1/runs/r1',
        'GET /v1/runs',
        'GET /v1/whoami',
        'GET /v1/top-ups',
        'GET /v1/ledger',
        'POST /v1/capability-requests',
      ]);
      expect(r.requests[1].url.queryParameters, {'facets': 'true'});
      expect(r.requests[2].url.queryParameters,
          {'fields': 'a.b,c', 'max_items': '3'});
      expect(r.requests[3].url.queryParameters,
          {'status': 'completed', 'limit': '5', 'includeResult': 'true'});
      expect(r.requests[7].headers['Authorization'], 'Bearer $fakeToken');
    });

    test('downloadMedia needs the token and returns bytes', () async {
      final r = Recorder([
        (_) => http.Response.bytes([1, 2, 3], 200)
      ]);
      final out = await make(r).downloadMedia('/v1/media/abc');
      expect(out, [1, 2, 3]);
      expect(r.requests.single.url.path, '/v1/media/abc');
      expect(r.requests.single.headers['Authorization'], 'Bearer $fakeToken');
    });

    test('iterRuns follows the cursor', () async {
      final r = Recorder([
        (_) => json({
              'runs': [
                {'runId': 'r1'}
              ],
              'nextCursor': 'c1'
            }),
        (_) => json({
              'runs': [
                {'runId': 'r2'}
              ],
              'nextCursor': null
            }),
      ]);
      final ids = await make(r).iterRuns().map((s) => s.runId).toList();
      expect(ids, ['r1', 'r2']);
      expect(r.requests[1].url.queryParameters['cursor'], 'c1');
    });

    test('balance exposes the top-up link', () async {
      final r = Recorder([
        (_) => json({
              'available': 2.5,
              'topUpLink': {
                'checkoutUrl': null,
                'dashboardUrl': 'https://looot.ai/usage?top_up=1'
              }
            })
      ]);
      final b = await make(r).balance();
      expect(b.available, 2.5);
      expect(b.topUpLink!.url, 'https://looot.ai/usage?top_up=1');
    });
  });

  group('runs', () {
    test('runJob posts job id, wait in the query, merges prefer into fallback',
        () async {
      final r = Recorder([
        (_) => json({'runId': 'run_1', 'status': 'completed', 'outcome': 'hit'})
      ]);
      final run = await make(r).runJob(
        job: 'people.email.verify',
        input: {'email': 'jane@example.com'},
        prefer: Prefer.cheapest,
        fallback: const FallbackOptions(maxAttempts: 2),
        wait: 20,
        idempotencyKey: 'k1',
      );
      final req = r.requests.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/v1/runs');
      expect(req.url.queryParameters, {'wait': '20'});
      expect(req.headers['Content-Type'], 'application/json');
      expect(req.headers['Idempotency-Key'], 'k1');
      expect(jsonDecode(req.body), {
        'endpointId': 'job:people.email.verify',
        'input': {'email': 'jane@example.com'},
        'idempotencyKey': 'k1',
        'fallback': {'maxAttempts': 2, 'prefer': 'cheapest'},
      });
      expect(run.outcome, 'hit');
    });

    test(
        'runJob with prefer alone sends fallback.prefer; with nothing sends no fallback',
        () async {
      final r = Recorder([(_) => json({}), (_) => json({}), (_) => json({})]);
      final c = make(r);
      await c.runJob(
          job: 'j', input: {}, prefer: Prefer.fastest, fallback: true);
      await c.runJob(job: 'j', input: {});
      await c.runJob(job: 'j', input: {}, wait: true);
      expect(jsonDecode(r.requests[0].body)['fallback'], {'prefer': 'fastest'});
      expect(jsonDecode(r.requests[1].body).containsKey('fallback'), isFalse);
      expect(r.requests[1].url.query, isEmpty);
      expect(r.requests[2].url.queryParameters, {'wait': 'true'});
    });

    test('run keeps an explicit fallback map and generates an sdk- key',
        () async {
      final r = Recorder([
        (_) => json({'runId': 'run_1'})
      ]);
      await make(r).run(
        endpointId: 'icypeas-email-verify',
        input: {'email': 'jane@example.com'},
        fallback: {'maxAttempts': 2, 'maxCostUsd': 0.05},
        output: {'pick': 'x'},
      );
      final body = jsonDecode(r.requests.single.body) as Map;
      expect(body['fallback'], {'maxAttempts': 2, 'maxCostUsd': 0.05});
      expect(body['output'], {'pick': 'x'});
      expect(
          body['idempotencyKey'],
          matches(RegExp(
              r'^sdk-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(
          r.requests.single.headers['Idempotency-Key'], body['idempotencyKey']);
    });

    test('a 201 failed run comes back as a run, not an error', () async {
      final r = Recorder([
        (_) => json({
              'runId': 'run_9',
              'status': 'failed',
              'error': {
                'code': 'validation_error',
                'message': 'bad',
                'retryable': false,
                'retryHint': 'Fix the input.'
              },
              'result': {'code': 'needs_input'}
            }, 201)
      ]);
      final run = await make(r).run(endpointId: 'e', input: {});
      expect(run.status, 'failed');
      expect(run.isSuccess, isFalse);
      expect(run.isTerminal, isTrue);
      expect(run.error!.code, 'validation_error');
      expect(run.error!.retryHint, 'Fix the input.');
    });

    test('run exposes route, nextSteps and keeps unknown keys', () async {
      final r = Recorder([
        (_) => json({
              'runId': 'run_1',
              'status': 'completed',
              'actualCost': 0.0019,
              'pricing': {'finalChargeMicros': 1900},
              'route': {
                'servedBy': 'e1',
                'capped': false,
                'attempts': [
                  {'n': 1, 'endpointId': 'e1', 'ms': 380}
                ]
              },
              'nextSteps': [
                {'suggestionId': 's1'}
              ],
              'brandNewField': 7,
            })
      ]);
      final run = await make(r).run(endpointId: 'e', input: {});
      expect(run.isSuccess, isTrue);
      expect(run.finalChargeMicros, 1900);
      expect(run.route!.servedBy, 'e1');
      expect(run.route!.attempts.single.ms, 380);
      expect(run.nextSteps.single['suggestionId'], 's1');
      expect(run['brandNewField'], 7);
    });

    test('waitForRun polls until terminal', () async {
      final r = Recorder([
        (_) => json({'runId': 'r', 'status': 'queued'}),
        (_) => json({'runId': 'r', 'status': 'running'}),
        (_) => json({'runId': 'r', 'status': 'completed'}),
      ]);
      final sleeps = <Duration>[];
      final run = await make(r, sleeps: sleeps).waitForRun('r');
      expect(run.status, 'completed');
      expect(r.requests, hasLength(3));
      expect(sleeps,
          [const Duration(seconds: 1), const Duration(milliseconds: 1500)]);
    });
  });

  group('errors', () {
    test('402 maps to LoootError with code, requestId and topUp', () async {
      final r = Recorder([
        (_) => json({
              'error': {
                'code': 'insufficient_balance',
                'message': 'Add credit.',
                'requestId': 'req_1'
              },
              'topUp': {
                'checkoutUrl': 'https://pay.example.com/s',
                'dashboardUrl': 'https://looot.ai/usage'
              }
            }, 402)
      ]);
      await expectLater(
        make(r).run(endpointId: 'e', input: {}),
        throwsA(isA<LoootError>()
            .having((e) => e.status, 'status', 402)
            .having((e) => e.code, 'code', 'insufficient_balance')
            .having((e) => e.requestId, 'requestId', 'req_1')
            .having((e) => e.retryable, 'retryable', isFalse)
            .having(
                (e) => e.topUp!.url, 'topUp.url', 'https://pay.example.com/s')
            .having((e) => (e.body as Map<String, dynamic>)['error'], 'body',
                isA<Map<String, dynamic>>())),
      );
      expect(r.requests, hasLength(1));
    });

    test('non-JSON body falls back to http_<status> and the request id header',
        () async {
      final r = Recorder([
        (_) => http.Response('<html>', 502, headers: {'x-request-id': 'req_h'})
      ]);
      try {
        await make(r, maxRetries: 0).balance();
        fail('expected LoootError');
      } on LoootError catch (e) {
        expect(e.code, 'http_502');
        expect(e.message, 'GET /v1/balance failed with HTTP 502');
        expect(e.requestId, 'req_h');
        expect(e.body, '<html>');
        expect(e.toString(), isNot(contains(fakeToken)));
      }
    });

    test('network error and timeout become LoootError with status 0', () async {
      final c = Looot(
        token: fakeToken,
        maxRetries: 0,
        client: MockClient(
            (_) async => throw http.ClientException('connection refused')),
      );
      await expectLater(
          c.balance(),
          throwsA(isA<LoootError>()
              .having((e) => e.status, 'status', 0)
              .having((e) => e.code, 'code', 'network_error')
              .having((e) => e.retryable, 'retryable', isTrue)));
      final slow = Looot(
        token: fakeToken,
        maxRetries: 0,
        timeout: const Duration(milliseconds: 20),
        client: MockClient(
            (_) => Future.delayed(const Duration(seconds: 2), () => json({}))),
      );
      await expectLater(slow.balance(),
          throwsA(isA<LoootError>().having((e) => e.code, 'code', 'timeout')));
    });
  });

  group('retries', () {
    test('429 retries with the same idempotency key and waits retry-after',
        () async {
      final r = Recorder([
        (_) => json(
            {
              'error': {'code': 'run_rate_limited', 'message': 'slow'}
            },
            429,
            {'retry-after': '2'}),
        (_) => json({
              'error': {'code': 'run_rate_limited', 'message': 'slow'},
              'retryAfterSeconds': 100
            }, 429),
        (_) => json({'runId': 'run_1', 'status': 'completed'}),
      ]);
      final sleeps = <Duration>[];
      final run =
          await make(r, sleeps: sleeps).run(endpointId: 'e', input: {'a': 1});
      expect(run.runId, 'run_1');
      expect(r.requests, hasLength(3));
      final keys = {
        for (final q in r.requests) jsonDecode(q.body)['idempotencyKey']
      };
      expect(keys, hasLength(1));
      expect(keys.single, startsWith('sdk-'));
      expect(r.requests.map((q) => q.headers['Idempotency-Key']).toSet(), keys);
      expect(sleeps, [const Duration(seconds: 2), const Duration(seconds: 30)]);
    });

    test('retryable 503 retries, gives up after 2 retries', () async {
      final r = Recorder([
        (_) => json({
              'error': {'code': 'catalog_loading', 'message': 'x'}
            }, 503)
      ]);
      await expectLater(
          make(r).search(q: 'x'),
          throwsA(isA<LoootError>()
              .having((e) => e.retryable, 'retryable', isTrue)));
      expect(r.requests, hasLength(3));
    });

    test('network errors retry on GET and on runs with a key', () async {
      var n = 0;
      final c = Looot(
        token: fakeToken,
        sleep: (_) async {},
        client: MockClient((_) async {
          if (n++ == 0) throw http.ClientException('reset');
          return json({'runId': 'r'});
        }),
      );
      final run = await c.run(endpointId: 'e', input: {});
      expect(run.runId, 'r');
      expect(n, 2);
    });

    test('non-retryable answers are not retried', () async {
      for (final spec in [
        [400, 'validation_error'],
        [401, 'unauthorized'],
        [402, 'insufficient_balance'],
        [403, 'forbidden'],
        [404, 'not_found'],
        [409, 'idempotency_conflict'],
        [503, 'billing_unavailable'],
        [500, 'internal_error'],
      ]) {
        final r = Recorder([
          (_) => json({
                'error': {'code': spec[1], 'message': 'x'}
              }, spec[0] as int)
        ]);
        await expectLater(make(r).run(endpointId: 'e', input: {}),
            throwsA(isA<LoootError>()));
        expect(r.requests, hasLength(1), reason: '${spec[0]} ${spec[1]}');
      }
    });

    test('maxRetries 0 turns retries off', () async {
      final r = Recorder([
        (_) => json({
              'error': {'code': 'run_rate_limited', 'message': 'x'}
            }, 429)
      ]);
      await expectLater(
          make(r, maxRetries: 0).balance(), throwsA(isA<LoootError>()));
      expect(r.requests, hasLength(1));
    });
  });
}
