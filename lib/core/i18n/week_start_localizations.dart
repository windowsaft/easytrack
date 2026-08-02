// Members below the constructor are generated: every MaterialLocalizations
// member forwards to the wrapped instance verbatim. Only firstDayOfWeekIndex
// carries an opinion. If a Flutter upgrade adds a member, the build breaks here
// with a clear "missing implementation" and the forwarder can be pasted in.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../time/week_start.dart';

/// Makes Flutter's own date pickers honour the user's week-start setting.
///
/// The calendar grid takes its first column from
/// [MaterialLocalizations.firstDayOfWeekIndex], which [GlobalMaterialLocalizations]
/// derives from the locale — Sunday for English, Monday for German, with no way
/// to influence it. That left the setting governing the Verlauf ranges while
/// every picker ignored it, which reads as a bug rather than as a subtlety.
///
/// So the real localizations are loaded as normal and wrapped, with that one
/// value replaced. Everything else — every string, every date format — is the
/// genuine translation, untouched.
class WeekStartMaterialLocalizations implements MaterialLocalizations {
  const WeekStartMaterialLocalizations(this._inner, this._weekStart);

  final MaterialLocalizations _inner;
  final WeekStart _weekStart;

  /// Material counts from Sunday at index 0, [DateTime] from Monday at 1, so
  /// Sunday's 7 has to wrap back to 0.
  @override
  int get firstDayOfWeekIndex => _weekStart.firstWeekday % 7;

  @override
  String get openAppDrawerTooltip => _inner.openAppDrawerTooltip;

  @override
  String get backButtonTooltip => _inner.backButtonTooltip;

  @override
  String get clearButtonTooltip => _inner.clearButtonTooltip;

  @override
  String get closeButtonTooltip => _inner.closeButtonTooltip;

  @override
  String get deleteButtonTooltip => _inner.deleteButtonTooltip;

  @override
  String get moreButtonTooltip => _inner.moreButtonTooltip;

  @override
  String get nextMonthTooltip => _inner.nextMonthTooltip;

  @override
  String get previousMonthTooltip => _inner.previousMonthTooltip;

  @override
  String get firstPageTooltip => _inner.firstPageTooltip;

  @override
  String get lastPageTooltip => _inner.lastPageTooltip;

  @override
  String get nextPageTooltip => _inner.nextPageTooltip;

  @override
  String get previousPageTooltip => _inner.previousPageTooltip;

  @override
  String get showMenuTooltip => _inner.showMenuTooltip;

  @override
  String aboutListTileTitle(String applicationName) => _inner.aboutListTileTitle(applicationName);

  @override
  String get licensesPageTitle => _inner.licensesPageTitle;

  @override
  String licensesPackageDetailText(int licenseCount) => _inner.licensesPackageDetailText(licenseCount);

  @override
  String pageRowsInfoTitle(int firstRow, int lastRow, int rowCount, bool rowCountIsApproximate) => _inner.pageRowsInfoTitle(firstRow, lastRow, rowCount, rowCountIsApproximate);

  @override
  String get rowsPerPageTitle => _inner.rowsPerPageTitle;

  @override
  String tabLabel({required int tabIndex, required int tabCount}) => _inner.tabLabel(tabIndex: tabIndex, tabCount: tabCount);

  @override
  String selectedRowCountTitle(int selectedRowCount) => _inner.selectedRowCountTitle(selectedRowCount);

  @override
  String get cancelButtonLabel => _inner.cancelButtonLabel;

  @override
  String get closeButtonLabel => _inner.closeButtonLabel;

  @override
  String get continueButtonLabel => _inner.continueButtonLabel;

  @override
  String get copyButtonLabel => _inner.copyButtonLabel;

  @override
  String get cutButtonLabel => _inner.cutButtonLabel;

  @override
  String get scanTextButtonLabel => _inner.scanTextButtonLabel;

  @override
  String get okButtonLabel => _inner.okButtonLabel;

  @override
  String get pasteButtonLabel => _inner.pasteButtonLabel;

  @override
  String get selectAllButtonLabel => _inner.selectAllButtonLabel;

  @override
  String get lookUpButtonLabel => _inner.lookUpButtonLabel;

  @override
  String get searchWebButtonLabel => _inner.searchWebButtonLabel;

