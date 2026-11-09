// Demonstrates the bug where snapshotsInSync() fires before the Query snapshot
// when using cloud_firestore > 6.6.0
//
//   Terminal 1
//   firebase emulators:start --only firestore --project demo-snapshot-bug
//
//   Terminal 2 (consumer - watches a Query + snapshotsInSync(); start
//   this one first):
//     flutter test integration_test/repro_test.dart -d macos \
//       --dart-define=ROLE=consumer
//
//   Terminal 3 (writer - writes to the same document every 1s):
//     flutter test integration_test/repro_test.dart -d macos \
//       --dart-define=ROLE=writer
//
// Watch the consumer's own log, specifically the order of each matching
// pair of lines: on an affected version, "snapshotsInSync() fired"
// consistently prints first, "Query snapshot" a few ms after it - every
// single cycle. On an unaffected version (e.g. cloud_firestore 6.6.0),
// it's the other way around, every time - "Query snapshot" first, then
// "snapshotsInSync() fired". Ctrl+C either process to stop.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _role = String.fromEnvironment('ROLE');

const _emulatorHost = 'localhost';
const _emulatorPort = 8080;
const _projectId = 'demo-snapshot-bug';
const _collection = 'items';
const _docId = 'shared-doc';

const _fakeApiKey = 'AIzaSyBXhfhcZ8I-q9P5OCbaJE6z9LQlBo3Cy4A';
const _fakeAppId = '1:623957948749:ios:e7f4c984a71e8bfc9c2e3f';
const _fakeSenderId = '623957948749';

void _log(String line, DateTime? time) {
  // ignore: avoid_print
  print('[$time] [$_role] $line');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('snapshotsInSync repro ($_role)', () async {
    if (_role != 'writer' && _role != 'consumer') {
      throw ArgumentError(
        'Pass --dart-define=ROLE=writer or --dart-define=ROLE=consumer '
        '(got "$_role")',
      );
    }

    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: _fakeApiKey,
        appId: _fakeAppId,
        messagingSenderId: _fakeSenderId,
        projectId: _projectId,
      ),
    );
    final db = FirebaseFirestore.instance;
    db.useFirestoreEmulator(_emulatorHost, _emulatorPort);
    await db.clearPersistence();

    if (_role == 'writer') {
      await _runWriter(db);
    } else {
      await _runConsumer(db);
    }
  }, timeout: Timeout.none);
}

const _writeGap = Duration(seconds: 1);

Future<void> _runWriter(FirebaseFirestore db) async {
  _log(
    'writing $_collection/$_docId every ${_writeGap.inSeconds}s. '
    'Ctrl+C to stop.', DateTime.now(),
  );
  var seq = 0;
  while (true) {
    await Future.delayed(_writeGap);
    seq++;
    final value = 'write-$seq-${DateTime.now().millisecondsSinceEpoch}';
    await db.collection(_collection).doc(_docId).set({
      'seq': seq,
      'value': value,
    });
    _log('wrote seq=$seq value=$value', DateTime.now());
  }
}

// Sets up the Query listener and snapshotsInSync() listener exactly
// once and logs every event.
Future<void> _runConsumer(FirebaseFirestore db) async {
  _log(
    'watching $_collection (Query) and snapshotsInSync(). Ctrl+C to stop.',
      DateTime.now()
  );

  String? lastKnownValue;

  // A Query (collection) listener, not a single DocumentReference
  // listener - confirmed essential to reproducing this
  db.collection(_collection).snapshots().listen((snap) {
    final at = DateTime.now();
    for (final d in snap.docs) {
      if (d.id == _docId) lastKnownValue = d.data()['value'] as String?;
    }
    _log(
      'Query snapshot: ${snap.docs.length} doc(s), $_docId=$lastKnownValue '
      '(fromCache=${snap.metadata.isFromCache}, '
      'hasPendingWrites=${snap.metadata.hasPendingWrites})',
      at,
    );
  });

  db.snapshotsInSync().listen((_) {
    _log('snapshotsInSync() fired', DateTime.now());
  });

  // Nothing further to do - the listeners above do the work.
  await Completer<void>().future;
}
