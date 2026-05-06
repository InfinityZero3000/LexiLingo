import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/quick_save_selection_area.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/story_model.dart';
import '../../data/models/topic_session_model.dart';
import '../providers/story_provider.dart';
import '../widgets/educational_hints_widgets.dart';

/// Topic-Based Chat Page - Enhanced Version (Phase 3)
class TopicChatPage extends StatefulWidget {
  final StoryListItem story;

  const TopicChatPage({super.key, required this.story});

  @override
  State<TopicChatPage> createState() => _TopicChatPageState();
}

class _TopicChatPageState extends State<TopicChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _taskBannerVisible = false;
  bool _taskBannerDismissedByUser = false;
  _TaskBannerType _taskBannerType = _TaskBannerType.loading;
  String _taskBannerTitle = 'Preparing chat...';
  String _taskBannerDetail = '';
  double? _taskBannerProgress;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleTopReached);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openTopicAndWarmContext();
    });
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _scrollController.removeListener(_handleTopReached);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    // Capture provider before microtask to avoid using context after dispose
    final provider = context.read<StoryProvider>();
    Future.microtask(() {
      provider.clearActiveSession();
    });
    super.dispose();
  }

  void _handleTopReached() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels > 40) return;

    final provider = context.read<StoryProvider>();
    if (!provider.hasMoreMessages || provider.isLoadingMoreMessages) return;

    unawaited(provider.loadOlderMessages());
  }

  Future<void> _openTopicAndWarmContext() async {
    if (!mounted) return;
    final provider = context.read<StoryProvider>();
    final userId = _currentUserId(context);

    _showTaskBanner(
      type: _TaskBannerType.loading,
      title: 'topicChat.openingTaskTitle'.tr(),
      detail: 'topicChat.creatingSessionDetail'.tr(),
      progress: 0.25,
    );

    final success = await provider.restoreOrStartTopicSession(
      userId: userId,
      storyId: widget.story.storyId,
    );

    if (!mounted) return;
    if (!success) {
      _showTaskBanner(
        type: _TaskBannerType.error,
        title: 'topicChat.failedOpenTitle'.tr(),
        detail: provider.sessionError ?? 'topicChat.tryAgainDefault'.tr(),
        progress: null,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.sessionError ?? 'topicChat.failedStartSession'.tr()),
          backgroundColor: AppColors.errorBright,
        ),
      );
      return;
    }

    _showTaskBanner(
      type: _TaskBannerType.loading,
      title: 'topicChat.loadingKgTitle'.tr(),
      detail: 'topicChat.loadingKgDetail'.tr(),
      progress: 0.7,
    );

    final warmed = await provider.warmTopicCache(
      storyId: widget.story.storyId,
      userId: userId,
    );

    if (!mounted) return;
    if (warmed) {
      _showTaskBanner(
        type: _TaskBannerType.complete,
        title: 'topicChat.contextReadyTitle'.tr(),
        detail: 'topicChat.contextReadyDetail'.tr(),
        progress: 1.0,
      );
      _scheduleAutoHide();
    } else {
      _showTaskBanner(
        type: _TaskBannerType.error,
        title: 'topicChat.contextFailedTitle'.tr(),
        detail: provider.error ?? 'topicChat.contextFailedDetail'.tr(),
        progress: null,
      );
    }
  }

  void _showTaskBanner({
    required _TaskBannerType type,
    required String title,
    required String detail,
    double? progress,
  }) {
    _autoHideTimer?.cancel();
    if (_taskBannerDismissedByUser) return;

    setState(() {
      _taskBannerType = type;
      _taskBannerTitle = title;
      _taskBannerDetail = detail;
      _taskBannerProgress = progress;
      _taskBannerVisible = true;
    });
  }

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _taskBannerVisible = false;
      });
    });
  }

  void _dismissTaskBannerByUser() {
    _autoHideTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _taskBannerDismissedByUser = true;
      _taskBannerVisible = false;
    });
  }

  String _currentUserId(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return auth.user?.id ?? 'demo_user_001';
  }

  Future<void> _sendMessage([String? text]) async {
    if (!mounted) return;
    final message = text ?? _controller.text.trim();
    if (message.isEmpty) return;

    if (text == null) _controller.clear();
    _focusNode.requestFocus();

    final provider = context.read<StoryProvider>();
    final userId = _currentUserId(context);

    final success = await provider.sendMessage(
      userId: userId,
      message: message,
    );

    if (!mounted) return;
    if (success) {
      _scrollToBottom();
    } else if (provider.sessionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.sessionError!),
          backgroundColor: AppColors.errorBright,
        ),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: _buildAppBar(isDark),
      body: Consumer<StoryProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              // 1. Story context header
              if (provider.currentSession != null)
                _StoryContextHeader(session: provider.currentSession!),

              // 2. Messages list
              Expanded(
                child: provider.messages.isEmpty
                    ? Center(
                        child: Text(
                          provider.isLoading
                              ? 'topicChat.preparingTopicMessage'.tr()
                              : 'topicChat.emptyStateMessage'.tr(),
                          style: TextStyle(
                            color: AppColorRoles.textMuted(isDark),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: provider.messages.length,
                        itemBuilder: (context, index) {
                          final message = provider.messages[index];
                          return _TopicMessageBubble(message: message);
                        },
                      ),
              ),

              // 3. Suggested Prompts (if any)
              if (widget.story.suggestedPrompts.isNotEmpty &&
                  !provider.isSendingMessage)
                _buildSuggestedPrompts(isDark),

              // 4. Typing indicator
              if (provider.isSendingMessage) _buildTypingIndicator(isDark),

              // 5. Input field
              if (!_taskBannerDismissedByUser) _buildTaskBanner(isDark),
              _buildInputField(
                isEnabled: provider.hasActiveSession,
                isDark: isDark,
              ),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      toolbarHeight: 86,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      foregroundColor: AppColorRoles.textPrimary(isDark),
      elevation: 0,
      leading: BackButton(
        onPressed: () {
          context.read<StoryProvider>().clearActiveSession();
          Navigator.pop(context);
        },
      ),
      titleSpacing: 8,
      title: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColorRoles.primary(isDark),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getCategoryIconData(widget.story.category),
              color: Theme.of(context).colorScheme.surface,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.story.title.en,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColorRoles.textPrimary(isDark),
                  ),
                ),
                Text(
                  '${widget.story.difficultyLevel.shortName} • ${widget.story.estimatedMinutes}m left',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColorRoles.textSecondary(isDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.menu_book_outlined),
          onPressed: _showVocabularyPreview,
          tooltip: 'topicChat.vocabularyTooltip'.tr(),
        ),
        IconButton(
          icon: const Icon(Icons.exit_to_app_outlined),
          onPressed: _confirmEndSession,
          tooltip: 'topicChat.endSessionTooltip'.tr(),
        ),
      ],
    );
  }

  IconData _getCategoryIconData(String category) {
    switch (category.toLowerCase()) {
      case 'travel':
        return Icons.flight_takeoff;
      case 'business':
      case 'work':
        return Icons.work;
      case 'daily_life':
      case 'daily life':
        return Icons.home;
      case 'food':
      case 'cafe':
        return Icons.coffee;
      case 'shopping':
        return Icons.shopping_cart;
      case 'health':
        return Icons.local_hospital;
      default:
        return Icons.chat_bubble;
    }
  }

  Widget _buildSuggestedPrompts(bool isDark) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: widget.story.suggestedPrompts.length,
        itemBuilder: (context, index) {
          final prompt = widget.story.suggestedPrompts[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              label: Text(prompt, style: TextStyle(fontSize: 12)),
              onPressed: () => _sendMessage(prompt),
              backgroundColor: isDark
                  ? AppColors.surfaceDarkInk
                  : AppColors.surfaceLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: AppColorRoles.primary(isDark).withValues(alpha: 0.3),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: LottieLoadingWidget.tiny(),
          ),
          const SizedBox(width: 12),
          Text(
            '${widget.story.title.en.split(' ').first} is typing...',
            style: TextStyle(
              fontSize: 12,
              color: AppColorRoles.textMuted(isDark),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskBanner(bool isDark) {
    final Color accent = switch (_taskBannerType) {
      _TaskBannerType.loading => AppColorRoles.primary(isDark),
      _TaskBannerType.complete => AppColors.greenSuccessBright,
      _TaskBannerType.error => AppColors.orange,
    };

    final IconData icon = switch (_taskBannerType) {
      _TaskBannerType.loading => Icons.sync,
      _TaskBannerType.complete => Icons.check_circle_outline,
      _TaskBannerType.error => Icons.info_outline,
    };

    return AnimatedSlide(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      offset: _taskBannerVisible ? Offset.zero : const Offset(0, 1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _taskBannerVisible ? 1 : 0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Dismissible(
            key: ValueKey('task-banner-$_taskBannerTitle-$_taskBannerType'),
            direction: DismissDirection.horizontal,
            onDismissed: (_) => _dismissTaskBannerByUser(),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceDarkCard
                    : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _taskBannerTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColorRoles.textPrimary(isDark),
                          ),
                        ),
                      ),
                      Text(
                        'topicChat.swipeToCloseHint'.tr(),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColorRoles.textMuted(isDark),
                        ),
                      ),
                    ],
                  ),
                  if (_taskBannerDetail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _taskBannerDetail,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColorRoles.textSecondary(isDark),
                      ),
                    ),
                  ],
                  if (_taskBannerProgress != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: _taskBannerProgress,
                        backgroundColor: accent.withValues(alpha: 0.16),
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({required bool isEnabled, required bool isDark}) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMuted : AppColors.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDarkInk : AppColors.grey100,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? AppColors.borderDarkSoft : AppColors.grey200,
                ),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: isEnabled,
                style: TextStyle(color: AppColorRoles.textPrimary(isDark)),
                decoration: InputDecoration(
                  hintText: 'topicChat.inputHint'.tr(),
                  hintStyle: TextStyle(color: AppColorRoles.textMuted(isDark)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: isEnabled ? _sendMessage : null,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isEnabled
                    ? AppColorRoles.primary(isDark)
                    : AppColors.grey500,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.send,
                color: isDark ? AppColors.slate900 : AppColors.surfaceLight,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _getCategoryIcon(String category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    IconData icon;
    Color color;
    switch (category.toLowerCase()) {
      case 'travel':
        icon = Icons.flight_takeoff;
        color = AppColorRoles.primary(isDark);
        break;
      case 'business':
      case 'work':
        icon = Icons.work;
        color = Colors.indigo;
        break;
      case 'daily_life':
      case 'daily life':
        icon = Icons.home;
        color = AppColors.teal;
        break;
      case 'food':
      case 'cafe':
        icon = Icons.coffee;
        color = AppColors.orange;
        break;
      case 'shopping':
        icon = Icons.shopping_cart;
        color = Colors.pinkAccent;
        break;
      case 'health':
        icon = Icons.local_hospital;
        color = Colors.redAccent;
        break;
      default:
        icon = Icons.chat_bubble;
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  void _showVocabularyPreview() {
    final session = context.read<StoryProvider>().currentSession;
    if (session == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => VocabularyPreviewSheet(
          vocabulary: session.vocabularyPreview,
          scrollController: scrollController,
        ),
      ),
    );
  }

  void _confirmEndSession() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('topicChat.endSessionTitle'.tr()),
        content: Text(
          'topicChat.endSessionConfirmation'.tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('topicChat.cancelButton'.tr()),
          ),
          ElevatedButton(
            onPressed: () {
              final provider = context.read<StoryProvider>();
              provider.endSession();
              provider.clearActiveSession();
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to story selection
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorBright,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('topicChat.endSessionButton'.tr()),
          ),
        ],
      ),
    );
  }
}

