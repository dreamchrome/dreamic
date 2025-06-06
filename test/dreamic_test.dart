import 'package:flutter_test/flutter_test.dart';

import 'package:dreamic/dreamic.dart';

void main() {
  test('flutter_base package loads without errors', () {
    // Test that the AppStatus enum contains expected values
    expect(AppStatus.values.contains(AppStatus.loading), isTrue);
    expect(AppStatus.values.contains(AppStatus.normal), isTrue);
    expect(AppStatus.values.contains(AppStatus.networkError), isTrue);
    expect(AppStatus.values.contains(AppStatus.error), isTrue);
  });
}
