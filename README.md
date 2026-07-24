# EasyTrack

A personal, local-first calorie and hydration tracker. Mobile-first Flutter app with an
offline German food database, barcode scanning, and no account or subscription required.

## Status

Early development. See `docs/` for the implementation plan.

## Features

- **Diary** — four meals per day (breakfast, lunch, dinner, snacks), calories + macros
- **Hydration** — water logging against a daily goal
- **Activity** — manual calorie-burn entries with a configurable safety factor
- **Search** — offline-first across the German BLS database and an Open Food Facts slice,
  with an online fallback that caches results locally
- **Barcode scanning** — camera scan resolved against the local product pack, then online
- **Custom foods & recipes** — build a recipe from ingredients, then log the portion you
  actually weighed
- **Targets** — TDEE calculated via Mifflin-St Jeor, always manually overridable

All data is stored locally on device. The schema is sync-ready so a server can be added
later without migration pain.

## Development

Requires Flutter 3.44+ and Node.js (for the food-data ETL under `tools/etl/`).

```bash
flutter pub get
flutter test
flutter run
```

## Data sources & attribution

### Bundeslebensmittelschlüssel (BLS) 4.0

Generic German food data comes from the BLS, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.de).

> Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0 –
> Deutsche Nährstoffdatenbank. Karlsruhe.
> DOI: [10.25826/Data20251217-134202-0](https://doi.org/10.25826/Data20251217-134202-0)

### Open Food Facts

Branded and barcode product data comes from [Open Food Facts](https://openfoodfacts.org),
made available under the [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/1-0/).
Product images are not used.

### USDA FoodData Central

Planned as an additional source. Public domain.

## License

The **source code** is licensed under the [GNU General Public License v3.0](LICENSE):
you're free to use, study, modify, and redistribute it, but derivative works must stay
open source under the same license.

The **bundled food data is not covered by the GPL** — it keeps the licenses noted above:
BLS 4.0 under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) and Open Food
Facts under the [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Redistributing
the data carries those obligations (attribution, plus share-alike for the Open Food
Facts-derived pack).
