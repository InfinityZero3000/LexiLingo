import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';

class AchievementsShopScreen extends StatefulWidget {
  const AchievementsShopScreen({super.key});

  @override
  State<AchievementsShopScreen> createState() => _AchievementsShopScreenState();
}

class _AchievementsShopScreenState extends State<AchievementsShopScreen> {
  List<Map<String, dynamic>> _achievements = [];
  List<Map<String, dynamic>> _shopItems = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([
        ApiClient.instance.get('/admin/achievements', params: {'page': 1, 'page_size': 10}),
        ApiClient.instance.get('/admin/shop', params: {'page': 1, 'page_size': 10}),
      ]);
      if (mounted) {
        setState(() {
          final aData = res[0]['data'];
          _achievements = List<Map<String, dynamic>>.from(
              aData is Map ? aData['items'] ?? aData['achievements'] ?? [] : aData ?? []);
          final sData = res[1]['data'];
          _shopItems = List<Map<String, dynamic>>.from(
              sData is Map ? sData['items'] ?? sData['shop_items'] ?? [] : sData ?? []);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text('Achievements & Shop',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: _GameStat(label: 'ACTIVE\nACHIEVEMENTS', value: _achievements.isNotEmpty ? '${_achievements.length}' : '128', icon: Icons.military_tech_outlined)),
                    const SizedBox(width: 12),
                    Expanded(child: _GameStat(label: 'TOTAL\nSHOP ITEMS', value: _shopItems.isNotEmpty ? '${_shopItems.length}' : '42', icon: Icons.shopping_cart_outlined)),
                    const SizedBox(width: 12),
                    Expanded(child: _GameStat(label: 'GLOBAL\nREDEMPTION', value: '64%', icon: Icons.trending_up)),
                  ]),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Achievement Badges',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.add, size: 14),
                        label: Text('ADD NEW BADGE',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 10, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    children: [
                      ..._defaultBadges.map(_buildBadge),
                      _buildNewBadge(),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Asset Upload
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Asset Upload',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text('Drag and drop SVGs or high-res PNGs for the gamification engine.',
                            style: GoogleFonts.spaceGrotesk(fontSize: 12, color: Colors.white60)),
                        const SizedBox(height: 16),
                        Center(
                          child: Container(
                            height: 80,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white24, style: BorderStyle.solid),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.cloud_upload_outlined,
                                      color: AppColors.primaryBright, size: 28),
                                  const SizedBox(height: 4),
                                  Text('UPLOAD NEW ASSET',
                                      style: GoogleFonts.spaceGrotesk(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.05,
                                          color: Colors.white60)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Pending Reviews
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.outlineVariant, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PENDING REVIEWS',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.08,
                                color: AppColors.onSurfaceMuted)),
                        const SizedBox(height: 10),
                        _ReviewRow(label: '"Vocab Hero" Badge'),
                        const Divider(height: 16),
                        _ReviewRow(label: 'Lingo Coin Texture'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Store Inventory
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Store Inventory Management',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Configure prices, stock levels, and active shop items.',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12, color: AppColors.onSurfaceMuted)),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search inventory...',
                      prefixIcon: Icon(Icons.search, size: 18, color: AppColors.onSurfaceMuted),
                    ),
                    style: GoogleFonts.spaceGrotesk(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  // Inventory table
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.outlineVariant, width: 0.5),
                    ),
                    child: Column(
                      children: [
                        _InventoryHeader(),
                        const Divider(height: 1),
                        ...(_shopItems.isNotEmpty ? _shopItems : _defaultShopItems).map((item) {
                          return Column(
                            children: [
                              _InventoryRow(item: item),
                              const Divider(height: 1),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  static final _defaultBadges = [
    {'name': 'STREAK MASTER', 'subtitle': '30 Day Consistency', 'color': Colors.amber},
    {'name': 'POLYGLOT', 'subtitle': 'Learn 3 Languages', 'color': AppColors.primary},
    {'name': 'SPEED DEMON', 'subtitle': 'Perfect Lesson < 2min', 'color': Colors.deepOrange},
  ];

  static final _defaultShopItems = [
    {'name': 'Streak Freeze', 'category': 'Consumable', 'price': 250, 'availability': 'Unlimited'},
    {'name': 'Duo Tuxedo Skin', 'category': 'Avatar Accessory', 'price': 1200, 'availability': 'Limited (500)'},
    {'name': 'Double or Nothing', 'category': 'Wager', 'price': 50, 'availability': 'Unlimited'},
    {'name': 'Neon UI Theme', 'category': 'Personalization', 'price': 2500, 'availability': 'Unlimited'},
  ];

  Widget _buildBadge(Map<String, dynamic> badge) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primaryContainer,
            child: Icon(Icons.military_tech, color: AppColors.primary, size: 22),
          ),
          const SizedBox(height: 6),
          Text(badge['name'] ?? '',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.onSurface),
              textAlign: TextAlign.center,
              maxLines: 2),
          Text(badge['subtitle'] ?? '',
              style: GoogleFonts.spaceGrotesk(fontSize: 7, color: AppColors.onSurfaceMuted),
              textAlign: TextAlign.center,
              maxLines: 1),
        ],
      ),
    );
  }

  Widget _buildNewBadge() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 1.5, style: BorderStyle.solid),
      ),
      child: Center(
        child: Icon(Icons.add_circle_outline, color: AppColors.primary, size: 28),
      ),
    );
  }
}

class _GameStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _GameStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(height: 6),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.onSurfaceMuted),
              maxLines: 2),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  const _ReviewRow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.military_tech, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurface)),
        ),
        GestureDetector(
          onTap: () {},
          child: Text('REVIEW',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
        ),
      ],
    );
  }
}

class _InventoryHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('ITEM NAME', style: _headerStyle)),
          Expanded(child: Text('CATEGORY', style: _headerStyle)),
          Expanded(child: Text('PRICE (LC)', style: _headerStyle)),
          Expanded(child: Text('AVAIL.', style: _headerStyle)),
        ],
      ),
    );
  }

  TextStyle get _headerStyle => GoogleFonts.spaceGrotesk(
      fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.onSurfaceMuted);
}

class _InventoryRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const _InventoryRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
              flex: 2,
              child: Text(item['name'] ?? item['item_name'] ?? '',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onSurface))),
          Expanded(
              child: Text(item['category'] ?? '',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, color: AppColors.onSurfaceMuted))),
          Expanded(
              child: Text('${item['price'] ?? item['price_gems'] ?? 0}',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onSurface))),
          Expanded(
              child: Text(item['availability'] ?? item['stock'] ?? 'Unlimited',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, color: AppColors.onSurfaceMuted))),
        ],
      ),
    );
  }
}
