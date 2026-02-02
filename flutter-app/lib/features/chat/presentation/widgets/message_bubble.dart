import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/chat/domain/entities/chat_message.dart';
import 'package:lexilingo_app/features/chat/presentation/widgets/markdown_message_content.dart';
import 'package:intl/intl.dart';

/// Message Reaction data
class MessageReaction {
  final String emoji;
  final String label;
  
  const MessageReaction({required this.emoji, required this.label});
}

/// A reusable message bubble widget for chat interface
/// Supports both user and AI messages with different styling
class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool showAvatar;
  final bool showTimestamp;
  final VoidCallback? onRetry;
  final Function(String reaction)? onReaction;

  const MessageBubble({
    super.key,
    required this.message,
    this.showAvatar = true,
    this.showTimestamp = true,
    this.onRetry,
    this.onReaction,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> with SingleTickerProviderStateMixin {
  bool _showActions = false;
  bool _showReactions = false;
  String? _selectedReaction;
  late AnimationController _reactionController;
  late Animation<double> _reactionScaleAnimation;

  static const List<MessageReaction> _reactions = [
    MessageReaction(emoji: 'thumb_up', label: 'Helpful'),
    MessageReaction(emoji: 'favorite', label: 'Love'),
    MessageReaction(emoji: 'lightbulb', label: 'Insightful'),
    MessageReaction(emoji: 'target', label: 'Perfect'),
    MessageReaction(emoji: 'help', label: 'Need more'),
  ];

  @override
  void initState() {
    super.initState();
    _reactionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _reactionScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _reactionController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _reactionController.dispose();
    super.dispose();
  }

  void _toggleReactions() {
    setState(() {
      _showReactions = !_showReactions;
      if (_showReactions) {
        _reactionController.forward(from: 0);
      }
    });
  }

  void _selectReaction(String emoji) {
    setState(() {
      _selectedReaction = emoji;
      _showReactions = false;
    });
    widget.onReaction?.call(emoji);
    HapticFeedback.lightImpact();
  }

  IconData _getReactionIcon(String iconName) {
    switch (iconName) {
      case 'thumb_up':
        return Icons.thumb_up;
      case 'favorite':
        return Icons.favorite;
      case 'lightbulb':
        return Icons.lightbulb;
      case 'target':
        return Icons.gps_fixed;
      case 'help':
        return Icons.help_outline;
      default:
        return Icons.star;
    }
  }

  Color _getReactionColor(String iconName) {
    switch (iconName) {
      case 'thumb_up':
        return Colors.blue;
      case 'favorite':
        return Colors.red;
      case 'lightbulb':
        return Colors.amber;
      case 'target':
        return Colors.green;
      case 'help':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.isUserMessage;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser && widget.showAvatar) _buildAvatar(isAI: true),
          if (!isUser && widget.showAvatar) const SizedBox(width: 12),
          
          Flexible(
            child: GestureDetector(
              onLongPress: () {
                setState(() {
                  _showActions = !_showActions;
                });
              },
              onDoubleTap: !widget.message.isUserMessage ? () {
                _toggleReactions();
                HapticFeedback.mediumImpact();
              } : null,
              child: Column(
                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // Sender label
                  Padding(
                    padding: EdgeInsets.only(
                      left: isUser ? 0 : 4,
                      right: isUser ? 4 : 0,
                      bottom: 4,
                    ),
                    child: Text(
                      isUser ? 'You' : 'AI Tutor',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  
                  // Message bubble
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _getBubbleColor(isUser, isDark),
                      borderRadius: _getBorderRadius(isUser),
                      boxShadow: isUser
                          ? [
                              const BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Content with markdown support for AI messages
                        if (isUser)
                          Text(
                            widget.message.content,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.white,
                                ),
                          )
                        else
                          MarkdownMessageContent(
                            content: widget.message.content,
                            isDark: isDark,
                          ),
                        
                        // Status indicator & timestamp
                        if (widget.showTimestamp || widget.message.isSending || widget.message.hasError)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.showTimestamp) ...[
                                  Text(
                                    _formatTimestamp(widget.message.timestamp),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isUser 
                                          ? Colors.white.withValues(alpha: 0.7)
                                          : AppColors.textGrey,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                
                                // Status icon
                                if (widget.message.isSending)
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: isUser ? Colors.white : AppColors.primary,
                                    ),
                                  )
                                else if (widget.message.hasError)
                                  Icon(
                                    Icons.error_outline,
                                    size: 14,
                                    color: isUser ? Colors.red[200] : Colors.red,
                                  )
                                else if (isUser)
                                  Icon(
                                    Icons.check,
                                    size: 14,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Error message
                  if (widget.message.hasError && widget.message.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.message.error!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red[700],
                            ),
                            softWrap: true,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                          if (widget.onRetry != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: GestureDetector(
                                onTap: widget.onRetry,
                                child: Text(
                                  'Retry',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  
                  // Selected Reaction Display
                  if (_selectedReaction != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getReactionColor(_selectedReaction!).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _getReactionColor(_selectedReaction!).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(
                          _getReactionIcon(_selectedReaction!),
                          size: 18,
                          color: _getReactionColor(_selectedReaction!),
                        ),
                      ),
                    ),

                  // Reaction Picker (for AI messages only)
                  if (_showReactions && !widget.message.isUserMessage)
                    ScaleTransition(
                      scale: _reactionScaleAnimation,
                      child: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: _reactions.map((reaction) {
                            return GestureDetector(
                              onTap: () => _selectReaction(reaction.emoji),
                              child: Tooltip(
                                message: reaction.label,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: Icon(
                                    _getReactionIcon(reaction.emoji),
                                    size: 24,
                                    color: _getReactionColor(reaction.emoji),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  
                  // Action buttons (copy, react)
                  if (_showActions)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildActionButton(
                            icon: Icons.copy,
                            label: 'Copy',
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: widget.message.content),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Message copied to clipboard'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                              setState(() {
                                _showActions = false;
                              });
                            },
                          ),
                          // Reaction button for AI messages
                          if (!widget.message.isUserMessage) ...[
                            const SizedBox(width: 8),
                            _buildActionButton(
                              icon: _selectedReaction != null 
                                  ? Icons.emoji_emotions 
                                  : Icons.emoji_emotions_outlined,
                              label: 'React',
                              onTap: _toggleReactions,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          if (isUser && widget.showAvatar) const SizedBox(width: 12),
          if (isUser && widget.showAvatar) _buildAvatar(isAI: false),
        ],
      ),
    );
  }

  Widget _buildAvatar({required bool isAI}) {
    if (isAI) {
      // AI Avatar with network image
      return Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accentYellow,
          image: const DecorationImage(
            image: NetworkImage(
              "https://lh3.googleusercontent.com/aida-public/AB6AXuATpszxo8IDSZGFMcAe7wu3OsLcfmZ-s1g8zqZEZrd1NWWKigT9eaRCBLHYPYrzm_QHWJnz7gDyqvGT8FPffL3SHy4BPngd150uW71CjgCXpokjLtm7-JOo639zGjehA2gx3x0GrWgVn3fQhVJQnFfn53UEibhEVOb1k3gycZzHNg6fSz23m5uyeyR0n2gaM8_-RSKtJ5LPpf8z6c_nvkCPbAeOU-UKQ5RtZOh_4iBwspBMQqLZY3yHpWZ5hYD5Vj3tWnYFB68cxn1E",
            ),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      // User Avatar - default icon like profile page
      return Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withValues(alpha: 0.15),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: const Icon(
          Icons.person,
          size: 18,
          color: AppColors.primary,
        ),
      );
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBubbleColor(bool isUser, bool isDark) {
    if (isUser) return AppColors.primary;
    return isDark ? Colors.grey[800]! : const Color(0xFFF0F2F4);
  }

  BorderRadius _getBorderRadius(bool isUser) {
    return BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomRight: Radius.circular(isUser ? 0 : 16),
      bottomLeft: Radius.circular(isUser ? 16 : 0),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      return DateFormat.Hm().format(timestamp); // HH:mm
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday ${DateFormat.Hm().format(timestamp)}';
    } else {
      return DateFormat('MMM d, HH:mm').format(timestamp);
    }
  }
}
