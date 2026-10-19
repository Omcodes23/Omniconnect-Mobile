/// Shared app-wide constants.
class AppConstants {
  AppConstants._();

  /// Synthetic user id the backend uses for the Internet-only AI companion
  /// node. It is never callable and has no LAN or Bluetooth presence.
  static const String aiAssistantUserId =
      '00000000-0000-0000-0000-0000000000ff';

  /// Display-name prefix of the AI companion node. Used as a fallback check
  /// when the id is not available.
  static const String aiAssistantNamePrefix = 'AI Assistant';
}
