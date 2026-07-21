import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/diagnostics/app_log.dart';

void main() {
  // Everything runs inside a guarded zone so uncaught async errors also reach
  // the exportable App-Protokoll, not just the ones the framework routes.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await AppLog.instance.init();

      // Route framework errors into the protocol while keeping Flutter's own
      // console/red-screen reporting intact (priorOnError == presentError).
      final priorOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        AppLog.instance.log(
          details.exceptionAsString(),
          tag: 'flutter',
          level: LogLevel.error,
          error: details.exception,
          stack: details.stack,
        );
        priorOnError?.call(details);
      };
      // The top-level hook for errors the framework does not wrap. Already
      // mirrored to the console by AppLog, so it is safe to report it handled.
      PlatformDispatcher.instance.onError = (error, stack) {
        AppLog.instance.log(
          'Unbehandelter Plattformfehler',
          tag: 'platform',
          level: LogLevel.error,
          error: error,
          stack: stack,
        );
        return true;
      };

      // Loads the German month and weekday names. Without this every DateFormat
      // constructed with an explicit 'de' locale throws at first use, which is a
      // crash on the diary's date header rather than a wrong-looking label.
      await initializeDateFormatting('de');
      runApp(const ProviderScope(child: EasyTrackApp()));
    },
    (error, stack) {
      AppLog.instance.log(
        'Unbehandelter Fehler',
        tag: 'zone',
        level: LogLevel.error,
        error: error,
        stack: stack,
      );
    },
  );
}
