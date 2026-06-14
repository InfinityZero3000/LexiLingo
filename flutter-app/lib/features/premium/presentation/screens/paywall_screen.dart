import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:lexilingo_app/core/services/purchases_service.dart';

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
    final packages = await PurchasesService.instance.getOfferings();
    if (mounted) setState(() { _packages = packages; _loading = false; });
  }

  Future<void> _purchase(Package pkg) async {
    setState(() => _purchasing = true);
    try {
      final success = await PurchasesService.instance.purchase(pkg);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('premium.success'.tr())),
        );
        Navigator.of(context).pop(true);
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      final msg = (e.message?.isNotEmpty == true) ? e.message! : 'Purchase failed. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _purchasing = true);
    final success = await PurchasesService.instance.restore();
    if (!mounted) return;
    setState(() => _purchasing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'premium.restored'.tr() : 'premium.no_purchases'.tr()),
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
            colors: isDark
                ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
                : [const Color(0xFF6C63FF), const Color(0xFF3B1F8C)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const Spacer(),
              const Icon(Icons.workspace_premium_rounded, size: 80, color: Color(0xFFFFD700)),
              const SizedBox(height: 16),
              Text(
                'premium.title'.tr(),
                style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'premium.subtitle'.tr(),
                style: const TextStyle(fontSize: 16, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _buildFeatureList(),
              const Spacer(),
              if (_loading)
                const CircularProgressIndicator(color: Colors.white)
              else if (_packages.isEmpty)
                Text('premium.unavailable'.tr(),
                    style: const TextStyle(color: Colors.white70))
              else
                ..._packages.map(_buildPackageTile),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _purchasing ? null : _restore,
                child: Text(
                  'premium.restore'.tr(),
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 24),
            ],
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
      children: features.map((f) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
        child: Row(
          children: [
            Icon(f.$2, color: const Color(0xFFFFD700), size: 20),
            const SizedBox(width: 12),
            Text(f.$1.tr(), style: const TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      )).toList(),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: FilledButton(
        onPressed: _purchasing ? null : () => _purchase(pkg),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFFD700),
          foregroundColor: Colors.black87,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _purchasing
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
              )
            : Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}
