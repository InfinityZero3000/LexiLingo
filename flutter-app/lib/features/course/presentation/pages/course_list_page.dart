import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/course/domain/entities/course.dart';

class CourseListPage extends StatelessWidget {
  const CourseListPage({super.key});

  @override
  Widget build(BuildContext context) {
    // We might want to fetch courses on init, assuming main.dart or provider init does it.
    // Provider.of<CourseProvider>(context, listen: false).loadCourses(); // If needed to trigger load
    
    final courseProvider = Provider.of<CourseProvider>(context);
    final courses = courseProvider.courses;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Learning Courses'),
        leading: GestureDetector(
          onTap: () {
             // Maybe switch tab or pop? If it's a tab, back button isn't usually there unless navigated to.
             // But design shows back button.
          },
          child: const Icon(Icons.arrow_back_ios, size: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Daily Habit
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Daily Habit',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        Text('Practice AI Conversation',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontSize: 16)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                          color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.mic, color: Colors.white),
                    )
                  ],
                ),
              ),
            ),
            
            // Course List
            if (courses.isEmpty)
               // Show skeleton or hardcoded demo if DB is empty to match "y chang" request?
               // I'll add the Hardcoded Demo items from HTML if courses are empty,
               // to ensure the UI looks right immediately as requested.
               _buildDemoList(context)
            else
               ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: courses.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  return _CourseCard(course: courses[index]);
                },
              ),
              const SizedBox(height: 80), // Bottom padding
          ],
        ),
      ),
    );
  }

  Widget _buildDemoList(BuildContext context) {
    return Column(
      children: const [
        _DemoCourseCard(
          category: "Grammar & Basics",
          title: "Beginner Path",
          subtitle: "Start your journey with basic phrases and daily greetings.",
          progress: 0.45,
          lessons: "12/30 Lessons",
          imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuDSgBnCW0jvJgf-Nxcog8rxc8sqp7x1ZGy__-lXf8pDRRyY0UVvhlRfcNT8uV-8ivezgKEJYagvz-Ppop9aN1Jdg39RGROT6uAemGBPvK17QM11sIOkX5WHAfMVBdIqsgjiga0YegCou6Z5RIHjlikk22nh-w61gcygOhvgiFPyN6drRJcQFbbJVsTgQOZiTQedICW9WrM7efcpxo5trF4QbIWCdjreHdaZ3qDBPvWQzBYCTFB27MjZ9c_SiyNX3GJVACQ3Gb2hEf5i",
        ),
        SizedBox(height: 16),
        _DemoCourseCard(
          category: "Fluency Focus",
          title: "Intermediate Path",
          subtitle: "Improve your fluency and master complex sentence structures.",
          progress: 0.15,
          lessons: "5/45 Lessons",
          imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuCoyJyr2IOMdN0vbHwkxVbw2epPh1jAU9GtK_s6HGX1GqiKAZ1oA2yapIvDtSSLCV4QezFkmZhnacrE5gF2xUa2iQ4hzEZSA4525roedjhkIPLlpGBOLXXSsEa4tWO0nRNdKpcOXPe9SRo5zFI2vxhe1fmPKCBIy4e1r9a5eL0PdxXFsX5EJQcfeUoYQAgvXYFD2aKTVJLYv7016a4QVOfrgR8XWT9Ld3FqikOEIqKwf8bafUT30XdG9U5QtNyT-gZobaUy0DIHt3Hi",
        ),
        SizedBox(height: 16),
        _DemoCourseCard(
           category: "Exam Prep",
           title: "TOEIC Master",
           subtitle: "Targeted practice for workplace communication and exam success.",
           progress: 0.0,
           lessons: "60 Lessons total",
           imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuBQUFRFJzNyhDBV4dCp5BU2d-3621-QR3J7pnEF7A07P3AEkEoyi65YWHuWxs1ucMf_1bBnQ65c2JOK5XA39F5Qm7mPkx_6J_hlJYUTP3Ew20j1WFMo71iKZS6bz0qaZGCUpFgf2UyMO-jpRKvmZdEF6Q2wyqQ_me439GXSWWRfrCg75A5CJXKRuYY_NKCwcFHdS1NRX65EWMP9TDiwA3GePpDUTdyx4iV3qeOZ7UvPD_CNB9UHf_yN192_rCImhwYNiEdanG_Jsgf0",
           categoryColor: Color(0xFFE2A21E),
        ),
      ],
    );
  }
}

class _CourseCard extends StatelessWidget {
  final Course course;
  const _CourseCard({required this.course});

  @override
  Widget build(BuildContext context) {
    return _DemoCourseCard(
      category: course.level, // Map level to category text if needed
      title: course.title,
      subtitle: course.description,
      progress: 0.1, // Mock progress
      lessons: "1/10 Lessons",
      imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuDSgBnCW0jvJgf-Nxcog8rxc8sqp7x1ZGy__-lXf8pDRRyY0UVvhlRfcNT8uV-8ivezgKEJYagvz-Ppop9aN1Jdg39RGROT6uAemGBPvK17QM11sIOkX5WHAfMVBdIqsgjiga0YegCou6Z5RIHjlikk22nh-w61gcygOhvgiFPyN6drRJcQFbbJVsTgQOZiTQedICW9WrM7efcpxo5trF4QbIWCdjreHdaZ3qDBPvWQzBYCTFB27MjZ9c_SiyNX3GJVACQ3Gb2hEf5i", // Placeholder or from entity
    ); 
  }
}

class _DemoCourseCard extends StatelessWidget {
  final String category;
  final String title;
  final String subtitle;
  final double progress;
  final String lessons;
  final String imageUrl;
  final Color categoryColor;

  const _DemoCourseCard({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.lessons,
    required this.imageUrl,
    this.categoryColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 160,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.toUpperCase(),
                    style: TextStyle(
                        color: categoryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0)),
                const SizedBox(height: 4),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textGrey)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(progress > 0 ? 'Progress' : 'Not Started',
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text('${(progress * 100).toInt()}%',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: progress > 0 ? AppColors.primary : Colors.grey)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[200],
                    color: AppColors.primary,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(lessons,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textGrey, fontWeight: FontWeight.w500)),
                    ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        minimumSize: const Size(100, 40),
                      ),
                      child: Text(progress > 0 ? 'Continue' : 'Start Path',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    )
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
