import 'dart:async';

import '../../core/nutrition/food_ref.dart';
import 'food_item.dart';
import 'food_provider.dart';

/// How often a food was logged recently, used to boost search ranking.
///
/// Kept as a plain map so the orchestrator never has to join the user database
/// against the reference database — the two are deliberately separate files.
typedef RecencyIndex = Map<FoodRef, int>;

/// A snapshot of an in-progress search.
class SearchState {
  const SearchState({
    required this.results,
    this.localDone = false,
    this.remoteInFlight = false,
    this.error,
  });

  static const empty = SearchState(results: []);

  final List<FoodSearchResult> results;
  final bool localDone;
  final bool remoteInFlight;
  final Object? error;

  bool get isEmpty => results.isEmpty;
}

/// Runs a query across every provider and merges the results into one list.
class FoodSearchOrchestrator {
  FoodSearchOrchestrator({
    required this.local,
    this.remote = const [],
    this.recency = const {},
  });

  /// Sources that answer without a network round-trip.
  final List<FoodProvider> local;

  /// Sources consulted only when local results are thin.
  final List<FoodProvider> remote;

  /// Log counts per food, highest-value ranking signal in a tracker: people eat
  /// the same twenty things. Applied after merging because it lives in the user
  /// database while most results come from the reference pack.
  final RecencyIndex recency;

  /// Below this many local hits, the network is worth consulting.
  static const _remoteThreshold = 5;

  /// Searches local sources, then remote ones only if local came up short.
  ///
  /// Emits local results as soon as they are ready rather than waiting for the
  /// network — typing is the common path and it must never block on a request.
  Stream<SearchState> search(
    String query, {
    int limit = 30,
    bool forceRemote = false,
  }) async* {
    if (query.trim().isEmpty) {
      yield SearchState.empty;
      return;
    }

    final localResults = await _runAll(local, query, limit);
    final merged = _merge(localResults, limit);

    final shouldQueryRemote =
        remote.isNotEmpty && (forceRemote || merged.length < _remoteThreshold);

    yield SearchState(
      results: merged,
      localDone: true,
      remoteInFlight: shouldQueryRemote,
    );

    if (!shouldQueryRemote) return;

    try {
      final remoteResults = await _runAll(remote, query, limit);
      yield SearchState(
        results: _merge([...localResults, ...remoteResults], limit),
        localDone: true,
      );
    } on Object catch (error) {
      // A failed network lookup must not discard the local results already
      // shown; surface it alongside them instead.
      yield SearchState(results: merged, localDone: true, error: error);
    }
  }

  Future<List<_Scored>> _runAll(
    List<FoodProvider> providers,
    String query,
    int limit,
  ) async {
    final batches = await Future.wait([
      for (final provider in providers) _runOne(provider, query, limit),
    ]);
    return [for (final batch in batches) ...batch];
  }

  Future<List<_Scored>> _runOne(
    FoodProvider provider,
    String query,
    int limit,
  ) async {
    try {
      if (!await provider.isAvailable()) return const [];
      final results = await provider.search(query, limit: limit);
      if (results.isEmpty) return const [];

      // Normalize within the provider before weighting: BM25 and the substring
      // rank used for custom foods are on entirely different scales, so raw
      // scores from different providers are meaningless to compare.
      final best = results
          .map((r) => r.rawScore)
          .reduce((a, b) => a > b ? a : b);
      final divisor = best.abs() < 1e-9 ? 1.0 : best;

      return [
        for (final result in results)
          _Scored(result, (result.rawScore / divisor) * provider.sourceWeight),
      ];
    } on Object {
      // One broken provider must not take the whole search down.
      return const [];
    }
  }

  List<FoodSearchResult> _merge(List<_Scored> scored, int limit) {
    final byRef = <FoodRef, _Scored>{};

    for (final entry in scored) {
      final boosted = _Scored(entry.result, _boost(entry));
      final existing = byRef[entry.result.item.ref];
      if (existing == null || boosted.score > existing.score) {
        byRef[entry.result.item.ref] = boosted;
      }
    }

    final merged = byRef.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return [for (final entry in merged.take(limit)) entry.result];
  }

  double _boost(_Scored entry) {
    var score = entry.score;
    final result = entry.result;

    if (result.exactMatch) {
      score *= 1.6;
    } else if (result.prefixMatch) {
      score *= 1.25;
    }

    // Prefer "Vollkornbrot" over "Vollkornbrot mit Sonnenblumenkernen, 500g":
    // the shorter name is usually the generic the user meant.
    final tokens = result.item.name.split(' ').length;
    if (tokens <= 3) score *= 1.1;

    final logged = recency[result.item.ref] ?? 0;
    if (logged > 0) {
      // Saturating, so a food logged 200 times cannot bury everything else.
      score += 0.25 * (logged / (logged + 3));
    }

    return score;
  }
}

class _Scored {
  const _Scored(this.result, this.score);

  final FoodSearchResult result;
  final double score;
}
