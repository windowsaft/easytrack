import 'dart:convert';

import 'package:easytrack/core/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

String releases(List<Map<String, dynamic>> entries) => jsonEncode(entries);

Map<String, dynamic> rel(
  String tag, {
  bool draft = false,
  bool prerelease = false,
  String url = 'https://example/r',
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'html_url': url,
};

void main() {
  group('latestUpdateFrom', () {
    test('returns the newer version with its release url', () {
      final update = latestUpdateFrom(
        releases([rel('v1.2.0', url: 'https://example/v120')]),
        '1.1.0',
      );
      expect(update, isNotNull);
      expect(update!.version, '1.2.0');
      expect(update.url, 'https://example/v120');
    });

    test('returns null when already on the latest version', () {
      expect(latestUpdateFrom(releases([rel('v1.0.0')]), '1.0.0'), isNull);
    });

    test('returns null when the running build is newer', () {
      expect(latestUpdateFrom(releases([rel('v1.0.0')]), '1.1.0'), isNull);
    });

    test('ignores the off-latest pack tag and other non-version tags', () {
      final update = latestUpdateFrom(
        releases([rel('off-latest'), rel('v1.0.1')]),
        '1.0.0',
      );
      expect(update!.version, '1.0.1');
    });

    test('skips drafts and pre-releases', () {
      final update = latestUpdateFrom(
        releases([
          rel('v2.0.0', prerelease: true),
          rel('v1.9.0', draft: true),
          rel('v1.1.0'),
        ]),
        '1.0.0',
      );
      expect(update!.version, '1.1.0');
    });

    test('compares numerically, not lexically (v1.10 > v1.9)', () {
      final update = latestUpdateFrom(releases([rel('v1.10.0')]), '1.9.0');
      expect(update!.version, '1.10.0');
    });

    test('null on a non-list body', () {
      expect(latestUpdateFrom('{}', '1.0.0'), isNull);
    });
  });
}
