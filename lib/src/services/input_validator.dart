class InputValidator {
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?)*$',
  );

  /// Matches E.164 format: optional +, then 7-15 digits.
  /// Allows spaces, dashes, parens as formatting but validates digit count.
  static final _phoneDigitsRegex = RegExp(r'^\d{7,15}$');

  static final _unsafeCharsRegex = RegExp(r'[<>"&\\]');

  static bool isValidEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty || trimmed.length > 254) return false;
    return _emailRegex.hasMatch(trimmed);
  }

  static bool isValidPhone(String phone) {
    final trimmed = phone.trim();
    // Strip everything except digits
    final digitsOnly = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    return _phoneDigitsRegex.hasMatch(digitsOnly);
  }

  static bool isValidPassword(String password, {int minLength = 8}) {
    if (password.length < minLength) return false;
    if (!password.contains(RegExp(r'[A-Z]'))) return false;
    if (!password.contains(RegExp(r'[a-z]'))) return false;
    if (!password.contains(RegExp(r'[0-9]'))) return false;
    return true;
  }

  static bool isValidDisplayName(String name) {
    final trimmed = name.trim();
    if (trimmed.length < 2 || trimmed.length > 50) return false;
    if (_unsafeCharsRegex.hasMatch(trimmed)) return false;
    return true;
  }

  static String sanitizeInput(String input) {
    return input
        .replaceAll('<', '')
        .replaceAll('>', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('&', '')
        .replaceAll('\\', '')
        .trim();
  }

  static bool isValidOtp(String otp, {int length = 6}) {
    return otp.length == length && RegExp(r'^\d+$').hasMatch(otp);
  }

  static bool isValidBio(String bio, {int maxLength = 500}) {
    if (bio.length > maxLength) return false;
    return true;
  }

  static final _urlRegex = RegExp(
    r'https?://|www\.|\.com/|\.net/|\.org/|\.io/',
    caseSensitive: false,
  );

  static bool containsUrl(String text) {
    return _urlRegex.hasMatch(text);
  }

  static String stripUrls(String text) {
    return text.replaceAll(
      RegExp(r'https?://\S+|www\.\S+', caseSensitive: false),
      '[link removed]',
    );
  }

  static bool isValidPhotoSize(int bytes, {int maxMb = 10}) {
    return bytes <= maxMb * 1024 * 1024;
  }

  static bool isValidPhotoFormat(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif') ||
        lower.endsWith('.webp');
  }

  static String sanitizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  static final _htmlTagRegex = RegExp(r'<[^>]*>');

  /// Sanitizes user text input by trimming whitespace, stripping HTML/script
  /// tags, removing unsafe characters, and enforcing a maximum length.
  /// Use this on all user-provided text before persisting to cloud storage.
  static String sanitizeText(String input, {int maxLength = 500}) {
    var result = input.trim();
    result = result.replaceAll(_htmlTagRegex, '');
    result = result
        .replaceAll('<', '')
        .replaceAll('>', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('&', '')
        .replaceAll('\\', '');
    if (result.length > maxLength) {
      result = result.substring(0, maxLength);
    }
    return result;
  }
}
