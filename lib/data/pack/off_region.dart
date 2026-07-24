/// Which slice of Open Food Facts to download.
///
/// Persisted by [wire] name. The build machine publishes one pack per region and
/// the manifest keys them by these names, so switching region is a pack swap,
/// not a re-filter on device.
enum OffRegion {
  de('de'),
  dach('dach'),
  world('world');

  const OffRegion(this.wire);

  final String wire;

  static const fallback = OffRegion.dach;

  static OffRegion fromWire(String? value) =>
      values.firstWhere((e) => e.wire == value, orElse: () => fallback);
}
