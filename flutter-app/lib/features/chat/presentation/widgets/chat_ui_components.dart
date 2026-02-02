import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Glassmorphic Chat Input Widget
/// Modern chat input with glass effect and smooth animations
class GlassmorphicChatInput extends StatefulWidget {
  final TextEditingController controller;
  final bool isEnabled;
  final String hintText;
  final VoidCallback? onSend;
  final VoidCallback? onVoiceStart;
  final VoidCallback? onVoiceEnd;
  final VoidCallback? onAttachment;
  final bool isRecording;
  final bool showVoiceButton;
  final bool showAttachmentButton;

  const GlassmorphicChatInput({
    super.key,
    required this.controller,
    this.isEnabled = true,
    this.hintText = 'Type your message...',
    this.onSend,
    this.onVoiceStart,
    this.onVoiceEnd,
    this.onAttachment,
    this.isRecording = false,
    this.showVoiceButton = true,
    this.showAttachmentButton = false,
  });

  @override
  State<GlassmorphicChatInput> createState() => _GlassmorphicChatInputState();
}

class _GlassmorphicChatInputState extends State<GlassmorphicChatInput>
    with SingleTickerProviderStateMixin {
  late AnimationController _focusController;
  late Animation<double> _focusAnimation;
  bool _isFocused = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _focusController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _focusAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _focusController, curve: Curves.easeOut),
    );
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _onFocusChanged(bool focused) {
    setState(() => _isFocused = focused);
    if (focused) {
      _focusController.forward();
    } else {
      _focusController.reverse();
    }
  }

  @override
  void dispose() {
    _focusController.dispose();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _focusAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.08 + _focusAnimation.value * 0.04),
                      Colors.white.withValues(alpha: 0.04 + _focusAnimation.value * 0.02),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.7 + _focusAnimation.value * 0.2),
                      Colors.white.withValues(alpha: 0.5 + _focusAnimation.value * 0.2),
                    ],
            ),
            border: Border.all(
              color: _isFocused
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : (isDark 
                      ? Colors.white.withValues(alpha: 0.1) 
                      : Colors.grey.withValues(alpha: 0.2)),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _isFocused
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    // Attachment button (optional)
                    if (widget.showAttachmentButton)
                      IconButton(
                        onPressed: widget.onAttachment,
                        icon: Icon(
                          Icons.add_circle_outline,
                          color: isDark ? Colors.white60 : AppColors.textGrey,
                        ),
                      ),
                    
                    // Text input
                    Expanded(
                      child: Focus(
                        onFocusChange: _onFocusChanged,
                        child: TextField(
                          controller: widget.controller,
                          enabled: widget.isEnabled,
                          maxLines: 4,
                          minLines: 1,
                          style: TextStyle(
                            fontSize: 15,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                          decoration: InputDecoration(
                            hintText: widget.hintText,
                            hintStyle: TextStyle(
                              color: isDark 
                                  ? Colors.white38 
                                  : AppColors.textGrey.withValues(alpha: 0.7),
                              fontSize: 15,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => widget.onSend?.call(),
                        ),
                      ),
                    ),
                    
                    // Voice button (optional)
                    if (widget.showVoiceButton && !_hasText)
                      GestureDetector(
                        onLongPressStart: (_) => widget.onVoiceStart?.call(),
                        onLongPressEnd: (_) => widget.onVoiceEnd?.call(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: widget.isRecording
                                ? Colors.red.withValues(alpha: 0.2)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.isRecording ? Icons.mic : Icons.mic_none,
                            color: widget.isRecording
                                ? Colors.red
                                : (isDark ? Colors.white60 : AppColors.textGrey),
                          ),
                        ),
                      ),
                    
                    // Send button
                    AnimatedOpacity(
                      opacity: _hasText ? 1.0 : 0.5,
                      duration: const Duration(milliseconds: 150),
                      child: AnimatedScale(
                        scale: _hasText ? 1.0 : 0.9,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.primary,
                                AppColors.primary.withValues(alpha: 0.8),
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: _hasText
                                ? [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(alpha: 0.4),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _hasText ? widget.onSend : null,
                              borderRadius: BorderRadius.circular(20),
                              child: const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// AI Tutor Mood Indicator Widget
/// Shows the current mood/status of the AI tutor
class AITutorMoodIndicator extends StatefulWidget {
  final AIMood mood;
  final bool isOnline;
  final String? currentTopic;
  final VoidCallback? onTap;

  const AITutorMoodIndicator({
    super.key,
    this.mood = AIMood.neutral,
    this.isOnline = true,
    this.currentTopic,
    this.onTap,
  });

  @override
  State<AITutorMoodIndicator> createState() => _AITutorMoodIndicatorState();
}

class _AITutorMoodIndicatorState extends State<AITutorMoodIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isOnline) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(AITutorMoodIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline != oldWidget.isOnline) {
      if (widget.isOnline) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _moodColor {
    switch (widget.mood) {
      case AIMood.happy:
        return Colors.green;
      case AIMood.thinking:
        return Colors.orange;
      case AIMood.excited:
        return Colors.pink;
      case AIMood.helpful:
        return Colors.blue;
      case AIMood.neutral:
        return Colors.green;
    }
  }

  String get _moodText {
    switch (widget.mood) {
      case AIMood.happy:
        return 'Happy to help!';
      case AIMood.thinking:
        return 'Thinking...';
      case AIMood.excited:
        return 'Great progress!';
      case AIMood.helpful:
        return 'Learning Guide';
      case AIMood.neutral:
        return 'Ready to chat';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'AI Tutor',
            style: TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status dot with pulse animation
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: widget.isOnline ? _pulseAnimation.value : 1.0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: widget.isOnline ? _moodColor : Colors.grey,
                        shape: BoxShape.circle,
                        boxShadow: widget.isOnline
                            ? [
                                BoxShadow(
                                  color: _moodColor.withValues(alpha: 0.5),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
              // Status text
              Text(
                widget.isOnline ? _moodText : 'Offline',
                style: TextStyle(
                  color: AppColors.textDark.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
              if (widget.currentTopic != null) ...[
                Text(
                  ' | ',
                  style: TextStyle(
                    color: AppColors.textDark.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
                Text(
                  widget.currentTopic!,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// AI Mood enum
enum AIMood {
  neutral,
  happy,
  thinking,
  excited,
  helpful,
}

/// Topic Chip for conversation starters
class TopicChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  final bool isSelected;

  const TopicChip({
    super.key,
    required this.label,
    required this.icon,
    this.color,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [chipColor, chipColor.withValues(alpha: 0.8)],
                  )
                : null,
            color: isSelected
                ? null
                : (isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : chipColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : chipColor),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : chipColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Topic chips row for conversation starters
class TopicChipsRow extends StatelessWidget {
  final List<TopicData> topics;
  final String? selectedTopic;
  final Function(String)? onTopicSelected;

  const TopicChipsRow({
    super.key,
    required this.topics,
    this.selectedTopic,
    this.onTopicSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: topics.map((topic) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TopicChip(
              label: topic.label,
              icon: topic.icon,
              color: topic.color,
              isSelected: selectedTopic == topic.label,
              onTap: () => onTopicSelected?.call(topic.label),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Topic data model
class TopicData {
  final String label;
  final IconData icon;
  final Color? color;

  const TopicData({
    required this.label,
    required this.icon,
    this.color,
  });
}

/// Default conversation topics
const List<TopicData> defaultTopics = [
  TopicData(label: 'Daily Life', icon: Icons.wb_sunny, color: Colors.orange),
  TopicData(label: 'Travel', icon: Icons.flight, color: Colors.blue),
  TopicData(label: 'Food', icon: Icons.restaurant, color: Colors.red),
  TopicData(label: 'Work', icon: Icons.work, color: Colors.purple),
  TopicData(label: 'Hobbies', icon: Icons.palette, color: Colors.green),
];
