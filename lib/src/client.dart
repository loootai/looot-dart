import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'env_stub.dart' if (dart.library.io) 'env_io.dart';
import 'errors.dart';
import 'types.dart';
import 'version.dart';

/// The default API address.
const String defaultBaseUrl = 'https://api.looot.ai';

const _retryable503 = {
  'catalog_loading',
  'storage_busy',
  'storage_uncertain',
  'runtime_bridge_timeout',
};

/// Client for the looot REST API.
///
/// The token comes from [token], else the `LOOOT_TOKEN` environment variable on the Dart VM
/// and Flutter mobile and desktop. On Flutter web there is no environment, so pass [token].
/// Never ship a token inside a public web or app bundle.
class Looot {
  /// Creates a client.
  ///
  /// [client] is the `package:http` client to use; pass a `MockClient` in tests.
  /// [maxRetries] counts retries after the first try for 429, retryable 503 codes, network
  /// errors and timeouts. Retries reuse the same idempotency key. Set 0 to turn them off.
  /// [agent] is sent as `X-Looot-Agent` (64 characters at most) for usage analytics only.
  Looot({
    String? token,
    String baseUrl = defaultBaseUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 75),
    int maxRetries = 2,
    String? agent,
    Future<void> Function(Duration)? sleep,
  })  : _token = _clean(token ?? readEnv('LOOOT_TOKEN')),
        _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client(),
        _ownsClient = client == null,
        _timeout = timeout,
        _maxRetries = maxRetries,
        _agent = agent,
        _sleep = sleep ?? Future<void>.delayed;

  final String? _token;
  final String _baseUrl;
  final http.Client _http;
  final bool _ownsClient;
  final Duration _timeout;
  final int _maxRetries;
  final String? _agent;
  final Future<void> Function(Duration) _sleep;

  static String? _clean(String? t) {
    final v = t?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Closes the HTTP client when this object created it.
  void close() {
    if (_ownsClient) _http.close();
  }

  @override
  String toString() => 'Looot(baseUrl: $_baseUrl)';

  // ---------------------------------------------------------------- free routes

  /// `GET /v1/catalog/overview`. Free, no token. [depth] is `summary`, `platforms`, `jobs`
  /// or `full`.
  Future<CatalogOverview> catalogOverview({
    String? depth,
    String? category,
    String? platform,
    String? topic,
  }) async =>
      CatalogOverview(await _get(
          '/v1/catalog/overview',
          {
            'depth': depth,
            'category': category,
            'platform': platform,
            'topic': topic,
          },
          auth: false));

  /// `GET /v1/public-catalog`. Free, no token. [capability] uses underscores:
  /// `people_email_verify`.
  Future<PublicCatalogPage> publicCatalog({
    String? q,
    String? text,
    String? capability,
    String? category,
    String? provider,
    String? operationId,
    int? limit,
    String? cursor,
  }) async =>
      PublicCatalogPage(await _get(
          '/v1/public-catalog',
          {
            'q': q,
            'text': text,
            'capability': capability,
            'category': category,
            'provider': provider,
            'operationId': operationId,
            'limit': limit,
            'cursor': cursor,
          },
          auth: false));

  /// `GET /v1/public-catalog/{catalogItemId}`. Free, no token.
  Future<PublicCatalogItem> publicCatalogItem(String catalogItemId) async =>
      PublicCatalogItem(await _get(
          '/v1/public-catalog/${_seg(catalogItemId)}', const {},
          auth: false));

  /// `POST /v1/public-catalog/compare`. Free, no token. Takes 2 to 20 ids.
  Future<JsonResult> comparePublicCatalog(List<String> catalogItemIds) async =>
      JsonResult(await _send('POST', '/v1/public-catalog/compare', const {},
          body: {'catalogItemIds': catalogItemIds}, auth: false));

  // ------------------------------------------------------------ catalog (token)

  /// `GET /v1/catalog/search`. Free, needs `catalog.read`. [capability] is a job id with
  /// dots, `people.email.find`.
  Future<SearchResult> search({
    String? q,
    int? limit,
    int? offset,
    String? category,
    String? platform,
    String? provider,
    String? capability,
    bool? keyless,
    bool? verified,
    bool? mock,
    int? maxPriceMicros,
    Prefer? prefer,
  }) async =>
      SearchResult(await _get('/v1/catalog/search', {
        'q': q,
        'limit': limit,
        'offset': offset,
        'category': category,
        'platform': platform,
        'provider': provider,
        'capability': capability,
        'keyless': keyless,
        'verified': verified,
        'mock': mock,
        'maxPriceMicros': maxPriceMicros,
        'prefer': prefer?.name,
      }));

  /// `GET /v1/discover`. Up to 5 candidates plus `meta`. Needs `catalog.read`.
  Future<JsonResult> discover(
          {required String q, int? limit, Prefer? prefer}) async =>
      JsonResult(await _get(
          '/v1/discover', {'q': q, 'limit': limit, 'prefer': prefer?.name}));

  /// `GET /v1/catalog/endpoints`. Cursor paged listing. Needs `catalog.read`.
  Future<JsonResult> catalogEndpoints({
    String? q,
    String? category,
    String? provider,
    String? capability,
    int? limit,
    String? cursor,
    bool? facets,
  }) async =>
      JsonResult(await _get('/v1/catalog/endpoints', {
        'q': q,
        'category': category,
        'provider': provider,
        'capability': capability,
        'limit': limit,
        'cursor': cursor,
        'facets': facets,
      }));

  /// `GET /v1/operations/{endpointId}`. Takes an endpoint id, not `job:<id>`.
  Future<Operation> inspect(String endpointId) async =>
      Operation(await _get('/v1/operations/${_seg(endpointId)}', const {}));

  // ----------------------------------------------------------------------- runs

  /// `POST /v1/runs`. Paid. Needs `runs.execute`.
  ///
  /// [fallback] is `true`, a [FallbackOptions] or a map. [wait] is seconds (0 to 60) or
  /// `true` for the default 20. Without [idempotencyKey] the SDK sends `sdk-<uuid v4>`;
  /// build your own from your record (`lead-4821-email`) so a crashed worker replays
  /// instead of paying twice. A run that failed before dispatch comes back as a [Run], not
  /// an exception.
  Future<Run> run({
    required String endpointId,
    required Map<String, Object?> input,
    Object? fallback,
    Object? wait,
    String? idempotencyKey,
    Map<String, Object?>? output,
  }) async {
    final key = idempotencyKey ?? 'sdk-${_uuid4()}';
    final body = <String, Object?>{
      'endpointId': endpointId,
      'input': input,
      'idempotencyKey': key,
      if (fallback != null) 'fallback': _fallbackJson(fallback),
      if (output != null) 'output': output,
    };
    return Run(await _send('POST', '/v1/runs', {'wait': _wait(wait)},
        body: body, extraHeaders: {'Idempotency-Key': key}));
  }

  /// `POST /v1/runs` with `endpointId: "job:<job>"`. Paid.
  ///
  /// [prefer] goes into `fallback.prefer`, which turns fallback on. With neither [prefer]
  /// nor [fallback], a job run does not fall back. Take job ids from [catalogOverview] or a
  /// search row's `capability`.
  Future<Run> runJob({
    required String job,
    required Map<String, Object?> input,
    Prefer? prefer,
    Object? fallback,
    Object? wait,
    String? idempotencyKey,
    Map<String, Object?>? output,
  }) {
    Object? fb = fallback;
    if (prefer != null) {
      final base = fallback == null || fallback == true
          ? <String, Object?>{}
          : _fallbackJson(fallback) as Map<String, Object?>;
      fb = {...base, 'prefer': prefer.name};
    }
    return run(
      endpointId: 'job:$job',
      input: input,
      fallback: fb,
      wait: wait,
      idempotencyKey: idempotencyKey,
      output: output,
    );
  }

  /// `GET /v1/runs/{runId}`. [fields] keeps only those dotted paths of `result`;
  /// [maxItems] caps every list (1 to 10000).
  Future<Run> getRun(String runId,
          {List<String>? fields, int? maxItems}) async =>
      Run(await _get('/v1/runs/${_seg(runId)}', {
        'fields': fields?.join(','),
        'max_items': maxItems,
      }));

  /// `GET /v1/runs`, newest first. Needs `runs.read`.
  Future<RunList> listRuns({
    String? status,
    String? capability,
    int? limit,
    String? cursor,
    bool? includeResult,
  }) async =>
      RunList(await _get('/v1/runs', {
        'status': status,
        'capability': capability,
        'limit': limit,
        'cursor': cursor,
        'includeResult': includeResult,
      }));

  /// Every run matching the filters, following `nextCursor` until it is null.
  Stream<RunSummary> iterRuns(
      {String? status, String? capability, int? limit}) async* {
    String? cursor;
    do {
      final page = await listRuns(
          status: status, capability: capability, limit: limit, cursor: cursor);
      for (final r in page.runs) {
        yield r;
      }
      cursor = page.nextCursor;
    } while (cursor != null);
  }

  /// `POST /v1/runs/{runId}/cancel`. A settled run comes back unchanged.
  Future<Run> cancelRun(String runId) async =>
      Run(await _send('POST', '/v1/runs/${_seg(runId)}/cancel', const {}));

  /// `GET /v1/runs/{runId}/attempts`.
  Future<RunAttempts> runAttempts(String runId) async =>
      RunAttempts(await _get('/v1/runs/${_seg(runId)}/attempts', const {}));

  /// Polls [getRun] until the run reaches a terminal status, starting at [interval]
  /// (default 1 s) and backing off to 5 s. Throws [LoootError] with code `timeout` when
  /// [timeout] (default 120 s) passes first.
  Future<Run> waitForRun(
    String runId, {
    Duration timeout = const Duration(seconds: 120),
    Duration interval = const Duration(seconds: 1),
  }) async {
    final started = DateTime.now();
    var wait = interval;
    while (true) {
      final r = await getRun(runId);
      if (r.isTerminal) return r;
      if (DateTime.now().difference(started) + wait > timeout) {
        throw LoootError(
          status: 0,
          code: 'timeout',
          message:
              'Run $runId is still ${r.status} after ${timeout.inSeconds} s',
          retryable: true,
        );
      }
      await _sleep(wait);
      wait = Duration(milliseconds: min(5000, (wait.inMilliseconds * 3) ~/ 2));
    }
  }

  // ---------------------------------------------------------------- usage, misc

  /// `GET /v1/balance`. Needs `usage.read`. To top up, show `topUpLink.url`.
  Future<Balance> balance() async =>
      Balance(await _get('/v1/balance', const {}));

  /// `GET /v1/whoami`. Needs `organizations.read`.
  Future<JsonResult> whoami() async =>
      JsonResult(await _get('/v1/whoami', const {}));

  /// `GET /v1/top-ups`. Needs `usage.read`.
  Future<JsonResult> listTopUps() async =>
      JsonResult(await _get('/v1/top-ups', const {}));

  /// `GET /v1/ledger`. Needs `usage.read`.
  Future<JsonResult> ledger({int? limit, String? cursor}) async =>
      JsonResult(await _get('/v1/ledger', {'limit': limit, 'cursor': cursor}));

  /// `POST /v1/capability-requests`. Ask for a missing provider or job.
  Future<JsonResult> capabilityRequest(Map<String, Object?> request) async =>
      JsonResult(await _send('POST', '/v1/capability-requests', const {},
          body: request));

  /// Downloads a file from a run whose `result.media.downloadPath` is set.
  Future<Uint8List> downloadMedia(String downloadPath) async {
    final path = downloadPath.startsWith(_baseUrl)
        ? downloadPath.substring(_baseUrl.length)
        : downloadPath.startsWith('/')
            ? downloadPath
            : '/$downloadPath';
    final res = await _exec('GET', path, const {}, auth: true, accept: '*/*');
    return res.bodyBytes;
  }

  // -------------------------------------------------------------------- plumbing

  Future<Map<String, dynamic>> _get(String path, Map<String, Object?> query,
          {bool auth = true}) =>
      _send('GET', path, query, auth: auth);

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, Object?> query, {
    Object? body,
    bool auth = true,
    Map<String, String> extraHeaders = const {},
  }) async {
    final res = await _exec(method, path, query,
        body: body, auth: auth, extraHeaders: extraHeaders);
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (text.isEmpty) return <String, dynamic>{};
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw LoootError(
        status: res.statusCode,
        code: 'invalid_response',
        message:
            '$method $path answered HTTP ${res.statusCode} with a body that is not JSON',
        body: text,
      );
    }
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{'data': decoded};
  }

  Future<http.Response> _exec(
    String method,
    String path,
    Map<String, Object?> query, {
    Object? body,
    bool auth = true,
    String accept = 'application/json',
    Map<String, String> extraHeaders = const {},
  }) async {
    final token = auth ? _token : null;
    final agent = _agent;
    final ua = runtimeUserAgent();
    if (auth && token == null) {
      throw LoootError(
        status: 401,
        code: 'missing_token',
        message: '$method $path needs a token: set LOOOT_TOKEN or pass token',
      );
    }
    final uri = Uri.parse('$_baseUrl$path${_queryString(query)}');
    final headers = <String, String>{
      'Accept': accept,
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (ua != null) 'User-Agent': 'looot-dart/$version $ua',
      if (agent != null) 'X-Looot-Agent': _clip(agent),
      ...extraHeaders,
    };
    final payload = body == null ? null : jsonEncode(body);
    // A POST without an idempotency key may have run: only retry it on 429 and 503.
    final safeToRepeat = method == 'GET' ||
        extraHeaders.containsKey('Idempotency-Key') ||
        path.endsWith('/cancel');

    for (var attempt = 0;; attempt++) {
      LoootError error;
      try {
        final req = http.Request(method, uri)..headers.addAll(headers);
        if (payload != null) req.bodyBytes = utf8.encode(payload);
        final res = await (() async {
          final streamed = await _http.send(req);
          return http.Response.fromStream(streamed);
        })()
            .timeout(_timeout);
        if (res.statusCode >= 200 && res.statusCode < 300) return res;
        error = _errorFrom(method, path, res);
      } on TimeoutException {
        error = LoootError(
          status: 0,
          code: 'timeout',
          message: '$method $path timed out after ${_timeout.inSeconds} s',
          retryable: true,
        );
      } on http.ClientException catch (e) {
        error = LoootError(
          status: 0,
          code: 'network_error',
          message: '$method $path failed: ${e.message}',
          retryable: true,
        );
      } on Exception catch (e) {
        // TLS and other transport failures that package:http does not wrap.
        error = LoootError(
          status: 0,
          code: 'network_error',
          message: '$method $path failed: ${e.runtimeType}',
          retryable: true,
        );
      }
      final transport = error.status == 0;
      final canRetry = attempt < _maxRetries &&
          error.retryable &&
          (transport
              ? safeToRepeat
              : (error.status == 429 || error.status == 503));
      if (!canRetry) throw error;
      await _sleep(_delay(error, attempt));
    }
  }

  static Duration _delay(LoootError e, int attempt) {
    final s = e.retryAfterSeconds;
    if (s != null) return Duration(milliseconds: (min(s, 30) * 1000).round());
    return Duration(milliseconds: 500 * (attempt + 1));
  }

  static LoootError _errorFrom(String method, String path, http.Response res) {
    final status = res.statusCode;
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    Object? body = text;
    try {
      body = jsonDecode(text);
    } on FormatException {
      // Keep the raw text.
    }
    final top = body is Map ? body : const <String, dynamic>{};
    final err = top['error'] is Map ? top['error'] as Map : const {};
    final code = err['code'] is String ? err['code'] as String : 'http_$status';

    num? retryAfter;
    final fromBody = top['retryAfterSeconds'] ?? err['retryAfterSeconds'];
    if (fromBody is num) {
      retryAfter = fromBody;
    } else {
      retryAfter = num.tryParse(res.headers['retry-after'] ?? '');
    }

    final bool retryable;
    if (err['retryable'] is bool) {
      retryable = err['retryable'] as bool;
    } else if (status == 429) {
      retryable = true;
    } else if (status == 503) {
      retryable = _retryable503.contains(code);
    } else if (status == 500) {
      retryable = code == 'internal_error';
    } else {
      retryable = false;
    }

    return LoootError(
      status: status,
      code: code,
      message: err['message'] is String
          ? err['message'] as String
          : '$method $path failed with HTTP $status',
      requestId: err['requestId'] is String
          ? err['requestId'] as String
          : res.headers['x-request-id'],
      body: body,
      retryable: retryable,
      retryAfterSeconds: retryAfter,
      topUp: top['topUp'] is Map
          ? TopUp(Map<String, dynamic>.from(top['topUp'] as Map))
          : null,
    );
  }

  static String _clip(String s) => s.length > 64 ? s.substring(0, 64) : s;

  static String _seg(String s) => Uri.encodeComponent(s);

  static String _queryString(Map<String, Object?> query) {
    final parts = <String>[];
    query.forEach((k, v) {
      if (v == null) return;
      final s = v is bool ? (v ? 'true' : 'false') : '$v';
      parts
          .add('${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(s)}');
    });
    return parts.isEmpty ? '' : '?${parts.join('&')}';
  }

  static Object? _wait(Object? wait) {
    if (wait == null || wait == false) return null;
    if (wait is int || wait == true) return wait;
    throw ArgumentError.value(wait, 'wait', 'use seconds as an int, or true');
  }

  static Object _fallbackJson(Object fallback) {
    if (fallback == true) return true;
    if (fallback is FallbackOptions) return fallback.toJson();
    if (fallback is Map) return Map<String, Object?>.from(fallback);
    throw ArgumentError.value(
        fallback, 'fallback', 'use true, a FallbackOptions or a Map');
  }

  static String _uuid4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }
}
