// ignore_for_file: avoid_print
import 'package:looot/looot.dart';

/// Search, inspect, then run a job. The run is paid.
/// Run with: LOOOT_TOKEN=... dart run example/quickstart.dart
Future<void> main() async {
  final looot = Looot(); // reads LOOOT_TOKEN
  try {
    final found = await looot.search(
        q: 'verify an email', prefer: Prefer.cheapest, limit: 3);
    for (final row in found.endpoints) {
      print('${row.endpointId} ${row.provider} USD ${row.estimatedPrice}');
    }

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
    if (run.error != null) print(run.error!.retryHint);
  } on LoootError catch (e) {
    if (e.code == 'insufficient_balance') {
      print('Add credit: ${e.topUp?.url}');
    } else {
      print('${e.status} ${e.code} ${e.message} ${e.requestId}');
    }
  } finally {
    looot.close();
  }
}
