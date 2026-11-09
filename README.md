Demonstrates the bug where snapshotsInSync() fires before the Query snapshot
when using cloud_firestore > 6.6.0

```
  Terminal 1
  firebase emulators:start --only firestore --project demo-snapshot-bug

  Terminal 2 (consumer - watches a Query + snapshotsInSync(); start
  this one first):
    flutter test integration_test/repro_test.dart -d macos \
      --dart-define=ROLE=consumer

  Terminal 3 (writer - writes to the same document every 1s):
    flutter test integration_test/repro_test.dart -d macos \
      --dart-define=ROLE=writer
```

Watch the consumer's own log, specifically the order of each matching
pair of lines: on an affected version, "snapshotsInSync() fired"
consistently prints first, "Query snapshot" a few ms after it - every
single cycle. On an unaffected version (e.g. cloud_firestore 6.6.0),
it's the other way around, every time - "Query snapshot" first, then
"snapshotsInSync() fired". Ctrl+C either process to stop.