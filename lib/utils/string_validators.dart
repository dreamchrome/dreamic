bool isStringValidEmail(String email) {
  // A simple regex to validate email format
  final emailRegex = RegExp(
    r"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$",
    caseSensitive: false,
  );
  return emailRegex.hasMatch(email);
}

//TODO: improve this regex
bool isStringValidUrl(String url) {
  // A simple regex to validate URL format
  final urlRegex = RegExp(
    r'^(https?|ftp):\/\/[^\s/$.?#].[^\s]*$',
  );
  return urlRegex.hasMatch(url);
}

//TODO: improve this regex
bool isStringValidPhoneNumber(String phoneNumber) {
  // A simple regex to validate phone number format
  final phoneRegex = RegExp(
    r'^\+?[1-9]\d{1,14}$',
  );
  return phoneRegex.hasMatch(phoneNumber);
}

bool isStringValidName(String name) {
  // A simple regex to validate name format (only letters and spaces)
  RegExp nameRegex = RegExp(r"^[a-zA-Z]+(([',. -][a-zA-Z ])?[a-zA-Z]*)*$".toString());
  return nameRegex.hasMatch(name);
}

/// Password complexity presets for validation.
enum PasswordComplexity {
  /// Minimum 6 characters, no other requirements.
  /// Suitable for family-friendly apps with simple password needs.
  sixCharAnything,

  /// Minimum 8 characters, at least 1 letter and 1 number.
  /// Default complexity level for most applications.
  eightChar1Letter1Number,

  /// Minimum 8 characters, at least 2 uppercase, 2 numbers, and 2 special characters.
  /// High security for sensitive applications.
  eight2Upper2Number2Special,
}

/// Validates a password against the specified complexity requirements.
///
/// [password] The password string to validate.
/// [complexity] The complexity preset to validate against.
///   Defaults to [PasswordComplexity.eightChar1Letter1Number].
///
/// Returns `true` if the password meets the complexity requirements.
bool isStringValidPassword(
  String password, {
  PasswordComplexity complexity = PasswordComplexity.eightChar1Letter1Number,
}) {
  switch (complexity) {
    case PasswordComplexity.sixCharAnything:
      // Minimum 6 characters, any characters allowed
      return password.length >= 6;

    case PasswordComplexity.eightChar1Letter1Number:
      // Minimum 8 characters, at least one letter and one number
      final regex = RegExp(r'^(?=.*[a-zA-Z])(?=.*\d).{8,}$');
      return regex.hasMatch(password);

    case PasswordComplexity.eight2Upper2Number2Special:
      // Minimum 8 characters, at least 2 uppercase, 2 numbers, 2 special chars
      if (password.length < 8) return false;

      final uppercaseCount = RegExp(r'[A-Z]').allMatches(password).length;
      final numberCount = RegExp(r'\d').allMatches(password).length;
      final specialCount =
          RegExp(r'[!@#$%^&*()_+\-=\[\]{};:"\\|,.<>\/?]').allMatches(password).length;

      return uppercaseCount >= 2 && numberCount >= 2 && specialCount >= 2;
  }
}
