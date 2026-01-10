import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import '../../../../features/vocabulary/presentation/pages/vocab_library_page.dart';
// import '../../../../features/chat/presentation/pages/chat_page.dart'; // Navigating to MainScreen tab usually, or direct push?

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 2),
                        image: const DecorationImage(
                          image: NetworkImage(
                              "https://lh3.googleusercontent.com/aida-public/AB6AXuAurKSaXqaZ-IaiMAcT3KMITCrOQOcCot10vznpkbDx8taTBQM17RM60Ge89X-lH5jDBY1vrTMOb1SaVuwiPzEQL9j2WoH9LzQvbAjXah05VfCOuolR2CzyDMj8ZHSyPCHqv_6f5w74XGYDumpynOnR8q8yLgQLeifHmt0eKAKU_O_brfi58u7Wd0OPIIAZ6BWipM8WPMBJqWdE3h0T86RcKFgpIsdEbpkNoDkCAwubT7GoN4h1GjGoFgGGrMq5PKCwviScgJKwVaUB"),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Welcome back',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                      color: AppColors.textGrey,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.5)),
                          Text('Alex Johnson!',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: const Icon(Icons.notifications_outlined),
                    )
                  ],
                ),
              ),

              // Streak Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFfef9c3), Color(0xFFdcfce7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.shade100),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('DAILY MOMENTUM',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: Colors.green.shade800,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.5)),
                              const SizedBox(height: 4),
                              Text('12 Day Streak',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                          color: AppColors.textDark,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -1)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFACC15), // Yellow-400
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.local_fire_department,
                                color: Colors.white, size: 28),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Days Row
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildDayItem('M', true),
                            _buildDayItem('T', true),
                            _buildDayItem('W', true),
                            _buildDayItem('T', false, isCurrent: true),
                            _buildDayItem('F', false, isFuture: true),
                            _buildDayItem('S', false, isFuture: true),
                            _buildDayItem('S', false, isFuture: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text("You're on fire! Keep the habit going.",
                              style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14)),
                        ],
                      )
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text('Your Daily Goal',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold, fontSize: 20)),
              ),

              // Daily Goal Card
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ],
                  border: Border.all(color: Colors.grey.withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bolt, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text('Daily XP Goal',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Text('450 / 500 XP',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: 0.9,
                        minHeight: 12,
                        backgroundColor:
                            Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[700]
                                : const Color(0xFFDBE0E6),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'Almost there! Just one more lesson to reach your target.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textGrey)),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text('Current Lesson',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold, fontSize: 20)),
              ),

              // Current Lesson Card
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ],
                  border: Border.all(color: Colors.grey.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Intermediate Phrasal Verbs',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('65% complete • Unit 4',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textGrey)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.play_arrow, size: 20),
                            label: const Text('Resume'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: Container(
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          image: const DecorationImage(
                            image: NetworkImage(
                                "https://lh3.googleusercontent.com/aida-public/AB6AXuCBLMT0S9uHRnKrgluXdATR_fLs_0j0ue1Ee1zevHj-zgRfLKkCoSn6WP_eBRa-Oj1fC793G4-ZXO2ZRJcLN4n-HkpnLSKvu3K96qkANmCUwNT_Vc-ZT5Gat0msJ0mEYmPIT99pzOPB55BunvmvyWnwTaWl_L_-h9pb-zlML2cjeiToRk_ZpuHQ4t4dI1Y2lUYzLpftS-T4tciIQWixlHVNirgN8tuPFi0mcbsOgWjDduE8OQd1lOEOQjZGhM2ACtF1qa8cDo_wQt_e"),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text('Short Activities',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold, fontSize: 20)),
              ),

              // Short Activities Grid
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector( // Add InkWell/GestureDetector
                        onTap: () {
                          // Navigate to Chat?
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.primary.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.smart_toy,
                                    color: Colors.white),
                              ),
                              const SizedBox(height: 12),
                              Text('AI Tutor',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                              Text('5 min chat',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.textGrey, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const VocabLibraryPage()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED), // Orange-50
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade100),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.style,
                                    color: Colors.white),
                              ),
                              const SizedBox(height: 12),
                              Text('Vocabulary',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textDark)),
                              Text('20 new cards',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.textGrey, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayItem(String day, bool completed,
      {bool isCurrent = false, bool isFuture = false}) {
    return Column(
      children: [
        Text(day,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isCurrent ? AppColors.primary : Colors.grey)),
        const SizedBox(height: 4),
        if (completed)
          const Icon(Icons.check_circle, color: Colors.green, size: 20)
        else if (isCurrent)
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            padding: const EdgeInsets.all(6),
            child: Container(
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
            ),
          )
        else
          Icon(Icons.circle,
              color: Colors.grey.withOpacity(0.4), size: 20),
      ],
    );
  }
}
