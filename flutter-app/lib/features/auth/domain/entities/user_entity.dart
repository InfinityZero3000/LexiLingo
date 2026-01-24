class UserEntity {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;

  UserEntity({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
  });
}
