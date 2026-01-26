# Chat Widgets

Reusable UI components for the Chat feature.

## Components

### MessageBubble
Displays individual chat messages with full styling and interactivity.

**Features**:
- User/AI message differentiation
- Avatar icons
- Timestamps
- Markdown rendering (AI messages only)
- Copy to clipboard
- Status indicators (sending/sent/error)
- Retry on error
- Dark mode support

**Usage**:
```dart
MessageBubble(
  message: chatMessage,
  showAvatar: true,
  showTimestamp: true,
  onRetry: () {
    // Handle retry
  },
)
```

### SessionListDrawer
Navigation drawer for session management.

**Features**:
- List of all chat sessions
- Create new session
- Switch between sessions
- Rename session (dialog)
- Delete session (confirmation)
- Active session highlighting
- Empty state

**Usage**:
```dart
Drawer(
  child: SessionListDrawer(
    sessions: sessions,
    currentSessionId: currentId,
    onSessionTap: (id) => selectSession(id),
    onNewSession: () => createSession(),
    onDeleteSession: (session) => deleteSession(session),
    onRenameSession: (session, title) => renameSession(session, title),
  ),
)
```

### MarkdownMessageContent
Renders markdown-formatted text for AI responses.

**Features**:
- Full markdown syntax support
- Syntax highlighting for code blocks
- Clickable links
- Styled blockquotes
- Custom theme integration
- Selectable text

**Usage**:
```dart
MarkdownMessageContent(
  content: markdownText,
  isDark: Theme.of(context).brightness == Brightness.dark,
)
```

## Styling Guidelines

### Colors
- User messages: `AppColors.primary` (blue)
- AI messages: `Color(0xFFF0F2F4)` (light grey) / `Colors.grey[800]` (dark mode)
- Accent: `AppColors.accentYellow`
- Text: `AppColors.textDark` / `AppColors.textGrey`

### Spacing
- Message padding: `16px`
- Message margin: `16px bottom`
- Avatar size: `32x32`
- Avatar margin: `4px bottom`

### Typography
- Message text: `bodyMedium`
- Timestamp: `11px, w500`
- Sender label: `11px, w500`

## Dependencies

- `flutter/material.dart` - Core UI framework
- `flutter_markdown` - Markdown rendering
- `url_launcher` - External link handling
- `intl` - Date/time formatting

## Best Practices

1. **Performance**: Use `const` constructors where possible
2. **Accessibility**: Ensure proper contrast ratios
3. **Responsiveness**: Test on various screen sizes
4. **Error Handling**: Always provide fallback states
5. **Dark Mode**: Test both light and dark themes

## Testing

See `test/features/chat/presentation/widgets/` for widget tests.

## Future Enhancements

- [ ] Message reactions (👍, ❤️, etc.)
- [ ] Message edit/delete
- [ ] Voice message playback UI
- [ ] Image/file attachments
- [ ] Search within messages
- [ ] Message threading
