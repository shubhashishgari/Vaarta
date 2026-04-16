// Vaarta — placeholder smoke test.
// The default Flutter counter template test has been removed because Vaarta
// has no counter widget. Add real tests here if needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:vaarta/main.dart';

void main() {
  test('VaartaApp can be instantiated', () {
    const app = VaartaApp();
    expect(app, isNotNull);
  });
}
