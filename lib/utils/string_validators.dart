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

//TODO: improve this regex
bool isStringValidPassword(String password) {
  // A simple regex to validate password format (at least 8 characters, at least one letter and one number)
  final passwordRegex = RegExp(
    r'^(?=.*[a-zA-Z])(?=.*\d)[a-zA-Z\d]{8,}$',
  );
  return passwordRegex.hasMatch(password);
}
