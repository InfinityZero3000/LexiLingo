import 'dart:async';
import 'startup_task.dart';

/// Coordinates sequential startup tasks with progress callbacks.
class StartupCoordinator {
  final List<StartupTask> tasks;
  final Duration timeoutPerTask;

  StartupCoordinator({
    required this.tasks,
    this.timeoutPerTask = const Duration(seconds: 10),
  });

  Future<List<StartupResult>> run({void Function(StartupResult result)? onProgress}) async {
    final results = <StartupResult>[];
    for (final task in tasks) {
      try {
        onProgress?.call(StartupResult(id: task.id, status: StartupStatus.running, message: task.label));
        await task.action().timeout(timeoutPerTask);
        final result = StartupResult(id: task.id, status: StartupStatus.success, message: task.label);
        results.add(result);
        onProgress?.call(result);
      } catch (e) {
        final result = StartupResult(id: task.id, status: StartupStatus.failed, message: e.toString());
        results.add(result);
        onProgress?.call(result);
        // Stop chain on first failure
        break;
      }
    }
    return results;
  }
}
