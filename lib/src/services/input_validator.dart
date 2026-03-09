class InputValidator {
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?)*$',
  );

  static final _phoneRegex = RegExp(r'^\+?[\d\s\-\(\)]{10,16}$');

  static final _unsafeCharsRegex = RegExp(r'[<>"&\\]');

  static bool isValidEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty || trimmed.length > 254) return false;
    return _emailRegex.hasMatch(trimmed);
  }

  static bool isValidPhone(String phone) {
    final trimmed = phone.trim();
    final digitsOnly = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length < 10 || digitsOnly.length > 15) return false;
    return _phoneRegex.hasMatch(trimmed);
  }

  static bool isValidPassword(String password, {int minLength = 8}) {
    return password.length >= minLength;
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
}
