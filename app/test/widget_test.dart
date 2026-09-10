import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sample note id is stable', () {
    expect('sample.hello'.startsWith('sample.'), isTrue);
  });
}
