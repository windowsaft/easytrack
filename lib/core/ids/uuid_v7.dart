import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Generates a UUIDv7 for use as a primary key on user-owned rows.
///
/// v7 over v4 because v7 embeds a millisecond timestamp in its high bits, so
/// keys are monotonically increasing. That gives B-tree index locality on
/// insert (v4 scatters writes across the whole index) and a stable
/// chronological tiebreaker for free.
///
/// The value is also stable across devices, which is what makes a future sync
/// possible without a server round-trip to mint IDs.
String newId() => _uuid.v7();
