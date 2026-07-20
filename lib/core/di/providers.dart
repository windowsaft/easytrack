import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/reference_database.dart';
import '../../data/db/user_database.dart';
import '../../data/food/barcode_resolver.dart';
import '../../data/food/bls_provider.dart';
import '../../data/food/custom_food_provider.dart';
import '../../data/food/food_item.dart';
import '../../data/food/food_provider.dart';
import '../../data/food/food_resolver.dart';
import '../../data/food/off_api_client.dart';
import '../../data/food/off_local_provider.dart';
import '../../data/food/recipe_provider.dart';
import '../../data/food/search_orchestrator.dart';
import '../../data/pack/off_pack_database.dart';
import '../../data/pack/pack_installer.dart';
import '../../data/pack/pack_service.dart';
import '../../data/repositories/custom_food_repository.dart';
import '../../data/repositories/diary_repository.dart';
import '../../data/repositories/off_cache_repository.dart';
import '../../data/repositories/pinned_foods_repository.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/day_summary.dart';
import '../nutrition/food_ref.dart';
import '../time/day_key.dart';

/// The local user database. Lives for the whole app session.
final userDatabaseProvider = Provider<UserDatabase>((ref) {
  final db = UserDatabase();
  ref.onDispose(db.close);
  return db;
});

/// The bundled reference pack, copied out of assets on first run.
final referenceDatabaseProvider = FutureProvider<ReferenceDatabase>((
  ref,
) async {
  final db = await ReferenceDatabase.open();
  ref.onDispose(db.dispose);
  return db;
});

/// Morphemes for compound splitting, shared with the ETL so that the runtime
/// and the index agree on how "Vollkornbrot" decomposes.
final morphemesProvider = FutureProvider<Set<String>>((ref) async {
  final raw = await rootBundle.loadString('tools/etl/de_food_morphemes.txt');
  return raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toSet();
});

/// How many times each food has been logged, used to boost search ranking.
///
/// Loaded once and kept in memory: it is a few hundred entries at most, and
/// computing it here avoids a join across the user and reference databases,
/// which are deliberately separate files.
final recencyIndexProvider = FutureProvider<RecencyIndex>((ref) async {
  final db = ref.watch(userDatabaseProvider);

  final rows = await db
      .customSelect(
        '''
        SELECT source_type, source_id, COUNT(*) AS n
        FROM diary_entries
        WHERE deleted_at IS NULL
        GROUP BY source_type, source_id
        ORDER BY n DESC
        LIMIT 500
        ''',
        readsFrom: {db.diaryEntries},
      )
      .get();

  return {
    for (final row in rows)
      FoodRef(
        FoodSourceType.fromWire(row.read<String>('source_type')),
        row.read<String>('source_id'),
      ): row.read<int>(
        'n',
      ),
  };
});

/// All locally available food sources, highest priority first.
///
/// The Open Food Facts provider joins only once a pack has been downloaded and
/// installed; until then search is BLS + the user's own foods, fully offline.
final localFoodProvidersProvider = FutureProvider<List<FoodProvider>>((
  ref,
) async {
  final reference = await ref.watch(referenceDatabaseProvider.future);
  final db = ref.watch(userDatabaseProvider);
  // Read the pack's *current* value rather than awaiting it: the OFF pack is
  // optional, so search must not block on it loading (or on the preferences
  // plugin behind it). Once the pack resolves, this provider re-runs and the
  // OFF source appears; until then search runs on BLS + the user's own foods.
  final offPack = switch (ref.watch(offPackProvider)) {
    AsyncData(:final value) => value,
    _ => null,
  };

  return [
    CustomFoodProvider(db),
    RecipeProvider(db),
    BlsProvider(reference),
    if (offPack != null) OffLocalProvider(offPack),
  ];
});

/// Device-local key/value store. Backs the product-pack bookkeeping.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

/// Owns the downloadable Open Food Facts pack: region, install state, updates.
final packServiceProvider = FutureProvider<PackService>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);

  Future<http.Response> get(Uri url) async {
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw PackInstallException('HTTP ${response.statusCode} bei $url');
    }
    return response;
  }

  return PackService(
    prefs: prefs,
    installer: PackInstaller((url) async => (await get(url)).bodyBytes),
    fetchManifestText: (url) async => (await get(url)).body,
    supportDirectory: getApplicationSupportDirectory,
  );
});

