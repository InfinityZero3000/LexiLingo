import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';

class AdsScreen extends StatelessWidget {
  const AdsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text('Banner & Ads',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quản lý chiến dịch banner, CTA và quảng cáo in-app.',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            // Feature overview cards
            _FeatureCard(
              icon: Icons.image_outlined,
              title: 'Banner Quảng Cáo',
              desc: 'Quản lý banner hero, sidebar, interstitial với lịch hiển thị.',
            ),
            const SizedBox(height: 12),
            _FeatureCard(
              icon: Icons.schedule_outlined,
              title: 'Lập Lịch',
              desc: 'Đặt thời gian bắt đầu/kết thúc, A/B testing giữa các banner.',
            ),
            const SizedBox(height: 12),
            _FeatureCard(
              icon: Icons.person_search_outlined,
              title: 'Targeting',
              desc: 'Hiển thị banner theo level, ngôn ngữ, hoạt động người dùng.',
            ),
            const SizedBox(height: 12),
            _FeatureCard(
              icon: Icons.preview_outlined,
              title: 'Preview',
              desc: 'Xem trước giao diện banner trên mobile và web.',
            ),
            const SizedBox(height: 32),
            // Coming soon banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBright,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.campaign_outlined,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text('Coming Soon',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Module quản lý banner & quảng cáo sẽ được triển khai trong giai đoạn tiếp theo. Theo dõi changelog để cập nhật mới nhất.',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        color: Colors.white60,
                        height: 1.5),
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

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface)),
                const SizedBox(height: 2),
                Text(desc,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 12, color: AppColors.onSurfaceMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
