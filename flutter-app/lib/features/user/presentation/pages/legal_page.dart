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
      title: 'legal.privacy1Title'.tr(),
      body:
          'legal.privacy1Body'.tr(),
    ),
    _Section(
      title: 'legal.privacy2Title'.tr(),
      body:
          'legal.privacy2Body'.tr(),
    ),
    _Section(
      title: 'legal.privacy3Title'.tr(),
      body:
          'legal.privacy3Body'.tr(),
    ),
    _Section(
      title: 'legal.privacy4Title'.tr(),
      body:
          'legal.privacy4Body'.tr(),
    ),
    _Section(
      title: 'legal.privacy5Title'.tr(),
      body:
          'legal.privacy5Body'.tr(),
    ),
    _Section(
      title: 'legal.privacy6Title'.tr(),
      body:
          'legal.privacy6Body'.tr(),
    ),
    _Section(
      title: 'legal.privacy7Title'.tr(),
      body:
          'legal.privacy7Body'.tr(),
    ),
  ];

  List<Widget> _termsSections(BuildContext context) => [
    _Section(
      title: 'legal.terms1Title'.tr(),
      body:
          'legal.terms1Body'.tr(),
    ),
    _Section(
      title: 'legal.terms2Title'.tr(),
      body:
          'legal.terms2Body'.tr(),
    ),
    _Section(
      title: 'legal.terms3Title'.tr(),
      body:
          'legal.terms3Body'.tr(),
    ),
    _Section(
      title: 'legal.terms4Title'.tr(),
      body:
          'legal.terms4Body'.tr(),
    ),
    _Section(
      title: 'legal.terms5Title'.tr(),
      body:
          'legal.terms5Body'.tr(),
    ),
    _Section(
      title: 'legal.terms6Title'.tr(),
      body:
          'legal.terms6Body'.tr(),
    ),
    _Section(
      title: 'legal.terms7Title'.tr(),
      body:
          'legal.terms7Body'.tr(),
    ),
    _Section(
      title: 'legal.terms8Title'.tr(),
      body: 'legal.terms8Body'.tr(),
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