/// The installed product pack, or null when none is installed (or the installed
/// file is unreadable, which is treated the same as absent).
final offPackProvider = FutureProvider<OffPackDatabase?>((ref) async {
  try {
    final service = await ref.watch(packServiceProvider.future);
    final file = await service.packFile();
    if (!file.existsSync()) return null;
    final pack = OffPackDatabase.openAt(file.path);
    ref.onDispose(pack.dispose);
    return pack;
  } catch (_) {
    // Anything upstream failing — no preferences store, no app-support
    // directory, or a corrupt/incompatible pack — is treated as "no pack": the
    // app stays on BLS rather than crashing the whole search path. This also
    // keeps the search stack buildable in unit tests, where the plugins behind
    // the pack service are absent.
    return null;
  }
});

/// Install state for the Settings product-data row.
final packStateProvider = FutureProvider<PackInstallState>((ref) async {
  final service = await ref.watch(packServiceProvider.future);
  return service.state();
});

/// The search entry point used by the UI.
final searchOrchestratorProvider = FutureProvider<FoodSearchOrchestrator>((
  ref,
) async {
  final local = await ref.watch(localFoodProvidersProvider.future);
  final recency = await ref.watch(recencyIndexProvider.future);

  return FoodSearchOrchestrator(
    local: local,
    // Open Food Facts providers are registered here in a later phase; the
    // orchestrator already handles the fallback.
    recency: recency,
  );
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(userDatabaseProvider)),
);

final diaryRepositoryProvider = Provider<DiaryRepository>(
  (ref) => DiaryRepository(
    ref.watch(userDatabaseProvider),
    ref.watch(settingsRepositoryProvider),
  ),
);

/// The profile row. Null until the user has changed a setting that creates it.
final userProfileProvider = StreamProvider<UserProfileRow?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchProfile(),
);

/// The safety factor applied to manual burn entries, with its default applied.
final safetyFactorProvider = Provider<double>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  return profile?.activitySafetyFactor ??
      SettingsRepository.defaultSafetyFactor;
});

/// The volume of one water-meter bar, with its default applied.
final waterCupMlProvider = Provider<int>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  return profile?.waterCupMl ?? SettingsRepository.defaultWaterCupMl;
});

/// The most recent recorded body weight, or null if never weighed.
final latestWeightProvider = StreamProvider<double?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchLatestWeightKg(),
);

/// The full weight history, oldest first, for the trend screen.
final weightLogProvider = StreamProvider<List<WeightEntry>>(
  (ref) => ref.watch(settingsRepositoryProvider).watchWeightLog(),
);

/// The target in force today, used by the settings screen. The diary reads the
/// target for the day it is showing instead, via [daySummaryProvider].
final currentTargetProvider = StreamProvider<TargetRow?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchTargetFor(DayKey.today()),
);

/// The day the diary is showing. Defaults to today.
class SelectedDay extends Notifier<DayKey> {
  @override
  DayKey build() => DayKey.today();

  void select(DayKey day) => state = day;

  void goToToday() => state = DayKey.today();

  void shift(int days) => state = state.addDays(days);
}

final selectedDayProvider = NotifierProvider<SelectedDay, DayKey>(
  SelectedDay.new,
);

/// One day's entries and totals, refreshed whenever the day changes.
final daySummaryProvider = StreamProvider.family<DaySummary, DayKey>(
  (ref, day) => ref.watch(diaryRepositoryProvider).watchDay(day),
);

/// The day's activity rows. Separate from [daySummaryProvider], which carries
/// only the totals the budget needs.
final activityEntriesProvider =
    StreamProvider.family<List<ActivityEntry>, DayKey>(
      (ref, day) => ref.watch(diaryRepositoryProvider).watchActivity(day),
    );

/// Distinct recently logged foods, powering the search screen's "Zuletzt" tab.
final recentFoodsProvider = StreamProvider<List<DiaryEntry>>(
  (ref) => ref.watch(diaryRepositoryProvider).watchRecentFoods(),
);

final customFoodRepositoryProvider = Provider<CustomFoodRepository>(
  (ref) => CustomFoodRepository(ref.watch(userDatabaseProvider)),
);

/// The Open Food Facts online API client, for the last link of the barcode
/// chain. A single client for the app session, so its HTTP connection pools.
final offApiClientProvider = Provider<OffApiClient>((ref) {
  final client = OffApiClient();
  ref.onDispose(client.close);
  return client;
});

