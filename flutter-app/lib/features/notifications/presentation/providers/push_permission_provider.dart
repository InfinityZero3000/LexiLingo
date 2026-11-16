import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/features/notifications/domain/services/push_permission_gateway.dart';

class PushPermissionProvider extends ChangeNotifier {
  static const String declinedAtKey = 'push_prompt_declined_at';
  static const Duration cooldown = Duration(days: 7);

  final PushPermissionGateway _gateway;
  final DateTime Function() _now;

  bool _visible = false;
  bool _busy = false;

  PushPermissionProvider({
    required PushPermissionGateway gateway,
    DateTime Function()? now,
  }) : _gateway = gateway,
       _now = now ?? DateTime.now;

  bool get visible => _visible;
  bool get busy => _busy;

  Future<void> evaluate() async {
    final prefs = await SharedPreferences.getInstance();
    final declinedAt = prefs.getInt(declinedAtKey);
    if (declinedAt != null) {
      final since = _now().difference(
        DateTime.fromMillisecondsSinceEpoch(declinedAt),
      );
      if (since < cooldown) return;
    }
    final status = await _gateway.status();
    _visible = status == PushPermission.notDetermined;
    notifyListeners();
  }

  Future<void> allow() async {
    _busy = true;
    notifyListeners();
    final result = await _gateway.requestPermission();
    if (result == PushPermission.denied) await _rememberDecline();
    _busy = false;
    _visible = false;
    notifyListeners();
  }

  Future<void> notNow() async {
    await _rememberDecline();
    _visible = false;
    notifyListeners();
  }

  Future<void> _rememberDecline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(declinedAtKey, _now().millisecondsSinceEpoch);
  }
}
