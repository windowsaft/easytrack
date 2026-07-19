import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:easytrack/data/food/food_item.dart';
import 'package:easytrack/data/food/food_provider.dart';
import 'package:easytrack/data/food/search_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Provider stub returning a fixed list, for testing merge and ranking.
class _FakeProvider implements FoodProvider {
  _FakeProvider({
    required this.source,
    required this.sourceWeight,
    required this.items,
    this.requiresNetwork = false,
    this.available = true,
    this.throws = false,
    this.delay = Duration.zero,
  });

  final List<(String id, String name, double score)> items;

  @override
  final FoodSourceType source;
  @override
  final double sourceWeight;
  @override
  final bool requiresNetwork;

  final bool available;
  final bool throws;
  final Duration delay;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<FoodSearchResult>> search(String query, {int limit = 30}) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (throws) throw StateError('provider is broken');

    return [
      for (final (id, name, score) in items)
        FoodSearchResult(
          item: FoodItem(
            ref: FoodRef(source, id),
            name: name,
            nutrients: const Nutrients(
              kcal: 100,
              proteinG: 5,
              carbsG: 10,
              fatG: 2,
            ),
          ),
          rawScore: score,
          exactMatch: name.toLowerCase() == query.toLowerCase(),
        ),
    ];
  }

  @override
  Future<FoodItem?> byBarcode(String barcode) async => null;
  @override
  Future<FoodItem?> byId(String id) async => null;
}

