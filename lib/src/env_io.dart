import 'dart:io' show Platform;

/// Reads an environment variable on the Dart VM and Flutter mobile and desktop.
String? readEnv(String name) => Platform.environment[name];

/// The runtime part of the User-Agent, for example `dart/3.5.0`.
String? runtimeUserAgent() => 'dart/${Platform.version.split(' ').first}';
