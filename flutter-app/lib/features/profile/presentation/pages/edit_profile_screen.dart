import 'package:lexilingo_app/core/widgets/tap_target.dart';
import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/utils/dispose_after_route.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/utils/avatar_utils.dart';
import 'package:lexilingo_app/core/widgets/network_avatar_image.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/level/presentation/level_sync.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/level/presentation/widgets/cefr_level_picker.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

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
  static const _verificationResendCooldownSeconds = 60;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _displayNameController;
  late TextEditingController _avatarUrlController;

  bool _isSaving = false;
  bool _isSendingVerification = false;
  bool _isCheckingVerification = false;
  int _verificationCooldownSeconds = 0;
  Timer? _verificationCooldownTimer;
  UiText? _errorMessage;
  String? _selectedAvatarUrl;
  Uint8List? _pickedAvatarBytes;
  String _pickedAvatarName = 'avatar.jpg';
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  List<String> _avatarOptions = List.of(AvatarUtils.presetAvatarUrls);

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final gamification = context.read<GamificationProvider>();
      await gamification.loadInventory();
      if (!mounted) return;
      setState(() {
        _avatarOptions = {
          ...AvatarUtils.presetAvatarUrls,
          ...gamification.ownedAvatarUrls,
        }.toList();
      });
    });

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
    _verificationCooldownTimer?.cancel();
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

      final picked = _pickedAvatarBytes;
      if (picked != null) {
        try {
          await authProvider.uploadAvatar(picked, _pickedAvatarName);
        } catch (_) {
          if (mounted) {
            setState(
              () => _errorMessage = UiText.key('profile.avatarUploadFailed'),
            );
          }
          return;
        }
        // Saved already; a retry after a later failure must not upload twice.
        _pickedAvatarBytes = null;
      }

      await authProvider.updateProfile(
        displayName: newDisplayName.isNotEmpty ? newDisplayName : null,
        avatarUrl: picked != null ? null : normalizedAvatarUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.surfaceLight),
                SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    'profile.profileUpdatedSuccess'.tr(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: context.status.success,

            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = UiText.key('profile.profileUpdatedFailed');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _sendVerificationEmail(UserEntity user) async {
    if (user.isVerified || _isSendingVerification || _isCheckingVerification) {
      return;
    }

    setState(() => _isSendingVerification = true);
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.resendVerificationEmail(user.email);
    if (!mounted) return;

    setState(() => _isSendingVerification = false);
    if (success) _startVerificationCooldown();
    _showVerificationSnackBar(
      success
          ? 'auth.emailVerificationResendSuccess'.tr()
          : (authProvider.errorMessage ??
                'auth.emailVerificationResendError'.tr()),
      isSuccess: success,
    );
  }

  Future<void> _checkVerificationStatus() async {
    if (_isCheckingVerification || _isSendingVerification) return;

    setState(() => _isCheckingVerification = true);
    final authProvider = context.read<AuthProvider>();
    await authProvider.refreshCurrentUser();
    if (!mounted) return;

    final isVerified = authProvider.currentUser?.isVerified == true;
    final refreshError = authProvider.errorMessage;
    setState(() {
      _isCheckingVerification = false;
      if (isVerified) {
        _verificationCooldownTimer?.cancel();
        _verificationCooldownSeconds = 0;
      }
    });
    _showVerificationSnackBar(
      isVerified
          ? 'profile.emailVerified'.tr()
          : (refreshError ?? 'profile.emailVerificationPending'.tr()),
      isSuccess: isVerified,
    );
  }

  void _startVerificationCooldown() {
    _verificationCooldownTimer?.cancel();
    setState(
      () => _verificationCooldownSeconds = _verificationResendCooldownSeconds,
    );
    _verificationCooldownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_verificationCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _verificationCooldownSeconds = 0);
        return;
      }
      setState(() => _verificationCooldownSeconds--);
    });
  }

  void _showVerificationSnackBar(String message, {required bool isSuccess}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess
            ? context.status.success
            : AppColors.warningDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    final primaryDeepColor = AppColorRoles.primaryDeep(isDark);

    return Scaffold(
      appBar: AppBar(
        title: Text('profile.editProfile'.tr()),
        leading: AppBackButton(
          onPressed: () => Navigator.of(context).pop(),
          iconSize: 20,
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            ),
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: LottieLoadingWidget.tiny(),
                  )
                : Text(
                    'common.save'.tr(),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: ContentWidth(
        maxWidth: ContentWidth.reading,
        child: FadeTransition(
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
                      padding: const EdgeInsets.all(AppSpacing.md),
                      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.errorBg,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.error.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.errorBright,
                            size: 20,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _errorMessage!.resolve(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Avatar Section
                  _buildAvatarSection(
                    user,
                    isDark,
                    primaryColor,
                    primaryDeepColor,
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // Display Name
                  _buildSectionLabel('profile.displayName'.tr()),
                  const SizedBox(height: AppSpacing.sm),
                  _buildTextField(
                    controller: _displayNameController,
                    hint: 'profile.enterDisplayName'.tr(),
                    icon: Icons.person_outline,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'profile.displayNameRequired'.tr();
                      }
                      if (value.trim().length < 2) {
                        return 'profile.displayNameMin'.tr();
                      }
                      if (value.trim().length > 50) {
                        return 'profile.displayNameMax'.tr();
                      }
                      return null;
                    },
                    isDark: isDark,
                    primaryColor: primaryColor,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Account Info (read-only)
                  _buildSectionLabel('profile.accountInformation'.tr()),
                  const SizedBox(height: AppSpacing.sm),
                  _buildReadOnlyField(
                    label: 'profile.username'.tr(),
                    value: user?.username ?? 'common.noData'.tr(),
                    icon: Icons.alternate_email,
                    isDark: isDark,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildReadOnlyField(
                    label: 'auth.email'.tr(),
                    value: user?.email ?? 'common.noData'.tr(),
                    icon: Icons.email_outlined,
                    isDark: isDark,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (user != null) ...[
                    _buildEmailVerificationCard(
                      user,
                      isDark: isDark,
                      primaryColor: primaryColor,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _buildLevelField(user: user, isDark: isDark),

                  const SizedBox(height: 40),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: AppColors.surfaceLight,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        elevation: 4,
                        shadowColor: primaryColor.withValues(alpha: 0.3),
                      ),
                      child: _isSaving
                          ? SizedBox(
                              width: 24,
                              height: AppSpacing.xl,
                              child: LottieLoadingWidget.tiny(),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.save_outlined, size: 20),
                                const SizedBox(width: AppSpacing.sm),
                                Flexible(
                                  child: Text(
                                    'profile.saveChanges'.tr(),
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
      ),
    );
  }

  Widget _buildAvatarSection(
    UserEntity? user,
    bool isDark,
    Color primaryColor,
    Color primaryDeepColor,
  ) {
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
                      primaryColor.withValues(alpha: 0.3),
                      primaryDeepColor.withValues(alpha: 0.3),
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
                      color: primaryColor.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _pickedAvatarBytes != null
                      ? Image.memory(
                          _pickedAvatarBytes!,
                          fit: BoxFit.cover,
                          width: 120,
                          height: 120,
                        )
                      : currentAvatar != null && currentAvatar.isNotEmpty
                      ? _buildAvatarImage(
                          currentAvatar,
                          fit: BoxFit.cover,
                          width: 120,
                          height: 120,
                          fallback: _buildDefaultAvatar(isDark, primaryColor),
                        )
                      : _buildDefaultAvatar(isDark, primaryColor),
                ),
              ),
              // Camera icon
              Positioned(
                bottom: 0,
                right: 0,
                child: TapTarget(
                  onTap: () => _showAvatarPicker(),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, primaryDeepColor],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.surfaceLight,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.4),
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
          const SizedBox(height: AppSpacing.md),
          Text(
            'profile.tapCameraToChangeAvatar'.tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColorRoles.textMuted(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar(bool isDark, Color primaryColor) {
    return Container(
      width: 120,
      height: 120,
      color: primaryColor.withValues(alpha: isDark ? 0.24 : 0.2),
      child: Icon(Icons.person, size: 60, color: primaryColor),
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
          color: Theme.of(context).colorScheme.outlineVariant,

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceLight.withValues(alpha: 0),
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.66,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Theme.of(context).colorScheme.outlineVariant
                          : Theme.of(context).colorScheme.outlineVariant,

                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'profile.chooseAvatar'.tr(),
                    style: Theme.of(context).textTheme.sectionTitle?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                            final normalized = AvatarUtils.normalizeAvatarUrl(
                              url,
                            );
                            setState(() {
                              _pickedAvatarBytes = null;
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
                                    ? primaryColor
                                    : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.6),

                                width: isSelected ? 3 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: primaryColor.withValues(
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,

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
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _pickAvatarFromDevice();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: AppColors.surfaceLight,
                        ),
                        icon: const Icon(Icons.upload_file),
                        label: Text('profile.uploadFromDevice'.tr()),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showCustomUrlDialog();
                        },
                        icon: const Icon(Icons.link),
                        label: Text('profile.useCustomUrl'.tr()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Matches the backend cap; the picker downsizes to 512 px so this is a safety net.
  static const _maxAvatarBytes = 2 * 1024 * 1024;

  Future<void> _pickAvatarFromDevice() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _maxAvatarBytes) {
        setState(
          () => _errorMessage = UiText.key('profile.avatarUploadFailed'),
        );
        return;
      }
      setState(() {
        _pickedAvatarBytes = bytes;
        _pickedAvatarName = file.name.isNotEmpty ? file.name : 'avatar.jpg';
        _errorMessage = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = UiText.key('profile.avatarUploadFailed'),
        );
      }
    }
  }

  void _showCustomUrlDialog() {
    final urlController = TextEditingController(
      text: _avatarUrlController.text,
    );
    final closed = showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: Text('profile.customAvatarUrl'.tr()),
          content: TextField(
            controller: urlController,
            decoration: InputDecoration(
              hintText: 'profile.avatarUrlHint'.tr(),
              prefixIcon: const Icon(Icons.link),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () {
                final normalized = AvatarUtils.normalizeAvatarUrl(
                  urlController.text,
                );
                setState(() {
                  _pickedAvatarBytes = null;
                  _selectedAvatarUrl = normalized;
                  _avatarUrlController.text = normalized ?? '';
                });
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColorRoles.primary(
                  Theme.of(context).brightness == Brightness.dark,
                ),
                foregroundColor: AppColors.surfaceLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: Text('profile.apply'.tr()),
            ),
          ],
        );
      },
    );
    // The route's future completes when pop starts; the field is still on
    // screen for the exit transition, so dispose only after it has played.
    closed.whenComplete(() => disposeAfterRoute([urlController]));
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
    required Color primaryColor,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: primaryColor, size: 20),
        filled: true,
        fillColor: isDark ? AppColors.grey900 : AppColors.grey50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.errorBright),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14,
        ),
      ),
    );
  }

  /// The working level, editable like the onboarding question. A level above
  /// the certified one is allowed but shows as unverified until the exam.
  Widget _buildLevelField({required UserEntity? user, required bool isDark}) {
    final theme = Theme.of(context);
    final level = user?.cefrLevel ?? 'A1';
    final verified = user?.levelVerified ?? true;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: user == null ? null : () => _pickLevel(user),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                Icons.school_outlined,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'profile.levelTitle'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      verified
                          ? level
                          : 'profile.levelUnverifiedValue'.tr(
                              namedArgs: {
                                'level': level,
                                'certified': user?.certifiedLevel ?? 'A1',
                              },
                            ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickLevel(UserEntity user) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        var selected = user.cefrLevel;
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'onboarding.levelQuestion'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'profile.levelPickerHint'.tr(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  CefrLevelPicker(
                    value: selected,
                    certifiedLevel: user.certifiedLevel,
                    onChanged: (code) => setSheetState(() => selected = code),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: selected == user.cefrLevel
                        ? null
                        : () => Navigator.of(sheetContext).pop(selected),
                    child: Text('common.save'.tr()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;

    if (cefrIndex(chosen) > cefrIndex(user.certifiedLevel)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('profile.levelAboveCertifiedTitle'.tr()),
          content: Text(
            'profile.levelAboveCertifiedBody'.tr(
              namedArgs: {'level': chosen, 'certified': user.certifiedLevel},
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('common.confirm'.tr()),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final ok = await context.read<ProficiencyProvider>().setWorkingLevel(
      chosen,
    );
    if (!mounted) return;
    if (ok) await LevelSync.afterLevelChange(context);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'profile.levelSaved'.tr(namedArgs: {'level': chosen})
              : 'errors.saveFailed'.tr(),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.grey900.withValues(alpha: 0.5)
            : AppColors.grey100,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 20,
          ),

          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? AppColors.onGradient.withValues(alpha: 0.7)
                        : AppColors.grey800,
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

  Widget _buildEmailVerificationCard(
    UserEntity user, {
    required bool isDark,
    required Color primaryColor,
  }) {
    final isVerified = user.isVerified;
    final statusColor = isVerified
        ? context.status.success
        : AppColors.warningDark;
    final backgroundColor = isVerified
        ? (isDark
              ? AppColors.greenSuccessDark.withValues(alpha: 0.22)
              : AppColors.greenSuccessBg)
        : (isDark
              ? AppColors.warningDark.withValues(alpha: 0.18)
              : AppColors.warningBg);

    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: statusColor.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isVerified
                  ? Icons.verified_rounded
                  : Icons.mark_email_unread_outlined,
              color: statusColor,
              size: 24,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isVerified
                        ? 'profile.emailVerified'.tr()
                        : 'profile.emailNotVerified'.tr(),
                    style: TextStyle(
                      color: isDark
                          ? Theme.of(context).colorScheme.onSurface
                          : AppColors.grey900,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!isVerified) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'profile.emailVerificationHint'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColorRoles.textSecondary(isDark),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed:
                              _isSendingVerification ||
                                  _isCheckingVerification ||
                                  _verificationCooldownSeconds > 0
                              ? null
                              : () => _sendVerificationEmail(user),
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: AppColors.surfaceLight,
                          ),
                          icon: _isSendingVerification
                              ? SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.surfaceLight,
                                  ),
                                )
                              : const Icon(Icons.outgoing_mail, size: 18),
                          label: Text(
                            _verificationCooldownSeconds > 0
                                ? '${'auth.emailVerificationResend'.tr()} '
                                      '(${_verificationCooldownSeconds}s)'
                                : 'auth.emailVerificationResend'.tr(),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              _isCheckingVerification || _isSendingVerification
                              ? null
                              : _checkVerificationStatus,
                          icon: _isCheckingVerification
                              ? SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: primaryColor,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text('profile.checkVerificationStatus'.tr()),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
