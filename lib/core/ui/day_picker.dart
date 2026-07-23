import 'package:flutter/material.dart';

import '../time/day_key.dart';
import 'app_theme.dart';

/// Shows a calendar to pick a day, returning it, or null if dismissed.
///
/// Wraps [CalendarDatePicker] rather than the stock [showDatePicker] for one
/// reason: a **Heute** shortcut. The stock picker has no slot for an extra
/// action, so returning to today from a month away means swiping the grid there
/// by hand — the shortcut jumps straight to it. Today is always kept within the
/// selectable range so the shortcut can never point at a disabled cell.
///
/// [last] is the latest selectable day (today for a weigh-in, which cannot be
/// recorded in the future; the current day for the diary, which may already have
/// walked ahead of today via the chevrons).
Future<DayKey?> showDayPicker(
  BuildContext context, {
  required DayKey initial,
  required DayKey last,
}) {
  final today = DayKey.today();
  final lastDate = (last.value >= today.value ? last : today).toDateTime();
  var selected = initial.toDateTime();

  return showDialog<DayKey>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 328,
            height: 340,
            child: CalendarDatePicker(
              initialDate: selected,
              firstDate: DateTime(2020),
              lastDate: lastDate,
              currentDate: today.toDateTime(),
              onDateChanged: (date) => selected = date,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(today),
                  child: const Text('Heute'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(DayKey.fromDate(selected)),
                  child: const Text('Auswählen'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
