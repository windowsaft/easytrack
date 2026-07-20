import 'package:drift/drift.dart';

import '../../core/nutrition/food_ref.dart';
import '../db/user_database.dart';
import '../food/food_item.dart';

/// Favourites that span any source.
///
/// A custom food is favourited with its own `isFavorite` flag (see
/// [CustomFoodRepository]); everything else — BLS generics, OFF products,
/// recipes — is pinned here by reference. The row is a lightweight pointer
/// `(sourceType, sourceId)` plus a name snapshot; the nutrients are resolved on
/// demand, so a pin never goes stale when the underlying food is corrected or a
/// pack is replaced.
class PinnedFoodsRepository {
  PinnedFoodsRepository(this._db);

  final UserDatabase _db;

  /// The pinned references, newest first. Resolving them to full foods is the
  /// caller's job (see the favorites provider).
  Stream<List<PinnedFood>> watchPinned() =>
      (_db.select(_db.pinnedFoods)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.createdAt,
                mode: OrderingMode.desc,
              ),
            ]))
          .watch();

  Future<bool> isPinned(FoodRef ref) async {
    final row = await _activeRow(ref);
    return row != null;
  }

  /// Pins [food], reviving a previously unpinned row rather than inserting a
  /// duplicate — the `(sourceType, sourceId)` unique index covers tombstones, so
  /// re-pinning must reuse the existing row.
  Future<void> pin(FoodItem food) async {
    final existing = await _anyRow(food.ref);
    if (existing != null) {
      await (_db.update(
        _db.pinnedFoods,
      )..where((t) => t.id.equals(existing.id))).write(
        PinnedFoodsCompanion(
          deletedAt: const Value(null),
          nameSnapshot: Value(food.name),
        ),
      );
      return;
    }

    await _db
        .into(_db.pinnedFoods)
        .insert(
          PinnedFoodsCompanion.insert(
            sourceType: food.ref.source.wireName,
            sourceId: food.ref.id,
            nameSnapshot: food.name,
          ),
        );
  }

  Future<void> unpin(FoodRef ref) async {
    await (_db.update(_db.pinnedFoods)..where(
          (t) =>
              t.sourceType.equals(ref.source.wireName) &
              t.sourceId.equals(ref.id) &
              t.deletedAt.isNull(),
        ))
        .write(PinnedFoodsCompanion(deletedAt: Value(DateTime.now())));
  }

  Future<void> toggle(FoodItem food) async {
    if (await isPinned(food.ref)) {
      await unpin(food.ref);
    } else {
      await pin(food);
    }
  }

  /// The active (non-tombstoned) row for [ref], if any.
  Future<PinnedFood?> _activeRow(FoodRef ref) =>
      (_db.select(_db.pinnedFoods)
            ..where(
              (t) =>
                  t.sourceType.equals(ref.source.wireName) &
                  t.sourceId.equals(ref.id) &
                  t.deletedAt.isNull(),
            )
            ..limit(1))
          .getSingleOrNull();

  /// Any row for [ref], tombstoned or not — used to revive on re-pin.
  Future<PinnedFood?> _anyRow(FoodRef ref) =>
      (_db.select(_db.pinnedFoods)
            ..where(
              (t) =>
                  t.sourceType.equals(ref.source.wireName) &
                  t.sourceId.equals(ref.id),
            )
            ..limit(1))
          .getSingleOrNull();
}
