/// Platforms without dart:io (web) have no environment and no runtime version.
String? readEnv(String name) => null;

/// The runtime part of the User-Agent.
String runtimeUserAgent() => 'dart-web/unknown';
