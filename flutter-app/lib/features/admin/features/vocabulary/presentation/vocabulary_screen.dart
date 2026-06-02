import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  List<Map<String, dynamic>> _words = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await ApiClient.instance.get('/admin/vocabulary', params: {'page': 1, 'page_size': 20});
      final data = resp['data'];
      final list = data is Map ? data['items'] ?? data['vocabulary'] ?? [] : data ?? [];
      if (mounted) {
        setState(() {
          _words = List<Map<String, dynamic>>.from(list);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text('Vocabulary Library',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        actions: [
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download_outlined, size: 14),
            label: Text('Export CSV',
                style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manage interactive flashcards and student performance metrics.',
              style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            // Stats
            Row(children: [
              Expanded(
                child: _VocabStat(label: 'TOTAL WORDS', value: '4,821', icon: Icons.book_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _VocabStat(label: 'GLOBAL MASTERY', value: '74%', icon: Icons.trending_up),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _VocabStat(
                    label: 'CRITICAL REVIEWS', value: '128', icon: Icons.timer_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _VocabStat(
                    label: 'DAILY VIEWS', value: '12.5k', icon: Icons.visibility_outlined),
              ),
            ]),
            const SizedBox(height: 24),
            Text('Active Curriculum Cards',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator(color: AppColors.primary))
            else if (_words.isEmpty)
              ..._defaultWords.map(_buildWordCard)
            else
              ..._words.map(_buildWordCard),
          ],
        ),
      ),
    );
  }

  static final _defaultWords = [
    {'word': 'Ephemeral', 'ipa': '/ɪˈfem(ə)r(ə)l/', 'level': 'A2 INTERMEDIATE'},
    {'word': 'Serendipity', 'ipa': '/ˌserənˈdɪpɪti/', 'level': 'C1 ADVANCED'},
    {'word': 'Vivid', 'ipa': '/ˈvɪvɪd/', 'level': 'B1 INTERMEDIATE'},
    {'word': 'Melancholy', 'ipa': '/ˈmelənkɒli/', 'level': 'B2 UPPER-INT'},
    {'word': 'Eloquent', 'ipa': '/ˈeləkwənt/', 'level': 'B2 UPPER-INT'},
    {'word': 'Apple', 'ipa': '/ˈap(ə)l/', 'level': 'A1 BEGINNER'},
  ];

  Widget _buildWordCard(Map<String, dynamic> w) {
    final word = w['word'] ?? w['word_text'] ?? '';
    final ipa = w['ipa'] ?? w['phonetic'] ?? '';
    final level = w['level'] ?? w['difficulty_level'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              level.toString().toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              word,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: -0.02,
              ),
            ),
          ),
          if (ipa.isNotEmpty) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                ipa,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 14, color: AppColors.onSurfaceVariant),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 0.6,
              backgroundColor: AppColors.surfaceContainerHigh,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class _VocabStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _VocabStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: 8),
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 0.08, color: AppColors.onSurfaceMuted)),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 24, fontWeight: FontWeight.w700,
                  color: AppColors.onSurface, letterSpacing: -0.02)),
        ],
      ),
    );
  }
}
