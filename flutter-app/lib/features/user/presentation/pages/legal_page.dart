import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

enum LegalPageType { privacyPolicy, termsOfService }

class LegalPage extends StatelessWidget {
  final LegalPageType type;

  const LegalPage({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = type == LegalPageType.privacyPolicy
        ? 'legal.privacy_title'.tr()
        : 'legal.terms_title'.tr();
    final sections = type == LegalPageType.privacyPolicy
        ? _privacySections(context)
        : _termsSections(context);

    return Scaffold(
      appBar: AppBar(title: Text(title), leading: const AppBackButton()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(
            'legal.last_updated'.tr(namedArgs: {'date': 'June 2025'}),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColorRoles.textMuted(isDark),
            ),
          ),
          const SizedBox(height: 20),
          ...sections,
        ],
      ),
    );
  }

  List<Widget> _privacySections(BuildContext context) => [
    _Section(
      title: '1. Information We Collect',
      body:
          'We collect information you provide directly, such as your name, email address, and learning preferences. We also collect usage data to improve your learning experience.',
    ),
    _Section(
      title: '2. How We Use Your Information',
      body:
          'We use your information to personalize your learning path, track progress, send study reminders, and improve our AI tutoring features. We never sell your personal data to third parties.',
    ),
    _Section(
      title: '3. Data Storage & Security',
      body:
          'Your data is stored on secure servers. We use industry-standard encryption in transit (TLS) and at rest. Firebase Authentication manages your login credentials.',
    ),
    _Section(
      title: '4. Third-Party Services',
      body:
          'LexiLingo integrates with Google (Firebase, YouTube), which have their own privacy policies. We use Sentry for error monitoring — error reports may include anonymized device information.',
    ),
    _Section(
      title: '5. Your Rights',
      body:
          'You can request access to, correction of, or permanent deletion of your personal data at any time through Settings → Account → Delete Account. Deletion is irreversible and processed immediately.',
    ),
    _Section(
      title: '6. Children\'s Privacy',
      body:
          'LexiLingo is not directed at children under 13. We do not knowingly collect personal information from children under 13.',
    ),
    _Section(
      title: '7. Contact',
      body:
          'For privacy inquiries, contact us at privacy@lexilingo.app. We will respond within 30 days.',
    ),
  ];

  List<Widget> _termsSections(BuildContext context) => [
    _Section(
      title: '1. Acceptance',
      body:
          'By using LexiLingo, you agree to these Terms. If you do not agree, please do not use the app.',
    ),
    _Section(
      title: '2. Account',
      body:
          'You are responsible for maintaining the security of your account and for all activities that occur under your account. Notify us immediately of any unauthorized use.',
    ),
    _Section(
      title: '3. Acceptable Use',
      body:
          'You agree not to misuse LexiLingo, including attempting to reverse-engineer the app, submitting false information, or using automated tools to manipulate learning scores or leaderboards.',
    ),
    _Section(
      title: '4. Intellectual Property',
      body:
          'All content, features, and AI-generated responses in LexiLingo are owned by or licensed to LexiLingo. You may not reproduce or distribute content without permission.',
    ),
    _Section(
      title: '5. Virtual Goods',
      body:
          'XP, Coins, and virtual items have no real-world monetary value and cannot be transferred or exchanged for cash. We reserve the right to modify or discontinue virtual goods at any time.',
    ),
    _Section(
      title: '6. Disclaimer',
      body:
          'LexiLingo is provided "as is". We make no guarantees about learning outcomes. AI responses are generated and may contain errors — always consult a qualified language teacher for critical needs.',
    ),
    _Section(
      title: '7. Termination',
      body:
          'We reserve the right to suspend or terminate accounts that violate these Terms. You may delete your account at any time through Settings.',
    ),
    _Section(
      title: '8. Governing Law',
      body: 'These Terms are governed by the laws of Vietnam.',
    ),
  ];
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.white70 : AppColors.textSlate,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
