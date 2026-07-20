/// Which slice of Open Food Facts to download.
///
/// Persisted by [wire] name. The build machine publishes one pack per region and
/// the manifest keys them by these names, so switching region is a pack swap,
/// not a re-filter on device.
enum OffRegion {
  de('de', 'Deutschland', 'Nur deutsche Produkte'),
  dach('dach', 'DACH', 'Deutschland, Österreich, Schweiz'),
  world('world', 'Weltweit', 'Größte Auswahl, größter Download');

  const OffRegion(this.wire, this.label, this.hint);

  final String wire;
  final String label;
  final String hint;

  static const fallback = OffRegion.dach;

  static OffRegion fromWire(String? value) =>
      values.firstWhere((e) => e.wire == value, orElse: () => fallback);
}
