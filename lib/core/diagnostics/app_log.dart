import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Severity of a log line. Kept small on purpose — this is a diagnostic trail
/// for a personal app, not a structured logging framework.
enum LogLevel { debug, info, warn, error }

/// A tiny app-wide log: an in-memory ring buffer that is also mirrored to a file
/// so a crash's last lines survive a restart.
///
/// It exists so the user can export an "App-Protokoll" from
/// Einstellungen → DIAGNOSE when something misbehaves on the phone, where there
/// is no attached debugger. Every framework/platform/zone error routed in from
/// `main()` lands here, alongside explicit `log()` calls from the app.
///
/// Deliberately dependency-light and failure-tolerant: if the log file cannot be
/// opened (e.g. in unit tests, where path_provider has no platform behind it),
/// logging silently falls back to memory-only and never throws into the caller.
class AppLog {
  AppLog();

  /// The app-wide instance, wired up in `main()`.
  static final AppLog instance = AppLog();

  /// The ring buffer keeps the most recent [_maxLines]; older lines roll off, so
  /// the buffer and its file never grow without bound. ~3000 lines is a few
  /// hundred KB — enough to span a session's worth of events.
  static const _maxLines = 3000;

  final List<String> _lines = <String>[];
  File? _file;
  bool _initialized = false;
  Timer? _flushTimer;

  /// Opens (and loads) the on-disk log. Safe to call more than once; only the
  /// first call does anything. Never throws — a missing platform just leaves the
  /// logger memory-only.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'logs'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'easytrack.log'));
      if (file.existsSync()) {
        final existing = await file.readAsLines();
        _lines.addAll(
          existing.length > _maxLines
              ? existing.sublist(existing.length - _maxLines)
              : existing,
        );
      }
      _file = file;
    } catch (_) {
      _file = null; // Memory-only; export still works from the buffer.
    }
    log('App gestartet', tag: 'app');
  }

  /// Records one line. [tag] names a subsystem ("pack", "flutter"); [error] and
  /// [stack] are appended, indented, when present.
  void log(
    String message, {
    String tag = 'app',
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stack,
  }) {
    final ts = DateTime.now().toIso8601String();
    final sb = StringBuffer(
      '$ts  ${level.name.toUpperCase().padRight(5)} [$tag]  $message',
    );
    if (error != null) sb.write('\n    → $error');
    if (stack != null) {
      for (final line in stack.toString().trimRight().split('\n')) {
        sb.write('\n    $line');
      }
    }
    _append(sb.toString());
  }

  void _append(String entry) {
    _lines.add(entry);
    final overflow = _lines.length - _maxLines;
    if (overflow > 0) _lines.removeRange(0, overflow);
    // Mirror to the platform console so it is also visible under a live debugger.
    developer.log(entry, name: 'easytrack');
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_file == null) return;
    // Coalesce a burst of log calls into a single write a couple of seconds
    // later, rather than rewriting the file on every line.
    _flushTimer ??= Timer(const Duration(seconds: 2), () {
      _flushTimer = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString('${_lines.join('\n')}\n');
    } catch (_) {
      // A failed flush must not crash the app; the in-memory buffer still holds
      // everything for an immediate export.
    }
  }

  /// The whole buffer as text, newest last.
  String dump() => _lines.join('\n');

  /// Writes the buffer (optionally behind a [header]) to a fresh file in [dir]
  /// and returns it, ready to hand to the share sheet. Flushes first so the file
  /// on disk and the returned copy agree.
  Future<File> exportTo(Directory dir, {String? header}) async {
    await _flush();
    await dir.create(recursive: true);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final out = File(p.join(dir.path, 'easytrack-protokoll-$stamp.txt'));
    final sb = StringBuffer();
    if (header != null && header.isNotEmpty) sb.writeln(header);
    sb.writeln(_lines.join('\n'));
    await out.writeAsString(sb.toString());
    return out;
  }

  /// Empties the buffer and the file. Backs the "Protokoll löschen" action.
  Future<void> clear() async {
    _lines.clear();
    final file = _file;
    if (file != null) {
      try {
        if (file.existsSync()) await file.writeAsString('');
      } catch (_) {
        // Best effort — the in-memory buffer is already cleared.
      }
    }
    log('Protokoll geleert', tag: 'app');
  }
}
