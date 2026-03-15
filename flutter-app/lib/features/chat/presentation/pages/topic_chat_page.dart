import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSession();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    // Use clearActiveSession via a microtask to avoid notifying during dispose
    Future.microtask(() {
      if (context.mounted) {
        context.read<StoryProvider>().clearActiveSession();
      }
    });
    super.dispose();
  }

  Future<void> _startSession() async {
    final provider = context.read<StoryProvider>();
    final userId = _currentUserId(context);

    final success = await provider.startTopicSession(
      userId: userId,
      storyId: widget.story.storyId,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.sessionError ?? 'Failed to start session'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _currentUserId(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return auth.user?.id ?? 'demo_user_001';
  }

  Future<void> _sendMessage([String? text]) async {
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

    if (success) {
      _scrollToBottom();
    } else if (mounted && provider.sessionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.sessionError!),
          backgroundColor: Colors.red,
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
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: Consumer<StoryProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && !provider.hasActiveSession) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              // 1. Story context header
              if (provider.currentSession != null)
                _StoryContextHeader(session: provider.currentSession!),

              // 2. Messages list
              Expanded(
                child: ListView.builder(
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
                _buildSuggestedPrompts(),

              // 4. Typing indicator
              if (provider.isSendingMessage) _buildTypingIndicator(),

              // 5. Input field
              _buildInputField(),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      leading: BackButton(
        onPressed: () {
          context.read<StoryProvider>().clearActiveSession();
          Navigator.pop(context);
        },
      ),
      title: Row(
        children: [
          _getCategoryIcon(widget.story.category),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.story.title.en,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${widget.story.difficultyLevel.shortName} • ${widget.story.estimatedMinutes}m left',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
          tooltip: 'Vocabulary',
        ),
        IconButton(
          icon: const Icon(Icons.exit_to_app_outlined),
          onPressed: _confirmEndSession,
          tooltip: 'End Session',
        ),
      ],
    );
  }

  Widget _buildSuggestedPrompts() {
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
              label: Text(prompt, style: const TextStyle(fontSize: 12)),
              onPressed: () => _sendMessage(prompt),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.blue.withOpacity(0.3)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            '${widget.story.title.en.split(' ').first} is typing...',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: const InputDecoration(
                  hintText: 'Type in English...',
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
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _getCategoryIcon(String category) {
    IconData icon;
    Color color;
    switch (category.toLowerCase()) {
      case 'travel':
        icon = Icons.flight;
        color = Colors.blue;
        break;
      case 'business':
        icon = Icons.business_center;
        color = Colors.indigo;
        break;
      case 'daily_life':
        icon = Icons.home;
        color = Colors.teal;
        break;
      case 'food':
        icon = Icons.restaurant;
        color = Colors.orange;
        break;
      default:
        icon = Icons.chat_bubble;
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
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
        title: const Text('End Session?'),
        content: const Text(
          'Are you sure you want to end this conversation? Your progress will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
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
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
  }
}

/// Story context header widget
class _StoryContextHeader extends StatelessWidget {
  final TopicSession session;

  const _StoryContextHeader({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.blue.withOpacity(0.1),
            child: Text(
              session.rolePersona.name.isNotEmpty
                  ? session.rolePersona.name[0]
                  : '?',
              style: const TextStyle(
                color: Colors.blue,
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
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  session.rolePersona.role,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.bolt, size: 12, color: Colors.green),
                SizedBox(width: 4),
                Text(
                  'Context Ready',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.green,
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
    final isUser = message.isUser;

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
                const CircleAvatar(
                  radius: 14,
                  child: Icon(Icons.smart_toy, size: 16),
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
                    color: isUser ? Colors.blue : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    message.displayContent,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 15,
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
          if (!isUser && message.llmMetadata != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 36),
              child: Text(
                'AI optimized with ${message.llmMetadata!.provider}',
                style: TextStyle(fontSize: 9, color: Colors.grey[400]),
              ),
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
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.menu_book, color: Colors.blue),
                const SizedBox(width: 12),
                const Text(
                  'Key Vocabulary',
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
