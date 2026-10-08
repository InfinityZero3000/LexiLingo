class PromoBanner {
  final String id, title, imageUrl;
  final String? description, linkUrl;

  const PromoBanner({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.description,
    this.linkUrl,
  });

  factory PromoBanner.fromJson(Map<String, dynamic> json) => PromoBanner(
    id: json['id']?.toString() ?? '',
    title: json['title'] ?? '',
    imageUrl: json['image_url'] ?? '',
    description: json['description']?.toString(),
    linkUrl: json['link_url']?.toString(),
  );
}
