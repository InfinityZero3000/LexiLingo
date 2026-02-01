import 'package:flutter/material.dart';
import 'custom_animations.dart';

/// Animation Showcase Page
/// Demonstrates all available custom animations in the app
class AnimationShowcasePage extends StatelessWidget {
  const AnimationShowcasePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Animations'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('1. Pulse Animation'),
            _buildDescription('Perfect for notification badges, buttons'),
            Center(
              child: PulseAnimation(
                color: Colors.blue,
                maxRadius: 30,
                child: Icon(Icons.notifications, color: Colors.blue, size: 30),
              ),
            ),
            const SizedBox(height: 32),

            _buildSectionTitle('2. Shimmer Effect'),
            _buildDescription('Loading placeholder for content'),
            ShimmerEffect(
              child: Container(
                width: double.infinity,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 32),

            _buildSectionTitle('3. Wave Animation'),
            _buildDescription('Beautiful wave background'),
            Container(
              height: 120,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
              ),
              child: WaveAnimation(
                color: Colors.blue.withValues(alpha: 0.3),
                height: 40,
              ),
            ),
            const SizedBox(height: 32),

            _buildSectionTitle('4. Floating Particles'),
            _buildDescription('Decorative floating particles background'),
            Container(
              height: 150,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.grey[900],
              ),
              child: FloatingParticles(
                particleCount: 20,
                color: Colors.white.withValues(alpha: 0.6),
                maxSize: 4,
              ),
            ),
            const SizedBox(height: 32),

            _buildSectionTitle('5. Animated Progress Ring'),
            _buildDescription('Circular progress with animation'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                AnimatedProgressRing(
                  progress: 0.3,
                  size: 80,
                  strokeWidth: 8,
                  backgroundColor: Colors.grey[300]!,
                  progressColor: Colors.red,
                  child: Text('30%', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                AnimatedProgressRing(
                  progress: 0.65,
                  size: 80,
                  strokeWidth: 8,
                  backgroundColor: Colors.grey[300]!,
                  progressColor: Colors.orange,
                  child: Text('65%', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                AnimatedProgressRing(
                  progress: 1.0,
                  size: 80,
                  strokeWidth: 8,
                  backgroundColor: Colors.grey[300]!,
                  progressColor: Colors.green,
                  child: Icon(Icons.check, color: Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 32),

            _buildSectionTitle('6. Ripple Effect'),
            _buildDescription('Touch feedback animation'),
            Center(
              child: RippleEffect(
                rippleColor: Colors.purple,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('Tap me'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            _buildSectionTitle('7. Breathing Glow'),
            _buildDescription('Highlight important elements'),
            Center(
              child: BreathingGlow(
                glowColor: Colors.amber,
                maxBlur: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Premium Feature',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            _buildSectionTitle('8. Typing Indicator'),
            _buildDescription('Chat typing animation'),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const TypingIndicator(
                  color: Colors.grey,
                  dotSize: 10,
                ),
              ),
            ),
            const SizedBox(height: 32),

            _buildSectionTitle('9. Animated Gradient Border'),
            _buildDescription('Eye-catching card borders'),
            AnimatedGradientBorder(
              borderWidth: 3,
              borderRadius: 16,
              colors: [Colors.blue, Colors.purple, Colors.pink, Colors.orange],
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.star, color: Colors.amber, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      'Featured Content',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'This card has an animated gradient border',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            _buildSectionTitle('10. Animated Checkmark'),
            _buildDescription('Success/completion feedback'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                AnimatedCheckmark(
                  color: Colors.green,
                  size: 60,
                ),
                AnimatedCheckmark(
                  color: Colors.blue,
                  size: 60,
                ),
                AnimatedCheckmark(
                  color: Colors.purple,
                  size: 60,
                ),
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDescription(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 14,
        ),
      ),
    );
  }
}