  @override
  String get shareButtonLabel => _inner.shareButtonLabel;

  @override
  String get viewLicensesButtonLabel => _inner.viewLicensesButtonLabel;

  @override
  String get anteMeridiemAbbreviation => _inner.anteMeridiemAbbreviation;

  @override
  String get postMeridiemAbbreviation => _inner.postMeridiemAbbreviation;

  @override
  String get timePickerHourModeAnnouncement => _inner.timePickerHourModeAnnouncement;

  @override
  String get timePickerMinuteModeAnnouncement => _inner.timePickerMinuteModeAnnouncement;

  @override
  String get modalBarrierDismissLabel => _inner.modalBarrierDismissLabel;

  @override
  String get menuDismissLabel => _inner.menuDismissLabel;

  @override
  String get drawerLabel => _inner.drawerLabel;

  @override
  String get popupMenuLabel => _inner.popupMenuLabel;

  @override
  String get menuBarMenuLabel => _inner.menuBarMenuLabel;

  @override
  String get dialogLabel => _inner.dialogLabel;

  @override
  String get alertDialogLabel => _inner.alertDialogLabel;

  @override
  String get searchFieldLabel => _inner.searchFieldLabel;

  @override
  String get currentDateLabel => _inner.currentDateLabel;

  @override
  String get selectedDateLabel => _inner.selectedDateLabel;

  @override
  String get scrimLabel => _inner.scrimLabel;

  @override
  String get bottomSheetLabel => _inner.bottomSheetLabel;

  @override
  String scrimOnTapHint(String modalRouteContentName) => _inner.scrimOnTapHint(modalRouteContentName);

  @override
  TimeOfDayFormat timeOfDayFormat({bool alwaysUse24HourFormat = false}) => _inner.timeOfDayFormat(alwaysUse24HourFormat: alwaysUse24HourFormat);

  @override
  ScriptCategory get scriptCategory => _inner.scriptCategory;

  @override
  String formatDecimal(int number) => _inner.formatDecimal(number);

  @override
  String formatHour(TimeOfDay timeOfDay, {bool alwaysUse24HourFormat = false}) => _inner.formatHour(timeOfDay, alwaysUse24HourFormat: alwaysUse24HourFormat);

  @override
  String formatMinute(TimeOfDay timeOfDay) => _inner.formatMinute(timeOfDay);

  @override
  String formatTimeOfDay(TimeOfDay timeOfDay, {bool alwaysUse24HourFormat = false}) => _inner.formatTimeOfDay(timeOfDay, alwaysUse24HourFormat: alwaysUse24HourFormat);

  @override
  String formatYear(DateTime date) => _inner.formatYear(date);

  @override
  String formatCompactDate(DateTime date) => _inner.formatCompactDate(date);

  @override
  String formatShortDate(DateTime date) => _inner.formatShortDate(date);

  @override
  String formatMediumDate(DateTime date) => _inner.formatMediumDate(date);

  @override
  String formatFullDate(DateTime date) => _inner.formatFullDate(date);

  @override
  String formatMonthYear(DateTime date) => _inner.formatMonthYear(date);

  @override
  String formatShortMonthDay(DateTime date) => _inner.formatShortMonthDay(date);

  @override
  DateTime? parseCompactDate(String? inputString) => _inner.parseCompactDate(inputString);

  @override
  List<String> get narrowWeekdays => _inner.narrowWeekdays;

  @override
  String get dateSeparator => _inner.dateSeparator;

  @override
  String get dateHelpText => _inner.dateHelpText;

  @override
  String get selectYearSemanticsLabel => _inner.selectYearSemanticsLabel;

  @override
  String get unspecifiedDate => _inner.unspecifiedDate;

  @override
  String get unspecifiedDateRange => _inner.unspecifiedDateRange;

  @override
  String get dateInputLabel => _inner.dateInputLabel;

  @override
  String get dateRangeStartLabel => _inner.dateRangeStartLabel;

  @override
  String get dateRangeEndLabel => _inner.dateRangeEndLabel;

  @override
  String dateRangeStartDateSemanticLabel(String formattedDate) => _inner.dateRangeStartDateSemanticLabel(formattedDate);