final offCacheRepositoryProvider = Provider<OffCacheRepository>(
  (ref) => OffCacheRepository(ref.watch(userDatabaseProvider)),
);

/// Resolves a scanned barcode through custom foods → cache → local pack →
/// online. Reads the OFF pack's current value (see [localFoodProvidersProvider])
/// so it is never blocked by the pack still loading.
final barcodeResolverProvider = Provider<BarcodeResolver>((ref) {
  final db = ref.watch(userDatabaseProvider);
  final offPack = switch (ref.watch(offPackProvider)) {
    AsyncData(:final value) => value,
    _ => null,
  };

  return BarcodeResolver(
    custom: CustomFoodProvider(db),
    cache: ref.watch(offCacheRepositoryProvider),
    offApi: ref.watch(offApiClientProvider),
    pack: offPack == null ? null : OffLocalProvider(offPack),
  );
});

final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => RecipeRepository(ref.watch(userDatabaseProvider)),
);

/// The user's recipes with their computed nutrients, for the Rezepte tab.
final recipesProvider = StreamProvider<List<RecipeDetail>>(
  (ref) => ref.watch(recipeRepositoryProvider).watchRecipes(),
);

/// The user's own foods, for the search screen's "Meine" tab.
final myFoodsProvider = StreamProvider<List<FoodItem>>(
  (ref) => ref.watch(customFoodRepositoryProvider).watchMyFoods(),
);

/// The user's favourite *custom* foods (the isFavorite flag). The unified
/// favourites — across every source — are [favoritesProvider].
final favoriteFoodsProvider = StreamProvider<List<FoodItem>>(
  (ref) => ref.watch(customFoodRepositoryProvider).watchFavorites(),
);

final pinnedFoodsRepositoryProvider = Provider<PinnedFoodsRepository>(
  (ref) => PinnedFoodsRepository(ref.watch(userDatabaseProvider)),
);

/// Foods pinned from any source (BLS, OFF, recipe), as bare references.
final pinnedFoodsProvider = StreamProvider<List<PinnedFood>>(
  (ref) => ref.watch(pinnedFoodsRepositoryProvider).watchPinned(),
);

/// Resolves a [FoodRef] back to a full [FoodItem] across all sources.
final foodResolverProvider = FutureProvider<FoodResolver>((ref) async {
  final providers = await ref.watch(localFoodProvidersProvider.future);
  return FoodResolver(
    providers: providers,
    cache: ref.watch(offCacheRepositoryProvider),
  );
});

/// Whether a given food is a favourite, as a cheap set of refs — no resolution.
/// Both mechanisms feed it: a custom food's flag and a pin on anything else.
final favoriteRefsProvider = Provider<Set<FoodRef>>((ref) {
  final custom = ref.watch(favoriteFoodsProvider).value ?? const <FoodItem>[];
  final pins = ref.watch(pinnedFoodsProvider).value ?? const <PinnedFood>[];
  return {
    for (final food in custom) food.ref,
    for (final pin in pins)
      FoodRef(FoodSourceType.fromWire(pin.sourceType), pin.sourceId),
  };
});

/// The unified favourites list for the "Favoriten" tab: custom favourites plus
/// pinned foods from other sources, resolved to full [FoodItem]s. Pins that no
/// longer resolve (an OFF product whose pack was removed) are quietly dropped.
final favoritesProvider = FutureProvider<List<FoodItem>>((ref) async {
  final custom = await ref.watch(favoriteFoodsProvider.future);
  final pins = await ref.watch(pinnedFoodsProvider.future);
  final resolver = await ref.watch(foodResolverProvider.future);

  final byRef = <FoodRef, FoodItem>{for (final food in custom) food.ref: food};
  for (final pin in pins) {
    final ref0 = FoodRef(FoodSourceType.fromWire(pin.sourceType), pin.sourceId);
    if (byRef.containsKey(ref0)) continue;
    final item = await resolver.resolve(ref0);
    if (item != null) byRef[ref0] = item;
  }
  return byRef.values.toList();
});

/// Debounced search results for a query.
final foodSearchProvider = StreamProvider.autoDispose
    .family<SearchState, String>((ref, query) async* {
      if (query.trim().isEmpty) {
        yield SearchState.empty;
        return;
      }

      // Debounce: without this every keystroke starts a query, and the
      // in-flight ones race to paint the list.
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (ref.mounted) {
        final orchestrator = await ref.watch(searchOrchestratorProvider.future);
        yield* orchestrator.search(query);
      }
    });
