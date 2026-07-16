import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';

class _AlwaysConnectedNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}

ApiClient _apiClient(MockClientHandler handler) => ApiClient(
      client: MockClient(handler),
      networkInfo: _AlwaysConnectedNetworkInfo(),
      baseUrl: 'http://test',
    );

Map<String, dynamic> _inventoryItem({
  required String id,
  required bool isActive,
  DateTime? expiresAt,
}) =>
    {
      'id': id,
      'item': {
        'id': 'item_$id',
        'name': 'Double XP',
        'description': 'desc',
        'category': 'boosts',
        'price_gems': 50,
        'icon_url': '',
        'effect_type': 'double_xp',
        'effect_duration': 24,
        'effects': {},
        'is_available': true,
      },
      'quantity': 1,
      'is_active': isActive,
      'expires_at': expiresAt?.toIso8601String(),
      'activated_at': isActive ? DateTime.now().toIso8601String() : null,
      'purchased_at': DateTime.now().toIso8601String(),
    };

void main() {
  group('GamificationProvider.activeBoosts', () {
    test('returns empty list when inventory is empty', () async {
      final provider = GamificationProvider(
        apiClient: _apiClient((req) async => http.Response(
              jsonEncode({'success': true, 'data': {'items': []}}),
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

      await provider.loadInventory();
      expect(provider.activeBoosts, isEmpty);
      provider.dispose();
    });

    test('returns only active, non-expired boosts with expiresAt set', () async {
      final futureExpiry = DateTime.now().add(const Duration(hours: 2));
      final pastExpiry = DateTime.now().subtract(const Duration(hours: 1));

      final provider = GamificationProvider(
        apiClient: _apiClient((req) async => http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'items': [
                    // ✅ Active + not expired + has expiresAt → included
                    _inventoryItem(
                        id: 'a', isActive: true, expiresAt: futureExpiry),
                    // ✗ Not active
                    _inventoryItem(id: 'b', isActive: false),
                    // ✗ Active but expired
                    _inventoryItem(
                        id: 'c', isActive: true, expiresAt: pastExpiry),
                    // ✗ Active but no expiresAt
                    _inventoryItem(id: 'd', isActive: true),
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

      await provider.loadInventory();
      expect(provider.activeBoosts.length, 1);
      expect(provider.activeBoosts.first.id, 'a');
      provider.dispose();
    });

    test('remainingDuration is positive for future expiry', () async {
      final futureExpiry = DateTime.now().add(const Duration(hours: 3));
      final provider = GamificationProvider(
        apiClient: _apiClient((req) async => http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'items': [
                    _inventoryItem(
                        id: 'x', isActive: true, expiresAt: futureExpiry),
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

      await provider.loadInventory();
      final boost = provider.activeBoosts.first;
      expect(boost.remainingDuration, isNotNull);
      expect(boost.remainingDuration!.inSeconds, greaterThan(0));
      provider.dispose();
    });
  });
}