  @override
  String dateRangeEndDateSemanticLabel(String formattedDate) => _inner.dateRangeEndDateSemanticLabel(formattedDate);

  @override
  String get invalidDateFormatLabel => _inner.invalidDateFormatLabel;

  @override
  String get invalidDateRangeLabel => _inner.invalidDateRangeLabel;

  @override
  String get dateOutOfRangeLabel => _inner.dateOutOfRangeLabel;

  @override
  String get saveButtonLabel => _inner.saveButtonLabel;

  @override
  String get datePickerHelpText => _inner.datePickerHelpText;

  @override
  String get dateRangePickerHelpText => _inner.dateRangePickerHelpText;

  @override
  String get calendarModeButtonLabel => _inner.calendarModeButtonLabel;

  @override
  String get inputDateModeButtonLabel => _inner.inputDateModeButtonLabel;

  @override
  String get timePickerDialHelpText => _inner.timePickerDialHelpText;

  @override
  String get timePickerInputHelpText => _inner.timePickerInputHelpText;

  @override
  String get timePickerHourLabel => _inner.timePickerHourLabel;

  @override
  String get timePickerMinuteLabel => _inner.timePickerMinuteLabel;

  @override
  String get invalidTimeLabel => _inner.invalidTimeLabel;

  @override
  String get dialModeButtonLabel => _inner.dialModeButtonLabel;

  @override
  String get inputTimeModeButtonLabel => _inner.inputTimeModeButtonLabel;

  @override
  String get signedInLabel => _inner.signedInLabel;

  @override
  String get hideAccountsLabel => _inner.hideAccountsLabel;

  @override
  String get showAccountsLabel => _inner.showAccountsLabel;

  @override
  // ignore: deprecated_member_use
  String get reorderItemToStart => _inner.reorderItemToStart;

  @override
  // ignore: deprecated_member_use
  String get reorderItemToEnd => _inner.reorderItemToEnd;

  @override
  // ignore: deprecated_member_use
  String get reorderItemUp => _inner.reorderItemUp;

  @override
  // ignore: deprecated_member_use
  String get reorderItemDown => _inner.reorderItemDown;

  @override
  // ignore: deprecated_member_use
  String get reorderItemLeft => _inner.reorderItemLeft;

  @override
  // ignore: deprecated_member_use
  String get reorderItemRight => _inner.reorderItemRight;

  @override
  String get expandedIconTapHint => _inner.expandedIconTapHint;

  @override
  String get collapsedIconTapHint => _inner.collapsedIconTapHint;

  @override
  String get expansionTileExpandedHint => _inner.expansionTileExpandedHint;

  @override
  String get expansionTileCollapsedHint => _inner.expansionTileCollapsedHint;

  @override
  String get expansionTileExpandedTapHint => _inner.expansionTileExpandedTapHint;

  @override
  String get expansionTileCollapsedTapHint => _inner.expansionTileCollapsedTapHint;

  @override
  String get expandedHint => _inner.expandedHint;

  @override
  String get collapsedHint => _inner.collapsedHint;

  @override
  String remainingTextFieldCharacterCount(int remaining) => _inner.remainingTextFieldCharacterCount(remaining);

  @override
  String get refreshIndicatorSemanticLabel => _inner.refreshIndicatorSemanticLabel;

  @override
  String get keyboardKeyAlt => _inner.keyboardKeyAlt;

  @override
  String get keyboardKeyAltGraph => _inner.keyboardKeyAltGraph;

  @override
  String get keyboardKeyBackspace => _inner.keyboardKeyBackspace;

  @override
  String get keyboardKeyCapsLock => _inner.keyboardKeyCapsLock;

  @override
  String get keyboardKeyChannelDown => _inner.keyboardKeyChannelDown;

  @override
  String get keyboardKeyChannelUp => _inner.keyboardKeyChannelUp;

  @override
  String get keyboardKeyControl => _inner.keyboardKeyControl;

  @override
  String get keyboardKeyDelete => _inner.keyboardKeyDelete;

  @override
  String get keyboardKeyEject => _inner.keyboardKeyEject;

  @override
  String get keyboardKeyEnd => _inner.keyboardKeyEnd;

  @override
  String get keyboardKeyEscape => _inner.keyboardKeyEscape;

  @override
  String get keyboardKeyFn => _inner.keyboardKeyFn;

