import 'dart:io';

import 'package:easytrack/core/diagnostics/app_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('applog-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('log appends lines in order, which dump returns', () {
    final log = AppLog();
    log.log('erste', tag: 'test');
    log.log('zweite', tag: 'test');

    final dump = log.dump();
    expect(dump, contains('erste'));
    expect(dump, contains('zweite'));
    expect(dump.indexOf('erste'), lessThan(dump.indexOf('zweite')));
  });

  test('an error and stack are recorded, indented under the message', () {
    final log = AppLog();
    log.log(
      'kaputt',
      level: LogLevel.error,
      error: StateError('boom'),
      stack: StackTrace.current,
    );

    final dump = log.dump();
    expect(dump, contains('ERROR'));
    expect(dump, contains('kaputt'));
    expect(dump, contains('Bad state: boom'));
  });

  test('exportTo writes a file with the header and the buffer', () async {
    final log = AppLog();
    log.log('hallo welt', tag: 'test');

    final file = await log.exportTo(dir, header: 'KOPFZEILE');
    expect(file.existsSync(), isTrue);

    final text = await file.readAsString();
    expect(text, startsWith('KOPFZEILE'));
    expect(text, contains('hallo welt'));
  });

  test('clear drops the previous entries', () async {
    final log = AppLog();
    log.log('vor dem löschen');

    await log.clear();
    expect(log.dump(), isNot(contains('vor dem löschen')));
  });
}
