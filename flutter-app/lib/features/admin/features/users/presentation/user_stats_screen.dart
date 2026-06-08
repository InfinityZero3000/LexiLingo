import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../data/users_repository.dart';

class UserStatsScreen extends StatefulWidget {
  final String userId;
  const UserStatsScreen({super.key, required this.userId});

  @override
  State<UserStatsScreen> createState() => _UserStatsScreenState();
}

class _UserStatsScreenState extends State<UserStatsScreen> {
  final _repo = UsersRepository();
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _saving = false;

  final _levelCtrl = TextEditingController();
  final _gemsCtrl = TextEditingController();
  String _selectedLeague = 'Platinum Division';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _levelCtrl.dispose();
    _gemsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _repo.getUserStats(widget.userId);
      if (mounted) {
        setState(() {
          _data = data;
          _levelCtrl.text = (data['numeric_level'] ?? 1).toString();
          _gemsCtrl.text = (data['gems'] ?? data['total_xp'] ?? 0).toString();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleBlock() async {
    final isActive = _data?['is_active'] == true;
    try {
      if (isActive) {
        await _repo.blockUser(widget.userId);
      } else {
        await _repo.unblockUser(widget.userId);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isActive ? 'User đã bị block' : 'User đã được unblock',
                style: GoogleFonts.spaceGrotesk()),
            backgroundColor: isActive ? AppColors.error : AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Thao tác thất bại', style: GoogleFonts.spaceGrotesk()),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _repo.updateUser(widget.userId, {
        'numeric_level': int.tryParse(_levelCtrl.text) ?? 1,
        'gems': int.tryParse(_gemsCtrl.text) ?? 0,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Changes saved', style: GoogleFonts.spaceGrotesk()),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save', style: GoogleFonts.spaceGrotesk()),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
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
        actions: [
          OutlinedButton(
            onPressed: _loading ? null : _toggleBlock,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: _data?['is_active'] == true ? AppColors.error : AppColors.success,
              ),
              foregroundColor: _data?['is_active'] == true ? AppColors.error : AppColors.success,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: Text(
              _data?['is_active'] == true ? 'Block' : 'Unblock',
              style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBright,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text('Save Changes',
                    style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Breadcrumb
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'USER MANAGEMENT > PROFILE > GAMIFICATION',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.08,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Adjust User Stats',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        letterSpacing: -0.02,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Profile card
                  _StatCard(
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.primary, width: 2.5),
                              ),
                              child: CircleAvatar(
                                radius: 38,
                                backgroundColor: AppColors.primaryContainer,
                                backgroundImage: _data?['avatar_url'] != null
                                    ? NetworkImage(_data!['avatar_url'])
                                    : null,
                                child: _data?['avatar_url'] == null
                                    ? Text(
                                        (_data?['display_name'] ?? 'A')[0].toUpperCase(),
                                        style: GoogleFonts.spaceGrotesk(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary),
                                      )
                                    : null,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBright,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(Icons.verified, color: Colors.white, size: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _data?['display_name'] ?? 'Admin User',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                        ),
                        Text(
                          _data?['email'] ?? '',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 13, color: AppColors.onSurfaceMuted),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ProfileMeta(
                              label: 'USER ID',
                              value: '#LX-${widget.userId.substring(0, 5).toUpperCase()}',
                            ),
                            const SizedBox(width: 24),
                            _ProfileMeta(
                              label: 'STATUS',
                              value: _data?['is_active'] == true ? 'ACTIVE' : 'INACTIVE',
                              valueColor: _data?['is_active'] == true
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Current Level
                  _StatCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.military_tech_outlined,
                                  color: AppColors.primary, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text('Current Level',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _levelCtrl.text,
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                    letterSpacing: -0.03),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('UPDATE',
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.08,
                                        color: AppColors.onSurfaceMuted)),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 80,
                                  child: TextField(
                                    controller: _levelCtrl,
                                    keyboardType: TextInputType.number,
                                    style: GoogleFonts.spaceGrotesk(fontSize: 14),
                                    decoration: const InputDecoration(
                                      contentPadding:
                                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      isDense: true,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: const LinearProgressIndicator(
                            value: 0.75,
                            backgroundColor: AppColors.surfaceContainerHigh,
                            valueColor: AlwaysStoppedAnimation(AppColors.primary),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('75% TO NEXT LEVEL',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.05,
                                color: AppColors.onSurfaceMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Total Gems
                  _StatCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.diamond_outlined,
                                  color: AppColors.primary, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text('Total Gems',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _gemsCtrl.text,
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                    letterSpacing: -0.03),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ADJUST',
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.08,
                                        color: AppColors.onSurfaceMuted)),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 90,
                                  child: TextField(
                                    controller: _gemsCtrl,
                                    keyboardType: TextInputType.number,
                                    style: GoogleFonts.spaceGrotesk(fontSize: 14),
                                    decoration: const InputDecoration(
                                      contentPadding:
                                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  final v = int.tryParse(_gemsCtrl.text) ?? 0;
                                  _gemsCtrl.text = (v + 100).toString();
                                },
                                child: Text('+ 100',
                                    style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  final v = int.tryParse(_gemsCtrl.text) ?? 0;
                                  _gemsCtrl.text = (v + 500).toString();
                                },
                                child: Text('+ 500',
                                    style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Rank Placement
                  _StatCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.leaderboard_outlined,
                                  color: AppColors.primary, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text('Rank Placement',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 16, fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBright,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('TOP 3%',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.primary),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('CURRENT RANK',
                                        style: GoogleFonts.spaceGrotesk(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.08,
                                            color: AppColors.onSurfaceMuted)),
                                    Text(
                                      (_data?['rank'] ?? 'Platinum IV').toString().toUpperCase(),
                                      style: GoogleFonts.spaceGrotesk(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.onSurface),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('CHANGE LEAGUE',
                                      style: GoogleFonts.spaceGrotesk(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.08,
                                          color: AppColors.onSurfaceMuted)),
                                  const SizedBox(height: 4),
                                  DropdownButtonFormField<String>(
                                    value: _selectedLeague,
                                    decoration: const InputDecoration(isDense: true),
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 13, color: AppColors.onSurface),
                                    items: const [
                                      'Bronze Division', 'Silver Division',
                                      'Gold Division', 'Platinum Division',
                                      'Diamond Division',
                                    ]
                                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                                        .toList(),
                                    onChanged: (v) =>
                                        setState(() => _selectedLeague = v ?? _selectedLeague),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Active Achievement Tracks
                  _StatCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Active Achievement Tracks',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface)),
                        const SizedBox(height: 16),
                        _AchievementRow(
                          icon: Icons.local_fire_department_outlined,
                          label: 'Streak Master',
                          progress: 88,
                          total: 100,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final Widget child;
  const _StatCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: child,
    );
  }
}

class _ProfileMeta extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ProfileMeta({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.08,
                color: AppColors.onSurfaceMuted)),
        const SizedBox(height: 2),
        Text(value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor ?? AppColors.onSurface)),
      ],
    );
  }
}

class _AchievementRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int progress;
  final int total;

  const _AchievementRow({
    required this.icon,
    required this.label,
    required this.progress,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface)),
                  Text('$progress/$total',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress / total,
                  backgroundColor: AppColors.surfaceContainerHigh,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  minHeight: 5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const Icon(Icons.edit_outlined, size: 18, color: AppColors.onSurfaceMuted),
      ],
    );
  }
}
