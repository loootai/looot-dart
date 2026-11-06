/// Web builds have no environment variables.
String? readEnv(String name) => null;

/// Browsers refuse to set User-Agent, so the web build sends none.
String? runtimeUserAgent() => null;