void main() {
  group('merging', () {
    test('combines results from several local providers', () async {
      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Brot', 5), ('b2', 'Brötchen', 3)],
          ),
          _FakeProvider(
            source: FoodSourceType.custom,
            sourceWeight: 1.1,
            items: [('c1', 'Mein Brot', 4)],
          ),
        ],
      );

      final state = await orchestrator.search('brot').last;
      expect(state.results, hasLength(3));
      expect(state.localDone, isTrue);
    });

    test('a broken provider does not take down the search', () async {
      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Brot', 5)],
          ),
          _FakeProvider(
            source: FoodSourceType.custom,
            sourceWeight: 1.1,
            items: const [],
            throws: true,
          ),
        ],
      );

      final state = await orchestrator.search('brot').last;
      expect(state.results, hasLength(1));
      expect(state.results.first.item.name, 'Brot');
    });

    test('an unavailable provider is skipped', () async {
      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.offLocal,
            sourceWeight: 0.85,
            items: [('o1', 'Brot', 9)],
            available: false,
          ),
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Brot', 5)],
          ),
        ],
      );

      final state = await orchestrator.search('brot').last;
      expect(state.results, hasLength(1));
      expect(state.results.first.item.ref.source, FoodSourceType.bls);
    });

    test('an empty query short-circuits', () async {
      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Brot', 5)],
          ),
        ],
      );
      expect((await orchestrator.search('').last).results, isEmpty);
      expect((await orchestrator.search('   ').last).results, isEmpty);
    });
  });

  group('ranking', () {
    test('source weight decides between otherwise equal hits', () async {
      // Same raw score from both providers; the user's own food must win.
      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Haferbrei', 5)],
          ),
          _FakeProvider(
            source: FoodSourceType.custom,
            sourceWeight: 1.1,
            items: [('c1', 'Haferbrei', 5)],
          ),
        ],
      );

      final state = await orchestrator.search('haferbrei').last;
      expect(state.results.first.item.ref.source, FoodSourceType.custom);
    });

    test('raw scores from different providers are normalized first', () async {
      // BM25 and a substring rank live on different scales. Without per-provider
      // normalization the provider with the larger numbers would always win,
      // regardless of relevance.
      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Brot', 0.02)], // tiny scale
          ),
          _FakeProvider(
            source: FoodSourceType.offLocal,
            sourceWeight: 0.85,
            items: [('o1', 'Brotaufstrich', 5000)], // huge scale
          ),
        ],
      );

      final state = await orchestrator.search('brot').last;
      expect(
        state.results.first.item.ref.source,
        FoodSourceType.bls,
        reason: 'the higher source weight should win, not the bigger number',
      );
    });

    test('recently logged foods are boosted', () async {
      const often = FoodRef(FoodSourceType.bls, 'b2');

      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Brot A', 5.0), ('b2', 'Brot B', 4.6)],
          ),
        ],
        recency: {often: 40},
      );

      final state = await orchestrator.search('brot').last;
      expect(
        state.results.first.item.ref,
        often,
        reason:
            'a food eaten 40 times should outrank a marginally better match',
      );
    });

    test('the recency boost saturates and cannot bury relevance', () async {
      const spammed = FoodRef(FoodSourceType.bls, 'b2');

      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Brot', 10.0), ('b2', 'Zwieback', 1.0)],
          ),
        ],
        recency: {spammed: 100000},
      );

      final state = await orchestrator.search('brot').last;
      expect(
        state.results.first.item.name,
        'Brot',
        reason: 'a far better match must still beat a heavily logged one',
      );
    });

    test('the same food from two sources appears once', () async {
      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Brot', 3)],
          ),
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Brot', 5)],
          ),
        ],
      );

      final state = await orchestrator.search('brot').last;
      expect(state.results, hasLength(1));
    });

    test('respects the result limit', () async {
      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [for (var i = 0; i < 50; i++) ('b$i', 'Brot $i', 50.0 - i)],
          ),
        ],
      );

      final state = await orchestrator.search('brot', limit: 10).last;
      expect(state.results, hasLength(10));
    });
  });

  group('online fallback', () {
    test('is skipped when local results suffice', () async {
      final remote = _FakeProvider(
        source: FoodSourceType.offOnline,
        sourceWeight: 0.7,
        requiresNetwork: true,
        items: [('r1', 'Remote Brot', 5)],
      );

      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [for (var i = 0; i < 8; i++) ('b$i', 'Brot $i', 5.0)],
          ),
        ],
        remote: [remote],
      );

      final states = await orchestrator.search('brot').toList();
      expect(states.last.remoteInFlight, isFalse);
      expect(
        states.last.results.any(
          (r) => r.item.ref.source == FoodSourceType.offOnline,
        ),
        isFalse,
      );
    });

    test('runs when local results are thin', () async {
      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Brot', 5)],
          ),
        ],
        remote: [
          _FakeProvider(
            source: FoodSourceType.offOnline,
            sourceWeight: 0.7,
            requiresNetwork: true,
            items: [('r1', 'Remote Brot', 5)],
          ),
        ],
      );

      final states = await orchestrator.search('brot').toList();
      expect(states.first.remoteInFlight, isTrue);
      expect(
        states.last.results.any(
          (r) => r.item.ref.source == FoodSourceType.offOnline,
        ),
        isTrue,
      );
    });

    test('local results are emitted before the network is awaited', () async {
      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Brot', 5)],
          ),
        ],
        remote: [
          _FakeProvider(
            source: FoodSourceType.offOnline,
            sourceWeight: 0.7,
            requiresNetwork: true,
            items: [('r1', 'Remote Brot', 5)],
            delay: const Duration(milliseconds: 300),
          ),
        ],
      );

      final stopwatch = Stopwatch()..start();
      final first = await orchestrator.search('brot').first;
      stopwatch.stop();

      expect(first.results, isNotEmpty);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(250),
        reason: 'typing must never block on a network request',
      );
    });

    test('a network failure keeps the local results', () async {
      final orchestrator = FoodSearchOrchestrator(
        local: [
          _FakeProvider(
            source: FoodSourceType.bls,
            sourceWeight: 1.0,
            items: [('b1', 'Brot', 5)],
          ),
        ],
        remote: [
          _FakeProvider(
            source: FoodSourceType.offOnline,
            sourceWeight: 0.7,
            requiresNetwork: true,
            items: const [],
            throws: true,
          ),
        ],
      );

      final state = await orchestrator.search('brot').last;
      expect(state.results, hasLength(1));
      expect(state.results.first.item.name, 'Brot');
    });

    test(
      'forceRemote consults the network even with enough local hits',
      () async {
        final orchestrator = FoodSearchOrchestrator(
          local: [
            _FakeProvider(
              source: FoodSourceType.bls,
              sourceWeight: 1.0,
              items: [for (var i = 0; i < 10; i++) ('b$i', 'Brot $i', 5.0)],
            ),
          ],
          remote: [
            _FakeProvider(
              source: FoodSourceType.offOnline,
              sourceWeight: 0.7,
              requiresNetwork: true,
              items: [('r1', 'Remote Brot', 5)],
            ),
          ],
        );

        final state = await orchestrator.search('brot', forceRemote: true).last;
        expect(
          state.results.any(
            (r) => r.item.ref.source == FoodSourceType.offOnline,
          ),
          isTrue,
        );
      },
    );
  });
}
