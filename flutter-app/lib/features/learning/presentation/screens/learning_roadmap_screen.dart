import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Learning Roadmap Screen
/// Displays course progress in a vertical roadmap/learning path design
/// Similar to Duolingo's path visualization
class LearningRoadmapScreen extends ConsumerStatefulWidget {
  final String courseId;
  
  const LearningRoadmapScreen({
    super.key,
    required this.courseId,
  });

  @override
  ConsumerState<LearningRoadmapScreen> createState() => _LearningRoadmapScreenState();
}

class _LearningRoadmapScreenState extends ConsumerState<LearningRoadmapScreen> 
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TODO: Get roadmap data from provider
    // final roadmap = ref.watch(courseRoadmapProvider(widget.courseId));
    
    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // App Bar
          _buildSliverAppBar(context),
          
          // Progress Stats Header
          SliverToBoxAdapter(
            child: _buildProgressHeader(context),
          ),
          
          // Roadmap (Units & Lessons)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return _buildUnitCard(
                    context,
                    index,
                    _getMockUnitData(index),
                  );
                },
                childCount: 8, // Mock data
              ),
            ),
          ),
          
          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 100),
          ),
        ],
      ),
      
      // Floating Action Button - Continue Learning
      floatingActionButton: _buildContinueButton(context),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Theme.of(context).colorScheme.primary,
      flexibleSpace: FlexibleSpaceBar(
        title: const Text(
          'PrepTalk - 500 từ vựng',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withOpacity(0.8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Completed 1/10 units',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: 0.1,
              minHeight: 12,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Stats Row
          Row(
            children: [
              _buildStatChip(
                icon: Icons.emoji_events,
                label: '125 XP',
                color: Colors.amber,
              ),
              const SizedBox(width: 8),
              _buildStatChip(
                icon: Icons.local_fire_department,
                label: '5 day streak',
                color: Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color.darken(20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitCard(BuildContext context, int index, Map<String, dynamic> unitData) {
    final isCurrentUnit = index == 0;
    final lessons = unitData['lessons'] as List<Map<String, dynamic>>;
    
    return FadeTransition(
      opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _animController,
          curve: Interval(
            index * 0.05,
            (index * 0.05) + 0.2,
            curve: Curves.easeOut,
          ),
        ),
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _animController,
            curve: Interval(
              index * 0.05,
              (index * 0.05) + 0.2,
              curve: Curves.easeOut,
            ),
          ),
        ),
        child: Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: isCurrentUnit
                ? BorderSide(color: Colors.green.shade400, width: 2)
                : BorderSide.none,
          ),
          elevation: isCurrentUnit ? 4 : 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: isCurrentUnit
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.green.shade50,
                        Colors.white,
                      ],
                    )
                  : null,
            ),
            child: Column(
              children: [
                // Unit Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isCurrentUnit ? Colors.green.shade400 : Colors.grey.shade100,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isCurrentUnit ? Colors.green : Colors.grey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isCurrentUnit)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Unit in progress',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              unitData['title'],
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isCurrentUnit ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              unitData['subtitle'],
                              style: TextStyle(
                                fontSize: 13,
                                color: isCurrentUnit ? Colors.white.withOpacity(0.9) : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Lessons
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: lessons.asMap().entries.map((entry) {
                      final lessonIndex = entry.key;
                      final lesson = entry.value;
                      return _buildLessonItem(
                        context,
                        lessonIndex,
                        lesson,
                        isLast: lessonIndex == lessons.length - 1,
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLessonItem(
    BuildContext context,
    int index,
    Map<String, dynamic> lesson,
    {bool isLast = false}
  ) {
    final status = lesson['status'] as String;
    final isCompleted = status == 'completed';
    final isLocked = status == 'locked';
    final isCurrent = status == 'current';
    
    Color getColor() {
      if (isCompleted) return Colors.green;
      if (isCurrent) return Colors.blue;
      if (isLocked) return Colors.grey.shade400;
      return Colors.grey.shade300;
    }
    
    IconData getIcon() {
      if (isCompleted) return Icons.check_circle;
      if (isLocked) return Icons.lock;
      return Icons.play_circle_fill;
    }
    
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress line and icon
          Column(
            children: [
              GestureDetector(
                onTap: isLocked ? null : () => _onLessonTap(lesson),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: getColor(),
                    shape: BoxShape.circle,
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    getIcon(),
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 3,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isCompleted ? Colors.green.shade200 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
          
          const SizedBox(width: 16),
          
          // Lesson info
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: isLast ? 0 : 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCurrent ? Colors.blue.shade50 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: isCurrent
                    ? Border.all(color: Colors.blue.shade200, width: 2)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'LESSON ${index + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (isCompleted)
                        Row(
                          children: List.generate(
                            lesson['stars'] ?? 0,
                            (i) => Icon(
                              Icons.star,
                              size: 16,
                              color: Colors.amber.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lesson['title'],
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lesson['subtitle'],
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: FloatingActionButton.extended(
        onPressed: () => _onContinueLearning(),
        backgroundColor: Colors.green,
        elevation: 4,
        icon: const Icon(Icons.play_arrow, size: 28),
        label: const Text(
          'CONTINUE LEARNING',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  void _onLessonTap(Map<String, dynamic> lesson) {
    // TODO: Navigate to lesson screen
    print('Starting lesson: ${lesson['title']}');
  }

  void _onContinueLearning() {
    // TODO: Continue to current lesson
    print('Continue learning');
  }

  Map<String, dynamic> _getMockUnitData(int index) {
    final units = [
      {
        'title': 'CORPORATE FINANCE',
        'subtitle': '0/1 Section',
        'lessons': [
          {
            'title': 'Introduction to Finance',
            'subtitle': 'Learn basic concepts',
            'status': 'current',
            'stars': 0,
          },
        ],
      },
      {
        'title': 'CURRENT EVENTS AND TRENDS',
        'subtitle': '0/1 Section',
        'lessons': [
          {
            'title': 'Market Analysis',
            'subtitle': 'Understanding trends',
            'status': 'locked',
            'stars': 0,
          },
        ],
      },
      {
        'title': 'ETHICS AND CORPORATE',
        'subtitle': '0/1 Section',
        'lessons': [
          {
            'title': 'Business Ethics',
            'subtitle': 'Core principles',
            'status': 'locked',
            'stars': 0,
          },
        ],
      },
      {
        'title': 'FINANCIAL ANALYSIS',
        'subtitle': '0/1 Section',
        'lessons': [
          {
            'title': 'Financial Statements',
            'subtitle': 'Reading & interpretation',
            'status': 'locked',
            'stars': 0,
          },
        ],
      },
      {
        'title': 'FINANCIAL COMMUNICATION',
        'subtitle': '0/1 Section',
        'lessons': [
          {
            'title': 'Presenting Data',
            'subtitle': 'Effective communication',
            'status': 'locked',
            'stars': 0,
          },
        ],
      },
      {
        'title': 'FINANCIAL INSTITUTIONS',
        'subtitle': '0/1 Section',
        'lessons': [
          {
            'title': 'Banking Systems',
            'subtitle': 'How banks work',
            'status': 'locked',
            'stars': 0,
          },
        ],
      },
      {
        'title': 'FINANCIAL MODELING',
        'subtitle': '0/1 Section',
        'lessons': [
          {
            'title': 'Building Models',
            'subtitle': 'Excel & forecasting',
            'status': 'locked',
            'stars': 0,
          },
        ],
      },
      {
        'title': 'RISK MANAGEMENT',
        'subtitle': '0/1 Section',
        'lessons': [
          {
            'title': 'Risk Assessment',
            'subtitle': 'Identifying & mitigating risks',
            'status': 'locked',
            'stars': 0,
          },
        ],
      },
    ];
    
    return units[index % units.length];
  }
}

// Extension for color manipulation
extension ColorExtension on Color {
  Color darken([int percent = 10]) {
    assert(1 <= percent && percent <= 100);
    final f = 1 - percent / 100;
    return Color.fromARGB(
      alpha,
      (red * f).round(),
      (green * f).round(),
      (blue * f).round(),
    );
  }
}
