import 'package:flutter/foundation.dart';

/// Bumped after every task write so the other tabs know their data is stale.
///
/// The tabs live inside an `IndexedStack` and stay mounted, so they cannot
/// rely on `Navigator.pop` to refresh themselves.
final ValueNotifier<int> tasksChanged = ValueNotifier<int>(0);

void notifyTasksChanged() => tasksChanged.value++;
