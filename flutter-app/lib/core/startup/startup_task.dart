typedef StartupAction = Future<void> Function();

enum StartupStatus { pending, running, success, failed }

class StartupTask {
  final String id;
  final String label;
  final StartupAction action;

  StartupTask({required this.id, required this.label, required this.action});
}

class StartupResult {
  final String id;
  final StartupStatus status;
  final String? message;

  StartupResult({required this.id, required this.status, this.message});
}
