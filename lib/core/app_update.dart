import 'dart:convert';

/// A newer app version found on GitHub Releases — the hint shown to sideloaded
/// installs, which (unlike Play Store / App Store builds) get no auto-update.
class AppUpdate {
  const AppUpdate({required this.version, required this.url});

  /// The newer version without a leading "v", e.g. "1.0.1".
  final String version;

  /// The release page to open in the browser.
  final String url;
}

/// Picks the newest published `v<semver>` release from a GitHub `/releases`
/// JSON body and returns it as an [AppUpdate] when it is newer than
/// [currentVersion]; otherwise null.
///
/// The rolling pack release (tag `off-latest`), drafts and pre-releases are
/// ignored, so only real app releases count. Pure, so it is unit-testable
/// without a network. GitHub returns releases newest-first, so the first
/// version-tagged entry is the latest.
AppUpdate? latestUpdateFrom(String releasesJson, String currentVersion) {
  final decoded = jsonDecode(releasesJson);
  if (decoded is! List) return null;
  final versionTag = RegExp(r'^v(\d+\.\d+\.\d+)$');
  for (final entry in decoded) {
    if (entry is! Map) continue;
    if (entry['draft'] == true || entry['prerelease'] == true) continue;
    final match = versionTag.firstMatch((entry['tag_name'] as String?) ?? '');
    if (match == null) continue; // off-latest and other non-version tags
    final version = match.group(1)!;
    if (!_isNewer(version, currentVersion)) return null;
    final url = entry['html_url'] as String?;
    return url == null ? null : AppUpdate(version: version, url: url);
  }
  return null;
}

/// Numeric dotted-version comparison: true when [a] is strictly newer than [b].
bool _isNewer(String a, String b) {
  final pa = a.split('.');
  final pb = b.split('.');
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? int.tryParse(pa[i]) ?? 0 : 0;
    final y = i < pb.length ? int.tryParse(pb[i]) ?? 0 : 0;
    if (x != y) return x > y;
  }
  return false;
}
