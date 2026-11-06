/// Dart and Flutter client for the looot API.
///
/// ```dart
/// final looot = Looot(); // reads LOOOT_TOKEN on the server, pass token on Flutter
/// final run = await looot.runJob(job: 'people.email.verify', input: {'email': 'jane@example.com'});
/// ```
library;

export 'src/client.dart' show Looot, defaultBaseUrl;
export 'src/errors.dart' show LoootError, TopUp;
export 'src/types.dart';
export 'src/version.dart' show version;
