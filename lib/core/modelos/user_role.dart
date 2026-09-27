enum UserRole {
  client,
  owner,
  professional,
  admin;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => UserRole.client,
    );
  }

  bool get isBusiness =>
      this == UserRole.owner ||
      this == UserRole.professional ||
      this == UserRole.admin;
}