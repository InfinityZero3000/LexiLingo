import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/utils/avatar_utils.dart';
import 'package:lexilingo_app/core/widgets/network_avatar_image.dart';

/// Edit Profile Screen
/// Allows users to update their display name and avatar.
/// Backend endpoint: PUT /users/me with UserUpdate schema.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _displayNameController;
  late TextEditingController _avatarUrlController;

  bool _isSaving = false;
  String? _errorMessage;
  String? _selectedAvatarUrl;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  static const List<String> _avatarOptions = AvatarUtils.presetAvatarUrls;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    _displayNameController = TextEditingController(
      text: user?.displayName ?? '',
    );
    final normalizedAvatar = AvatarUtils.normalizeAvatarUrl(user?.avatarUrl);
    _avatarUrlController = TextEditingController(text: normalizedAvatar ?? '');
    _selectedAvatarUrl = normalizedAvatar;

    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _avatarUrlController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final newDisplayName = _displayNameController.text.trim();
      final selectedOrTypedAvatar =
          _selectedAvatarUrl ?? _avatarUrlController.text.trim();
      final normalizedAvatarUrl = AvatarUtils.normalizeAvatarUrl(
        selectedOrTypedAvatar,
      );

      await authProvider.updateProfile(
        displayName: newDisplayName.isNotEmpty ? newDisplayName : null,
        avatarUrl: normalizedAvatarUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.surfaceLight),
                SizedBox(width: 8),
                Text('Profile updated successfully!'),
              ],
            ),
            backgroundColor: AppColors.greenSuccess,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to update profile. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: LottieLoadingWidget.tiny(),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Error message
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.errorBright.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.errorBright,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppColors.errorBright,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Avatar Section
                _buildAvatarSection(user, isDark),
                const SizedBox(height: 32),

                // Display Name
                _buildSectionLabel('Display Name'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _displayNameController,
                  hint: 'Enter your display name',
                  icon: Icons.person_outline,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Display name is required';
                    }
                    if (value.trim().length < 2) {
                      return 'Must be at least 2 characters';
                    }
                    if (value.trim().length > 50) {
                      return 'Must be less than 50 characters';
                    }
                    return null;
                  },
                  isDark: isDark,
                ),
                const SizedBox(height: 24),

                // Account Info (read-only)
                _buildSectionLabel('Account Information'),
                const SizedBox(height: 8),
                _buildReadOnlyField(
                  label: 'Username',
                  value: user?.username ?? 'N/A',
                  icon: Icons.alternate_email,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildReadOnlyField(
                  label: 'Email',
                  value: user?.email ?? 'N/A',
                  icon: Icons.email_outlined,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildReadOnlyField(
                  label: 'Level',
                  value: user?.level ?? 'A1',
                  icon: Icons.school_outlined,
                  isDark: isDark,
                ),

                const SizedBox(height: 40),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.surfaceLight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: AppColors.primary.withValues(alpha: 0.3),
                    ),
                    child: _isSaving
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: LottieLoadingWidget.tiny(),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_outlined, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection(UserEntity? user, bool isDark) {
    final currentAvatar = AvatarUtils.normalizeAvatarUrl(
      _selectedAvatarUrl ?? user?.avatarUrl,
    );

    return Center(
      child: Column(
        children: [
          // Current Avatar
          Stack(
            alignment: Alignment.center,
            children: [
              // Glow ring
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.3),
                      AppColors.primary.withValues(alpha: 0.3),
                    ],
                  ),
                ),
              ),
              // Avatar
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surfaceLight, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: currentAvatar != null && currentAvatar.isNotEmpty
                      ? _buildAvatarImage(
                          currentAvatar,
                          fit: BoxFit.cover,
                          width: 120,
                          height: 120,
                          fallback: _buildDefaultAvatar(),
                        )
                      : _buildDefaultAvatar(),
                ),
              ),
              // Camera icon
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => _showAvatarPicker(),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primary],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.surfaceLight,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      color: AppColors.surfaceLight,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Tap camera to change avatar',
            style: const TextStyle(color: AppColors.grey600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 120,
      height: 120,
      color: AppColors.primary.withValues(alpha: 0.2),
      child: const Icon(Icons.person, size: 60, color: AppColors.primary),
    );
  }

  Widget _buildAvatarImage(
    String url, {
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    Widget? fallback,
  }) {
    final fallbackWidget =
        fallback ??
        Container(
          color: AppColors.grey200,
          child: const Icon(Icons.person, color: AppColors.grey500),
        );

    return NetworkAvatarImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      fallback: fallbackWidget,
    );
  }

  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose Avatar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _avatarOptions.length,
                itemBuilder: (context, index) {
                  final url = _avatarOptions[index];
                  final isSelected = _selectedAvatarUrl == url;
                  return GestureDetector(
                    onTap: () {
                      final normalized = AvatarUtils.normalizeAvatarUrl(url);
                      setState(() {
                        _selectedAvatarUrl = normalized;
                        _avatarUrlController.text = normalized ?? '';
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.grey400.withValues(alpha: 0.6),
                          width: isSelected ? 3 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: ClipOval(
                        child: _buildAvatarImage(
                          url,
                          fit: BoxFit.cover,
                          fallback: Container(
                            color: AppColors.grey200,
                            child: const Icon(
                              Icons.person,
                              color: AppColors.grey500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // Custom URL option
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showCustomUrlDialog();
                },
                icon: const Icon(Icons.link),
                label: const Text('Use custom URL'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showCustomUrlDialog() {
    final urlController = TextEditingController(
      text: _avatarUrlController.text,
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Custom Avatar URL'),
          content: TextField(
            controller: urlController,
            decoration: InputDecoration(
              hintText: 'https://example.com/avatar.png',
              prefixIcon: const Icon(Icons.link),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final normalized = AvatarUtils.normalizeAvatarUrl(
                  urlController.text,
                );
                setState(() {
                  _selectedAvatarUrl = normalized;
                  _avatarUrlController.text = normalized ?? '';
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.surfaceLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.3,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    required bool isDark,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: isDark ? AppColors.grey900 : AppColors.grey50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.grey400.withValues(alpha: 0.6),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.grey400.withValues(alpha: 0.6),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.errorBright),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.grey900.withValues(alpha: 0.5)
            : AppColors.grey100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.grey400.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.grey600, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.grey600,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textInverted.withValues(alpha: 0.7)
                        : AppColors.grey800,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.lock_outline, color: AppColors.grey500, size: 16),
        ],
      ),
    );
  }
}
