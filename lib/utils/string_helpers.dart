import 'dart:convert';

class StringHelpers {
  static int getNumberOfWords(String s) {
    final RegExp regExp = RegExp(r"[\w-._]+");
    final Iterable matches = regExp.allMatches(s);
    return matches.length;
  }

  static String replaceTokens(
    String string,
    List<String> tokens,
    List<String> replacements, {
    bool convertSpacesToNewlines = false,
  }) {
    assert(tokens.length == replacements.length);

    String newString = string.substring(0, string.length);

    for (int i = 0; i < tokens.length; i++) {
      newString = newString.replaceAll(
          '{{${tokens[i]}}}',
          convertSpacesToNewlines
              ? capitalizeFirstLetter(replaceSpacesWithNewlines(replacements[i].trim()))
              : replacements[i]);
    }

    return newString;
  }

  // function that replaces any whitespace with a newline
  static String replaceSpacesWithNewlines(String string) {
    return string.replaceAll(' ', '\n');
  }

  // function to capitalize the first letter of a string if it's not empty, and handle strings of only one character
  static String capitalizeFirstLetter(String string) {
    if (string.isEmpty) {
      return string;
    }

    if (string.length == 1) {
      return string.toUpperCase();
    }

    return string[0].toUpperCase() + string.substring(1, string.length);
  }

  static List<String> replaceTokensInStrings(
    List<String> strings,
    List<String> tokens,
    List<String> replacements,
  ) {
    List<String> newStrings = [];

    for (String string in strings) {
      newStrings.add(replaceTokens(string, tokens, replacements));
    }

    return newStrings;
  }

  static int getNumberOfNewlines(String s) {
    // return s.allMatches('\n').length;
    return const LineSplitter().convert(s).length;
  }

  static String removeInOrderSoThat(String source) {
    final regex = RegExp(r'^(so that|in order to)\s+', caseSensitive: false);
    return source.replaceFirst(regex, '');
  }
}

extension StringX on String? {
  String firstLetterLowercaseOrFiller() {
    if (this?.isEmpty ?? true) {
      return '?????';
    }

    String s = this!;

    return s[0].toLowerCase() + (s.length > 1 ? s.substring(1, s.length) : '');
  }
}

extension StringX2 on String? {
  String orFillerIfNull() {
    if (this?.isEmpty ?? true) {
      return '?????';
    }
    return this!;
  }
}

String? encodeQueryParameters(Map<String, String> params) {
  return params.entries
      .map((MapEntry<String, String> e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}
