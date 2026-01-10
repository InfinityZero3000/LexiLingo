import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: GestureDetector(
          onTap: () {}, // Back if needed
          child: const Icon(Icons.arrow_back_ios, color: AppColors.primary, size: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: AppColors.primary),
            onPressed: () async {
               if (authService.isAuthenticated) {
                 await authService.signOut();
               } else {
                 await authService.signIn();
               }
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            // Profile Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                   Stack(
                     children: [
                       Container(
                         width: 128, height: 128,
                         decoration: BoxDecoration(
                           shape: BoxShape.circle,
                           border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 4),
                           image: DecorationImage(
                             image: NetworkImage(user?.photoUrl ?? "https://lh3.googleusercontent.com/aida-public/AB6AXuB8snaMOqgF-A_MIAsFDzdECfymQrWk-qFBIO2qe4HdGlxXevYkJ3nAohlMsHg2lBEZzOpGal3EiYk3Sey9XBjumAonhXCh8PM1vX1x8TMJ0pVqyp4wNanasXtZm46WdsppNU-CLUJJ7-8dL8NaNoQvXibu4sytaLxJww_QwW4DHsxgjtCok6_n6rpCtVv3IZXT2pF5_UL8QnEKkUnrPsFcAZa1m9KaxD4V6ISXvBvpp6h2uZeyFOecdKHVUbPw1ei7ZQQD8QbANtH_"),
                             fit: BoxFit.cover
                           )
                         ),
                       ),
                       Positioned(
                         bottom: 4, right: 4,
                         child: Container(
                           padding: const EdgeInsets.all(4),
                           decoration: BoxDecoration(
                             color: AppColors.primary,
                             shape: BoxShape.circle,
                             border: Border.all(color: Colors.white, width: 2),
                           ),
                           child: const Icon(Icons.verified, color: Colors.white, size: 14),
                         ),
                       )
                     ],
                   ),
                   const SizedBox(height: 16),
                   Text(user?.displayName ?? 'Alex Johnson', 
                     textAlign: TextAlign.center,
                     style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)
                   ),
                   const Text('B2 Upper Intermediate', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 4),
                   const Text('Member since Jan 2023', style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                ],
              ),
            ),

            // Progress Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                       Text('Progress to Level C1', style: TextStyle(fontWeight: FontWeight.w500)),
                       Text('1,250 / 1,500 XP', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 12),
                   ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: 0.75,
                      minHeight: 10,
                      backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[700] : const Color(0xFFDBE0E6),
                      valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                       Text('250 XP to go', style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                       Text('Top 5% this week', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),

            // Learning Stats
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(children: [Text('Learning Stats', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))]),
            ),
            
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                 _buildStatCard(context, Icons.local_fire_department, Colors.orange, "Streak", "15 Days", "+2 today"),
                 _buildStatCard(context, Icons.menu_book, Colors.blue, "Words", "840", "+45 new"),
                 _buildStatCard(context, Icons.smart_toy, Colors.purple, "AI Talk", "120 min", "+10 min"),
                 _buildStatCard(context, Icons.stars, Colors.amber, "Badges", "12", "View all", isAction: true),
              ],
            ),

            // Weekly Activity
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Weekly Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Activity Map', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
               decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                 boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildChartBar(context, "M", 0.4),
                  _buildChartBar(context, "T", 0.6),
                  _buildChartBar(context, "W", 0.9),
                  _buildChartBar(context, "T", 0.5),
                  _buildChartBar(context, "F", 0.3),
                  _buildChartBar(context, "S", 0.2),
                  _buildChartBar(context, "S", 0.25),
                ],
              ),
            ),

            // Recent Badges
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(children: [Text('Recent Badges', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))]),
            ),
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                   _buildBadgeItem(Icons.workspace_premium, Colors.orange, "Early Bird"),
                   const SizedBox(width: 16),
                   _buildBadgeItem(Icons.forum, AppColors.primary, "Chatterbox"),
                   const SizedBox(width: 16),
                   _buildBadgeItem(Icons.school, Colors.green, "100 Words"),
                   const SizedBox(width: 16),
                   _buildBadgeItem(Icons.lock, Colors.grey, "Locked", isLocked: true),
                ],
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, IconData icon, Color color, String title, String value, String subLabel, {bool isAction = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
               Icon(icon, color: color, size: 20),
               const SizedBox(width: 8),
               Text(title, style: const TextStyle(color: AppColors.textGrey, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isAction ? AppColors.primary.withOpacity(0.1) : const Color(0xFF078838).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4)
            ),
            child: Text(subLabel, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold,
              color: isAction ? AppColors.primary : const Color(0xFF078838)
            )),
          )
        ],
      ),
    );
  }

  Widget _buildChartBar(BuildContext context, String day, double pct) {
    return Column(
      children: [
         Container(
           width: 32,
           height: 80 * pct,
           decoration: BoxDecoration(
             color: AppColors.primary.withOpacity(0.3 + (pct * 0.7)),
             borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
           ),
         ),
         const SizedBox(height: 8),
         Text(day, style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
      ],
    );
  }

  Widget _buildBadgeItem(IconData icon, Color color, String label, {bool isLocked = false}) {
     return Column(
       children: [
         Container(
           width: 64, height: 64,
           decoration: BoxDecoration(
             shape: BoxShape.circle,
             gradient: isLocked ? null : LinearGradient(colors: [color.withOpacity(0.6), color], begin: Alignment.bottomLeft, end: Alignment.topRight),
             color: isLocked ? Colors.grey[200] : null,
             border: isLocked ? Border.all(color: Colors.grey, width: 2, style: BorderStyle.solid) : null, // Dashed unsupported simply
             boxShadow: isLocked ? null : [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))]
           ),
           child: Icon(icon, color: isLocked ? Colors.grey : Colors.white, size: 30),
         ),
         const SizedBox(height: 8),
         Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
       ],
     );
  }
}

