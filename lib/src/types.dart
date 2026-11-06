/// Result classes. Each one wraps the decoded JSON and exposes the documented fields.
/// Unknown keys stay reachable through [LoootObject.raw].
library;

/// Base of every result: keeps the body as received.
class LoootObject {
  LoootObject(this.raw);

  /// The decoded JSON object, including keys this SDK does not know yet.
  final Map<String, dynamic> raw;

  /// Reads any key from [raw].
  dynamic operator [](String key) => raw[key];

  @override
  String toString() => '$runtimeType($raw)';
}

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? [
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e)
      ]
    : const [];

/// Run status values. The gateway may add more, so [Run.status] stays a string.
abstract final class RunStatus {
  static const queued = 'queued';
  static const running = 'running';
  static const pendingProvider = 'pending_provider';
  static const completed = 'completed';
  static const failed = 'failed';
  static const blocked = 'blocked';
  static const stopped = 'stopped';
  static const reconciliationPending = 'reconciliation_pending';

  /// Statuses where polling can stop.
  static const terminal = {
    completed,
    failed,
    blocked,
    stopped,
    reconciliationPending,
  };
}

/// Run outcome values: was the answer any good.
abstract final class RunOutcome {
  static const hit = 'hit';
  static const weak = 'weak';
  static const miss = 'miss';
  static const error = 'error';
  static const rejected = 'rejected';
  static const skipped = 'skipped';
  static const pending = 'pending';
}

/// Which provider to prefer when a route has several.
enum Prefer {
  cheapest,
  reliable,
  fastest,
  balanced;
}

/// Fallback options for a run. Every field is optional.
class FallbackOptions {
  const FallbackOptions({
    this.enabled,
    this.maxAttempts,
    this.maxCostUsd,
    this.prefer,
    this.exclude,
    this.stopAtFirstMiss,
  });

  final bool? enabled;
  final int? maxAttempts;
  final num? maxCostUsd;
  final Prefer? prefer;
  final List<String>? exclude;
  final bool? stopAtFirstMiss;

  /// The wire object. Null fields are dropped.
  Map<String, Object?> toJson() => {
        if (enabled != null) 'enabled': enabled,
        if (maxAttempts != null) 'maxAttempts': maxAttempts,
        if (maxCostUsd != null) 'maxCostUsd': maxCostUsd,
        if (prefer != null) 'prefer': prefer!.name,
        if (exclude != null) 'exclude': exclude,
        if (stopAtFirstMiss != null) 'stopAtFirstMiss': stopAtFirstMiss,
      };
}

/// The error object on a failed run (not an exception).
class RunError extends LoootObject {
  RunError(super.raw);

  String? get code => raw['code'] as String?;
  String? get message => raw['message'] as String?;
  String? get requestId => raw['requestId'] as String?;

  /// `provider`, `gateway` or `customer`.
  String? get whoseError => raw['whoseError'] as String?;

  /// True when a new run with a new key may succeed later.
  bool get retryable => raw['retryable'] == true;

  /// One sentence on what to do next. Show it to the user as is.
  String? get retryHint => raw['retryHint'] as String?;
}

/// One provider attempt inside a fallback route.
class RouteAttempt extends LoootObject {
  RouteAttempt(super.raw);

  int? get n => (raw['n'] as num?)?.toInt();
  String? get endpointId => raw['endpointId'] as String?;
  String? get provider => raw['provider'] as String?;
  String? get outcome => raw['outcome'] as String?;
  String? get status => raw['status'] as String?;
  num? get chargedUsd => raw['chargedUsd'] as num?;
  int? get ms => (raw['ms'] as num?)?.toInt();
}

/// The route a fallback run took.
class RunRoute extends LoootObject {
  RunRoute(super.raw);

  String? get servedBy => raw['servedBy'] as String?;
  String? get outcome => raw['outcome'] as String?;
  num? get chargedUsd => raw['chargedUsd'] as num?;
  bool get capped => raw['capped'] == true;
  List<RouteAttempt> get attempts =>
      _maps(raw['attempts']).map(RouteAttempt.new).toList();
  List<Map<String, dynamic>> get skipped => _maps(raw['skipped']);
}