enum _TaskBannerType { loading, complete, error }

/// Story context header widget
class _StoryContextHeader extends StatelessWidget {
  final TopicSession session;

  const _StoryContextHeader({required this.session});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDarkCard
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColorRoles.primary(
              isDark,
            ).withValues(alpha: 0.16),
            child: Text(
              session.rolePersona.name.isNotEmpty
                  ? session.rolePersona.name[0]
                  : '?',
              style: TextStyle(
                color: AppColorRoles.primary(isDark),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.rolePersona.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColorRoles.textPrimary(isDark),
                  ),
                ),
                Text(
                  session.rolePersona.role,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColorRoles.textSecondary(isDark),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt, size: 12, color: AppColors.greenSuccessBright),
                const SizedBox(width: 4),
                Text(
                  'topicChat.contextReadyBadgeLabel'.tr(),
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.greenSuccessBright,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Topic message bubble widget
class _TopicMessageBubble extends StatelessWidget {
  final TopicChatMessage message;

  const _TopicMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.isUser;
    final bubbleTextStyle = TextStyle(
      color: isUser
          ? (isDark ? AppColors.slate900 : AppColors.surfaceLight)
          : AppColorRoles.textPrimary(isDark),
      fontSize: 15,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColorRoles.primary(
                    isDark,
                  ).withValues(alpha: 0.16),
                  child: Icon(
                    Icons.smart_toy,
                    size: 16,
                    color: AppColorRoles.primary(isDark),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? AppColorRoles.primary(isDark)
                        : (isDark
                              ? AppColors.surfaceDarkCard
                              : AppColors.surfaceLight),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 20),
                    ),
                    border: Border.all(
                      color: isUser
                          ? AppColorRoles.primary(isDark).withValues(alpha: 0.3)
                          : (isDark
                                ? AppColors.borderDarkSoft
                                : AppColors.grey200),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.14 : 0.05,
                        ),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isUser
                      ? Text(message.displayContent, style: bubbleTextStyle)
                      : QuickSaveSelectionArea(
                          sourceType: 'topic_chat',
                          sourceReference: message.id,
                          contextSentence: message.displayContent,
                          child: Text(
                            message.displayContent,
                            style: bubbleTextStyle,
                          ),
                        ),
                ),
              ),
            ],
          ),
          if (!isUser && message.hints != null && message.hints!.hasAnyHints)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 36),
              child: EducationalHintsCard(hints: message.hints!),
            ),

        ],
      ),
    );
  }
}

/// Vocabulary preview sheet widget
class VocabularyPreviewSheet extends StatelessWidget {
  final List<VocabularyItem> vocabulary;
  final ScrollController scrollController;

  const VocabularyPreviewSheet({
    super.key,
    required this.vocabulary,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppColors.textOnDarkMuted : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.menu_book, color: AppColorRoles.primary(isDark)),
                const SizedBox(width: 12),
                Text(
                  'topicChat.keyVocabularyTitle'.tr(),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: vocabulary.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final item = vocabulary[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Text(
                        item.term,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (item.partOfSpeech.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.partOfSpeech,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        item.definition,
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (item.exampleInStory.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '"${item.exampleInStory}"',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
