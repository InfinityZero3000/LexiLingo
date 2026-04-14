import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'forgot_password_page.dart';
import 'register_page.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const int _maxFailedAttempts = 5;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  int _failedAttempts = 0;

  bool get _isLockedAfterFailures => _failedAttempts >= _maxFailedAttempts;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isInvalidCredentialMessage(String? message) {
    if (message == null) return false;
    final normalized = message.toLowerCase();
    return normalized.contains('incorrect email or password') ||
        normalized.contains('invalid email or password') ||
        normalized.contains('auth_invalid');
  }

  Future<void> _openForgotPassword() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordPage(
          initialEmail: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.accentMintDark
          : AppColors.backgroundLight,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top app bar
                    Row(
                      children: [
                        canPop
                            ? IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: Icon(
                                  Icons.arrow_back,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.surfaceDarkInput,
                                ),
                              )
                            : const SizedBox(width: 48),
                        Expanded(
                          child: Text(
                            'LexiLingo',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.surfaceDarkInput,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Hero
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 200,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0x3330E8E8), Color(0x2230E8E8)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Image.network(
                          'https://lh3.googleusercontent.com/aida-public/AB6AXuC9e5sG5ITzGQOOtLmmixgmi3eqy1u2vjREx5V2LGBCdNg_bgu7OQarns0X8kgNuuuRN6bV1yWvZej9RBzXmsN0DYptA_CsuDNIuGLUOa_JlGU5R_fFBaQJZgQnWOvW6YVqMVd3tVGfLxAGrmQuwwyVsPQdEpGwB3E_bGE4Zbdw5Eya67psT55Ru81ggipsdLz1q7mHhNths64jCip1sXDvPCi_RBDeHWeza1RJmiuGVC9FfcWdVPLMLPZd2XM9pzu5ezA_FzA2O5g',
                          fit: BoxFit.cover,
                          errorBuilder: (context, _, __) => const Center(
                            child: Icon(Icons.language, size: 64),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Text(
                      'Welcome Back',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.surfaceDarkInput,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Continue your English language journey',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark ? Colors.white70 : AppColors.textSlateLight,
                      ),
                    ),
                    const SizedBox(height: 28),

                    Text(
                      'Email Address',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.surfaceDarkInput,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'name@example.com',
                        prefixIcon: const Icon(Icons.mail_outline),
                        filled: true,
                        fillColor: isDark ? AppColors.surfaceDarkInput : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Password',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : AppColors.surfaceDarkInput,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _openForgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: isDark ? AppColors.surfaceDarkInput : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: authProvider.isLoading || _isLockedAfterFailures
                            ? null
                            : () async {
                                if (_formKey.currentState!.validate()) {
                                  final messenger = ScaffoldMessenger.of(context);
                                  await authProvider.signInWithEmailPassword(
                                    _emailController.text.trim(),
                                    _passwordController.text,
                                  );

                                  if (!mounted) return;

                                  if (authProvider.isAuthenticated) {
                                    setState(() => _failedAttempts = 0);
                                  } else if (_isInvalidCredentialMessage(
                                    authProvider.errorMessage,
                                  )) {
                                    setState(() => _failedAttempts += 1);

                                    if (_isLockedAfterFailures) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'You entered the wrong password 5 times. Please reset your password.',
                                          ),
                                        ),
                                      );
                                      await _openForgotPassword();
                                    }
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentMint,
                          foregroundColor: AppColors.accentMintDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: authProvider.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(
                                'Sign In',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),

                    if (!_isLockedAfterFailures && _failedAttempts > 0) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Wrong credentials $_failedAttempts/$_maxFailedAttempts times.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],

                    if (_isLockedAfterFailures) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, color: Colors.orange.shade700),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Login is temporarily disabled after 5 failed attempts. Please use Forgot password.',
                                style: TextStyle(color: Colors.orange.shade800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: isDark
                                ? AppColors.surfaceDarkMuted
                                : AppColors.slate200,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Or login with',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isDark
                                  ? AppColors.textMuted
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: isDark
                                ? AppColors.surfaceDarkMuted
                                : AppColors.slate200,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: OutlinedButton.icon(
                              onPressed: authProvider.isLoading
                                  ? null
                                  : () async {
                                      await authProvider.signInWithGoogle();
                                    },
                              icon: const Icon(Icons.g_mobiledata, size: 26),
                              label: const Text('Google'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: OutlinedButton.icon(
                              onPressed: authProvider.isLoading
                                  ? null
                                  : () async {
                                      await authProvider.signInWithFacebook();
                                    },
                              icon: const Icon(Icons.facebook, size: 22),
                              label: const Text('Facebook'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Don\'t have an account?',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark ? Colors.white70 : AppColors.textSlate,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RegisterPage(),
                              ),
                            );
                          },
                          child: const Text(
                            'Sign up for free',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),

                    if (authProvider.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade700),
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
                    const SizedBox(height: 16),
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
