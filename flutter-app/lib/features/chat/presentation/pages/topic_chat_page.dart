import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/story_model.dart';
import '../../data/models/topic_session_model.dart';
import '../providers/story_provider.dart';
import '../widgets/educational_hints_widgets.dart';

/// Topic-Based Chat Page
/// Conversation with AI in a specific story/topic context
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
    // Start topic session on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSession();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
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

  Future<void> _sendMessage() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;

    _controller.clear();
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
      appBar: _buildAppBar(),
      body: Consumer<StoryProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && !provider.hasActiveSession) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              // Story context header
              if (provider.currentSession != null)
                _StoryContextHeader(session: provider.currentSession!),

              // Messages list
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

              // Typing indicator
              if (provider.isSendingMessage)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('AI is typing...'),
                    ],
                  ),
                ),

              // Input field
              _buildInputField(),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.story.title.en,
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            '${widget.story.category.toUpperCase()} • ${widget.story.difficultyLevel.shortName}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ],
      ),
      actions: [
        // Vocabulary preview button
        IconButton(
          icon: const Icon(Icons.menu_book),
          onPressed: _showVocabularyPreview,
          tooltip: 'Vocabulary',
        ),
        // End session button
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: _confirmEndSession,
          tooltip: 'End Session',
        ),
      ],
    );
  }

  Widget _buildInputField() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Type your message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            onPressed: _sendMessage,
            mini: true,
            elevation: 2,
            child: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  void _showVocabularyPreview() {
    final session = context.read<StoryProvider>().currentSession;
    if (session == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
        title: const Text('End Session?'),
        content: const Text(
          'Are you sure you want to end this conversation? '
          'Your progress will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<StoryProvider>().endSession();
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to story selection
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          // Character avatar
          CircleAvatar(
            backgroundColor: Theme.of(context).primaryColor,
            child: Text(
              session.rolePersona.name.isNotEmpty
                  ? session.rolePersona.name[0].toUpperCase()
                  : 'A',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Character info
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
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          // LLM indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy, size: 14, color: Colors.green),
                SizedBox(width: 4),
                Text(
                  'AI Active',
                  style: TextStyle(fontSize: 11, color: Colors.green),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Message bubble
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isUser
                  ? Theme.of(context).primaryColor
                  : Theme.of(context).cardColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
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
                color: isUser ? Colors.white : null,
              ),
            ),
          ),

          // Educational hints (for AI messages only)
          if (!isUser && message.hints != null && message.hints!.hasAnyHints)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: EducationalHintsCard(hints: message.hints!),
            ),

          // LLM metadata (for AI messages only)
          if (!isUser && message.llmMetadata != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${message.llmMetadata!.provider} • ${message.llmMetadata!.latencyMs}ms',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
                      fontSize: 10,
                    ),
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
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.menu_book),
                const SizedBox(width: 12),
                Text(
                  'Key Vocabulary',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Vocabulary list
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: vocabulary.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final item = vocabulary[index];
                return ListTile(
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
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.partOfSpeech,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(item.definition),
                      if (item.exampleInStory.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '"${item.exampleInStory}"',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      if (item.phonetic != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            item.phonetic!,
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