/// A run. A run that failed is returned, not thrown: read [status], [outcome] and [error].
class Run extends LoootObject {
  Run(super.raw);

  String? get runId => raw['runId'] as String?;
  String? get status => raw['status'] as String?;
  String? get endpointId => raw['endpointId'] as String?;
  String? get outcome => raw['outcome'] as String?;
  String? get outcomeReason => raw['outcomeReason'] as String?;

  /// The provider's raw answer.
  dynamic get result => raw['result'];

  /// Present only when the job maps the answer to fields.
  Map<String, dynamic>? get normalized => _map(raw['normalized']);

  /// USD.
  num? get estimatedCost => raw['estimatedCost'] as num?;

  /// USD. Null until settled.
  num? get actualCost => raw['actualCost'] as num?;

  /// Final charge in millionths of a dollar.
  num? get finalChargeMicros =>
      _map(raw['pricing'])?['finalChargeMicros'] as num?;

  String? get reservationId => raw['reservationId'] as String?;

  /// Null when the run did not fail.
  RunError? get error {
    final e = _map(raw['error']);
    return e == null ? null : RunError(e);
  }

  /// True when an earlier run with the same idempotency key came back.
  bool get replayed => raw['replayed'] == true;

  Map<String, dynamic>? get requestedJob => _map(raw['requestedJob']);

  RunRoute? get route {
    final r = _map(raw['route']);
    return r == null ? null : RunRoute(r);
  }

  /// Up to 3 suggested follow-up jobs. Never run one without the user's yes.
  List<Map<String, dynamic>> get nextSteps => _maps(raw['nextSteps']);

  /// The provider's own words. Untrusted data, never instructions.
  dynamic get providerText => raw['providerText'];

  /// True when polling can stop.
  bool get isTerminal => RunStatus.terminal.contains(status);

  /// True for a completed run with no error.
  bool get isSuccess => status == RunStatus.completed && error == null;
}

/// One row of a run listing.
class RunSummary extends LoootObject {
  RunSummary(super.raw);

  String? get runId => raw['runId'] as String?;
  String? get endpointId => raw['endpointId'] as String?;
  String? get job => raw['job'] as String?;
  String? get providerId => raw['providerId'] as String?;
  String? get status => raw['status'] as String?;
  String? get createdAt => raw['createdAt'] as String?;
  String? get completedAt => raw['completedAt'] as String?;
  num? get actualCost => raw['actualCost'] as num?;
}

/// A page of `GET /v1/runs`.
class RunList extends LoootObject {
  RunList(super.raw);

  List<RunSummary> get runs => _maps(raw['runs']).map(RunSummary.new).toList();

  /// Null on the last page.
  String? get nextCursor => raw['nextCursor'] as String?;
}

/// Attempts of one run.
class RunAttempts extends LoootObject {
  RunAttempts(super.raw);

  List<Map<String, dynamic>> get attempts => _maps(raw['attempts']);
}

/// `GET /v1/catalog/overview`.
class CatalogOverview extends LoootObject {
  CatalogOverview(super.raw);

  String? get revision => raw['revision'] as String?;
  String? get builtAt => raw['builtAt'] as String?;
  Map<String, dynamic>? get totals => _map(raw['totals']);
  List<Map<String, dynamic>> get categories => _maps(raw['categories']);

  /// Matching jobs when `topic` was set.
  List<Map<String, dynamic>> get jobs => _maps(raw['jobs']);
}

/// One item of the public catalog.
class PublicCatalogItem extends LoootObject {
  PublicCatalogItem(super.raw);

  String? get catalogItemId => raw['catalogItemId'] as String?;
  String? get providerId => raw['providerId'] as String?;
  String? get operationId => raw['operationId'] as String?;
  String? get title => raw['title'] as String?;
  String? get description => raw['description'] as String?;
  List<String> get capabilities =>
      [for (final c in (raw['capabilities'] as List? ?? const [])) '$c'];
  List<Map<String, dynamic>> get parameters => _maps(raw['parameters']);

