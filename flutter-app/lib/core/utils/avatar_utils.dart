library;

class AvatarUtils {
  AvatarUtils._();

  static const List<String> presetAvatarUrls = [
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Leo',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Luna',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Max',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Mia',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Felix',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Zoe',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Charlie',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Lily',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Aiden',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Aurora',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Noah',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Ivy',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Ezra',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Nova',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Theo',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Aria',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Kai',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Willow',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Milo',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Ruby',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Owen',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Nora',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Hugo',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Clara',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Finn',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Elena',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Jasper',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Stella',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Atlas',
    'https://api.dicebear.com/7.x/adventurer/svg?seed=Hazel',
  ];

  static String? normalizeAvatarUrl(String? rawUrl) {
    if (rawUrl == null) return null;

    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final withScheme = trimmed.startsWith('//') ? 'https:$trimmed' : trimmed;

    final uri = Uri.tryParse(withScheme);
    if (uri == null) return null;

    if (uri.scheme.toLowerCase() == 'http') {
      final host = uri.host.toLowerCase();
      const httpsPreferredHosts = [
        'googleusercontent.com',
        'gstatic.com',
        'dicebear.com',
        'gravatar.com',
        'pravatar.cc',
      ];

      final shouldUpgrade = httpsPreferredHosts.any(
        (domain) => host == domain || host.endsWith('.$domain'),
      );

      if (shouldUpgrade) {
        return withScheme.replaceFirst('http://', 'https://');
      }
    }

    return withScheme;
  }

  static bool isSvgUrl(String? rawUrl) {
    final normalized = normalizeAvatarUrl(rawUrl);
    if (normalized == null) return false;

    final uri = Uri.tryParse(normalized);
    if (uri == null) return false;

    final path = uri.path.toLowerCase();
    if (path.endsWith('.svg') || path.endsWith('/svg')) return true;

    final query = uri.query.toLowerCase();
    return query.contains('format=svg');
  }
}