import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, this.initialToken});

  final String? initialToken;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tokenController;
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isResetDone = false;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.initialToken ?? '');
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.accentMintDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('auth.createNewPassword'.tr()),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'auth.setNewPassword'.tr(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.onGradient
                            : AppColors.surfaceDarkInput,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'auth.useResetToken'.tr(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? Colors.white70
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextFormField(
                      controller: _tokenController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'auth.resetToken'.tr(),
                        prefixIcon: const Icon(Icons.vpn_key_outlined),
                        filled: true,
                        fillColor: isDark
                            ? AppColors.surfaceDarkInput
                            : AppColors.onGradient,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'auth.pleaseEnterResetToken'.tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: !_isNewPasswordVisible,
                      decoration: InputDecoration(
                        labelText: 'auth.newPassword'.tr(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isNewPasswordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _isNewPasswordVisible = !_isNewPasswordVisible;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: isDark
                            ? AppColors.surfaceDarkInput
                            : AppColors.onGradient,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'auth.pleaseEnterNewPassword'.tr();
                        }
                        if (value.length < 8) {
                          return 'auth.passwordMinLength'.tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: !_isConfirmPasswordVisible,
                      decoration: InputDecoration(
                        labelText: 'auth.confirmNewPassword'.tr(),
                        prefixIcon: const Icon(Icons.lock_reset),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isConfirmPasswordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _isConfirmPasswordVisible =
                                  !_isConfirmPasswordVisible;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: isDark
                            ? AppColors.surfaceDarkInput
                            : AppColors.onGradient,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'auth.pleaseConfirmNewPassword'.tr();
                        }
                        if (value != _newPasswordController.text) {
                          return 'auth.passwordMismatch'.tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: authProvider.isLoading
                            ? null
                            : () async {
                                if (!_formKey.currentState!.validate()) return;
                                final messenger = ScaffoldMessenger.of(context);
                                final success = await authProvider
                                    .resetPassword(
                                      token: _tokenController.text.trim(),
                                      newPassword: _newPasswordController.text,
                                    );

                                if (!mounted) return;

                                if (success) {
                                  setState(() => _isResetDone = true);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'auth.passwordUpdatedSuccess'.tr(),
                                      ),
                                    ),
                                  );
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentMint,
                          foregroundColor: AppColors.accentMintDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          elevation: 0,
                        ),
                        child: authProvider.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: LottieLoadingWidget.tiny(),
                              )
                            : Text(
                                'auth.updatePassword'.tr(),
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                    if (_isResetDone) ...[
                      const SizedBox(height: AppSpacing.lg),
                      TextButton(
                        onPressed: () {
                          Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst);
                        },
                        child: Text('auth.backToLogin'.tr()),
                      ),
                    ],
                    if (authProvider.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                authProvider.errorMessage!,
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