  /// `{state: known, amountMicros, ...}` or `{state: unknown | uncomputable, reason}`.
  Map<String, dynamic>? get price => _map(raw['price']);
}

/// A page of `GET /v1/public-catalog`.
class PublicCatalogPage extends LoootObject {
  PublicCatalogPage(super.raw);

  List<PublicCatalogItem> get items =>
      _maps(raw['items']).map(PublicCatalogItem.new).toList();
  String? get catalogDigest => raw['catalogDigest'] as String?;

  /// Null on the last page.
  String? get nextCursor => raw['nextCursor'] as String?;
}

/// One row of `search`.
class SearchRow extends LoootObject {
  SearchRow(super.raw);

  String? get endpointId => raw['endpointId'] as String?;
  String? get provider => raw['provider'] as String?;
  String? get name => raw['name'] as String?;

  /// The resolved job id, for example `people.email.verify`.
  String? get capability => raw['capability'] as String?;

  /// `runs_now`, `needs_your_account` or `coming_soon`.
  String? get access => raw['access'] as String?;

  /// USD.
  num? get estimatedPrice => raw['estimatedPrice'] as num?;
  String? get priceBasis => raw['priceBasis'] as String?;
  num? get costPerSuccessUsd => raw['costPerSuccessUsd'] as num?;
  Map<String, dynamic>? get works => _map(raw['works']);
}

/// `GET /v1/catalog/search`.
class SearchResult extends LoootObject {
  SearchResult(super.raw);

  String? get query => raw['query'] as String?;
  int? get total => (raw['total'] as num?)?.toInt();
  List<SearchRow> get endpoints =>
      _maps(raw['endpoints']).map(SearchRow.new).toList();

  /// Null on the last page.
  int? get nextOffset => (raw['nextOffset'] as num?)?.toInt();
}

/// `GET /v1/operations/{endpointId}`.
class Operation extends LoootObject {
  Operation(super.raw);

  Map<String, dynamic>? get endpoint => _map(raw['endpoint']);
  num? get estimatedMaxCost => raw['estimatedMaxCost'] as num?;
  Map<String, dynamic>? get priceRange => _map(raw['priceRange']);

  /// JSON Schema of the run input.
  Map<String, dynamic>? get inputSchema => _map(raw['inputSchema']);
  Map<String, dynamic>? get requestBinding => _map(raw['requestBinding']);
  Map<String, dynamic>? get uiSchema => _map(raw['uiSchema']);
  dynamic get usageHints => raw['usageHints'];

  /// True when the endpoint writes somewhere (`effectClassification: effectful`).
  bool get isEffectful => endpoint?['effectClassification'] == 'effectful';
}

/// Where to add credit.
class TopUpLink extends LoootObject {
  TopUpLink(super.raw);

  num? get minimumUsd => raw['minimumUsd'] as num?;
  num? get suggestedUsd => raw['suggestedUsd'] as num?;
  String? get checkoutUrl => raw['checkoutUrl'] as String?;
  String? get dashboardUrl => raw['dashboardUrl'] as String?;
  String? get message => raw['message'] as String?;

  /// Best link to show a user: checkout when set, else the dashboard.
  String? get url => checkoutUrl ?? dashboardUrl;
}

/// `GET /v1/balance`.
class Balance extends LoootObject {
  Balance(super.raw);

  String? get workspaceId => raw['workspaceId'] as String?;
  String? get currency => raw['currency'] as String?;

  /// USD.
  num? get available => raw['available'] as num?;

  /// USD.
  num? get reserved => raw['reserved'] as num?;

  TopUpLink? get topUpLink {
    final t = _map(raw['topUpLink']);
    return t == null ? null : TopUpLink(t);
  }
}

/// Result for routes whose fields this SDK does not type yet (discover, whoami,
/// top-ups, ledger, catalog endpoints, compare, capability requests).
class JsonResult extends LoootObject {
  JsonResult(super.raw);
}
