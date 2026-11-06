/// The 402 `topUp` object: where to add credit.
class TopUp {
  TopUp(this.raw);

  /// The object as received.
  final Map<String, dynamic> raw;

  /// Stripe checkout link, set only when a session is already open.
  String? get checkoutUrl => raw['checkoutUrl'] as String?;

  /// Dashboard page to add credit. Always present.
  String? get dashboardUrl => raw['dashboardUrl'] as String?;

  /// Best link to show a user: checkout when set, else the dashboard.
  String? get url => checkoutUrl ?? dashboardUrl;

  @override
  String toString() => 'TopUp(${url ?? ''})';
}

/// Raised for every non-2xx answer, a missing token, a network failure and a timeout.
///
/// A failed run is not a [LoootError]: `run` and `runJob` return it with `status: failed`.
/// The token never appears in a message, in [toString] or in [body].
class LoootError implements Exception {
  LoootError({
    required this.status,
    required this.code,
    required this.message,
    this.requestId,
    this.body,
    this.retryable = false,
    this.retryAfterSeconds,
    this.topUp,
  });

  /// HTTP status, or 0 for a network error or timeout.
  final int status;

  /// `error.code`, else `http_<status>`. Also `missing_token`, `network_error`, `timeout`.
  final String code;

  /// `error.message`, else `<METHOD> <path> failed with HTTP <status>`.
  final String message;

  /// `error.requestId`, else the `x-request-id` header.
  final String? requestId;

  /// The decoded body, or the raw text when it is not JSON.
  final Object? body;

  /// True when the same request may succeed later (429, retryable 503, network, timeout).
  final bool retryable;

  /// Seconds the gateway asked to wait, from the body or the `retry-after` header.
  final num? retryAfterSeconds;

  /// Set on a 402 `insufficient_balance`.
  final TopUp? topUp;

  @override
  String toString() {
    final id = requestId == null ? '' : ', requestId: $requestId';
    return 'LoootError($status $code: $message$id)';
  }
}
