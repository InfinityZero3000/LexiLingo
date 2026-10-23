import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/utils/app_logger.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';

const _tag = 'LexiMemoryProvider';

enum LexiMemoryStatus { loading, ready, failed }

/// What Lexi remembers about the learner from chat, and the way to forget it.
class LexiMemoryProvider extends ChangeNotifier {
  /// Display order; matches the backend allowlist in `lexi_memory.py`.
  static const factKeys = ['preferred_name', 'occupation', 'goal', 'interests'];

  final LexiChatRepository repository;

  LexiMemoryProvider({required this.repository});

  LexiMemoryStatus _status = LexiMemoryStatus.loading;
  Map<String, String> _facts = const {};
  bool _disposed = false;

  LexiMemoryStatus get status => _status;

  /// Known keys first in a fixed order, so rows do not jump between loads.
  List<MapEntry<String, String>> get facts => [
    for (final key in factKeys)
      if (_facts[key] != null) MapEntry(key, _facts[key]!),
  ];

  Future<void> load() async {
    _status = LexiMemoryStatus.loading;
    _notify();
    try {
      _facts = await repository.getMemory();
      _status = LexiMemoryStatus.ready;
    } catch (e) {
      logWarn(_tag, 'load failed: $e');
      _status = LexiMemoryStatus.failed;
    }
    _notify();
  }

  /// True when the server confirmed; the row only disappears then.
  Future<bool> forget(String key) async {
    try {
      await repository.forgetMemoryFact(key);
    } catch (e) {
      logWarn(_tag, 'forget($key) failed: $e');
      return false;
    }
    _facts = {..._facts}..remove(key);
    _notify();
    return true;
  }

  Future<bool> forgetAll() async {
    try {
      await repository.forgetMemory();
    } catch (e) {
      logWarn(_tag, 'forgetAll failed: $e');
      return false;
    }
    _facts = const {};
    _notify();
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
