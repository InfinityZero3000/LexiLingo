import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:lexilingo_app/core/di/injection_container.dart' as di;
import 'package:lexilingo_app/core/services/entitlement_service.dart';
import 'package:lexilingo_app/core/services/purchases_service.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

abstract final class _PaywallPalette {
  static const night = [Color(0xFF1A1A2E), Color(0xFF16213E)];
  static const violet = [Color(0xFF6C63FF), Color(0xFF3B1F8C)];
}

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  List<Package> _packages = [];
  bool _loading = true;
  bool _purchasing = false;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    if (!_loading) setState(() => _loading = true);
    List<Package> packages;
    try {
      packages = await PurchasesService.instance.getOfferings();
    } catch (_) {
      packages = const [];
    }
    if (mounted) {
      setState(() {
        _packages = packages;
        _loading = false;
      });
    }
  }

  Future<void> _purchase(Package pkg) async {
    setState(() => _purchasing = true);
    try {
      final success = await PurchasesService.instance.purchase(pkg);
      if (!mounted) return;
      if (success) {
        await di.sl<EntitlementService>().sync();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('premium.success'.tr())));
        Navigator.of(context).pop(true);
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      final msg = (e.message?.isNotEmpty == true)
          ? e.message!
          : 'premium.purchaseFailed'.tr();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('premium.purchaseFailed'.tr())));
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _purchasing = true);
    var success = false;
    try {
      success = await PurchasesService.instance.restore();
      if (success) await di.sl<EntitlementService>().sync();
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    setState(() => _purchasing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'premium.restored'.tr() : 'premium.no_purchases'.tr(),
        ),
      ),
    );
    if (success && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark ? _PaywallPalette.night : _PaywallPalette.violet,
          ),
        ),
        child: ContentWidth(
          maxWidth: ContentWidth.reading,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: Icon(
                              Icons.close,
                              color: AppColors.onGradient.withValues(
                                alpha: 0.7,
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.workspace_premium_rounded,
                          size: 80,
                          color: AppColors.gold,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'premium.title'.tr(),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.onGradient,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'premium.subtitle'.tr(),
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: AppColors.onGradient.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        _buildFeatureList(),
                        const Spacer(),
                        if (_loading)
                          const CircularProgressIndicator(
                            color: AppColors.onGradient,
                          )
                        else if (_packages.isEmpty)
                          Column(
                            children: [
                              Text(
                                'premium.unavailable'.tr(),
                                style: TextStyle(
                                  color: AppColors.onGradient.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _loadOfferings,
                                child: Text(
                                  'common.retry'.tr(),
                                  style: const TextStyle(
                                    color: AppColors.onGradient,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          ..._packages.map(_buildPackageTile),
                        const SizedBox(height: AppSpacing.md),
                        TextButton(
                          onPressed: _purchasing ? null : _restore,
                          child: Text(
                            'premium.restore'.tr(),
                            style: TextStyle(
                              color: AppColors.onGradient.withValues(
                                alpha: 0.54,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureList() {
    final features = [
      ('premium.feature_unlimited', Icons.all_inclusive_rounded),
      ('premium.feature_ai', Icons.psychology_rounded),
      ('premium.feature_offline', Icons.download_done_rounded),
      ('premium.feature_ads', Icons.block_rounded),
    ];

    return Column(
      children: features
          .map(
            (f) => Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
                vertical: 4,
              ),
              child: Row(
                children: [
                  Icon(f.$2, color: AppColors.gold, size: 20),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      f.$1.tr(),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.onGradient,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildPackageTile(Package pkg) {
    final price = pkg.storeProduct.priceString;
    final title = pkg.packageType == PackageType.monthly
        ? 'premium.monthly'.tr(namedArgs: {'price': price})
        : pkg.packageType == PackageType.annual
        ? 'premium.annual'.tr(namedArgs: {'price': price})
        : price;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 6,
      ),
      child: FilledButton(
        onPressed: _purchasing ? null : () => _purchase(pkg),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.textDark,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: _purchasing
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textDark.withValues(alpha: 0.54),
                ),
              )
            : Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