  @override
  String get keyboardKeyHome => _inner.keyboardKeyHome;

  @override
  String get keyboardKeyInsert => _inner.keyboardKeyInsert;

  @override
  String get keyboardKeyMeta => _inner.keyboardKeyMeta;

  @override
  String get keyboardKeyMetaMacOs => _inner.keyboardKeyMetaMacOs;

  @override
  String get keyboardKeyMetaWindows => _inner.keyboardKeyMetaWindows;

  @override
  String get keyboardKeyNumLock => _inner.keyboardKeyNumLock;

  @override
  String get keyboardKeyNumpad1 => _inner.keyboardKeyNumpad1;

  @override
  String get keyboardKeyNumpad2 => _inner.keyboardKeyNumpad2;

  @override
  String get keyboardKeyNumpad3 => _inner.keyboardKeyNumpad3;

  @override
  String get keyboardKeyNumpad4 => _inner.keyboardKeyNumpad4;

  @override
  String get keyboardKeyNumpad5 => _inner.keyboardKeyNumpad5;

  @override
  String get keyboardKeyNumpad6 => _inner.keyboardKeyNumpad6;

  @override
  String get keyboardKeyNumpad7 => _inner.keyboardKeyNumpad7;

  @override
  String get keyboardKeyNumpad8 => _inner.keyboardKeyNumpad8;

  @override
  String get keyboardKeyNumpad9 => _inner.keyboardKeyNumpad9;

  @override
  String get keyboardKeyNumpad0 => _inner.keyboardKeyNumpad0;

  @override
  String get keyboardKeyNumpadAdd => _inner.keyboardKeyNumpadAdd;

  @override
  String get keyboardKeyNumpadComma => _inner.keyboardKeyNumpadComma;

  @override
  String get keyboardKeyNumpadDecimal => _inner.keyboardKeyNumpadDecimal;

  @override
  String get keyboardKeyNumpadDivide => _inner.keyboardKeyNumpadDivide;

  @override
  String get keyboardKeyNumpadEnter => _inner.keyboardKeyNumpadEnter;

  @override
  String get keyboardKeyNumpadEqual => _inner.keyboardKeyNumpadEqual;

  @override
  String get keyboardKeyNumpadMultiply => _inner.keyboardKeyNumpadMultiply;

  @override
  String get keyboardKeyNumpadParenLeft => _inner.keyboardKeyNumpadParenLeft;

  @override
  String get keyboardKeyNumpadParenRight => _inner.keyboardKeyNumpadParenRight;

  @override
  String get keyboardKeyNumpadSubtract => _inner.keyboardKeyNumpadSubtract;

  @override
  String get keyboardKeyPageDown => _inner.keyboardKeyPageDown;

  @override
  String get keyboardKeyPageUp => _inner.keyboardKeyPageUp;

  @override
  String get keyboardKeyPower => _inner.keyboardKeyPower;

  @override
  String get keyboardKeyPowerOff => _inner.keyboardKeyPowerOff;

  @override
  String get keyboardKeyPrintScreen => _inner.keyboardKeyPrintScreen;

  @override
  String get keyboardKeyScrollLock => _inner.keyboardKeyScrollLock;

  @override
  String get keyboardKeySelect => _inner.keyboardKeySelect;

  @override
  String get keyboardKeyShift => _inner.keyboardKeyShift;

  @override
  String get keyboardKeySpace => _inner.keyboardKeySpace;

}

/// Loads the stock localizations for the locale and wraps them, so this must sit
/// ahead of [GlobalMaterialLocalizations.delegate] in the delegate list —
/// Flutter keeps only the first delegate per type.
class WeekStartMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const WeekStartMaterialLocalizationsDelegate(this.weekStart);

  final WeekStart weekStart;

  @override
  bool isSupported(Locale locale) =>
      GlobalMaterialLocalizations.delegate.isSupported(locale);

  /// The wrapped delegate resolves synchronously, and [SynchronousFuture.then]
  /// keeps it that way — an async hop here would blank the first frame.
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(locale).then(
        (inner) => WeekStartMaterialLocalizations(inner, weekStart),
      );

  @override
  bool shouldReload(WeekStartMaterialLocalizationsDelegate old) =>
      old.weekStart != weekStart;
}
