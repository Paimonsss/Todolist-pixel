import 'package:flutter_test/flutter_test.dart';
import 'package:tugas_quest/core/submission_checker.dart';

void main() {
  test('balasan skrip hanya menerima acara yang diminta', () {
    final result = parseCheckMessage(
      '{"ok":true,"timelineOk":true,"events":{'
      '"11":{"verdict":"submitted","module":"assign"},'
      '"12":{"verdict":"timeline","module":"quiz"},'
      '"13":{"verdict":"draft","module":"assign"},'
      '"14":{"verdict":"open","module":"assign"},'
      '"99":{"verdict":"submitted","module":"assign"}}}',
      [11, 12, 13, 14],
    );
    expect(result.status, CheckStatus.ok);
    expect(result.timelineOk, isTrue);
    expect(result.submitted, {11, 12});
    expect(result.events.containsKey(99), isFalse);
  });

  test('balasan rusak atau gagal dianggap gagal', () {
    expect(parseCheckMessage('{"ok":false}', [1]).status, CheckStatus.failed);
    expect(parseCheckMessage('bukan json', [1]).status, CheckStatus.failed);
  });
}
