/// Platforms without dart:io (web) have no environment and no runtime version.
String? readEnv(String name) => null;

/// Browsers refuse to set User-Agent, so the web build sends none.
String? runtimeUserAgent() => null;
