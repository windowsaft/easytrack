import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads the German month and weekday names. Without this every DateFormat
  // constructed with an explicit 'de' locale throws at first use, which is a
  // crash on the diary's date header rather than a wrong-looking label.
  await initializeDateFormatting('de');
  runApp(const ProviderScope(child: EasyTrackApp()));
}
