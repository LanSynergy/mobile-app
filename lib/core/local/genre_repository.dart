import 'package:drift/drift.dart';

import '../jellyfin/models/items.dart';
import 'app_database.dart';

class GenreRepository {
  GenreRepository(this.db);
  final AppDatabase db;

  // ── Queries ──────────────────────────────────────────────────────────────

  Future<List<AfGenre>> allGenres({int limit = 500}) async {
    final rows = await db
        .customSelect(
          '''
      SELECT genre, COUNT(*) as count, MIN(cover_path) as cover_path
      FROM tracks
      WHERE genre != ''
      GROUP BY genre
      ORDER BY genre COLLATE NOCASE ASC
      LIMIT ?1
      ''',
          variables: [Variable<int>(limit)],
        )
        .get();
    const palette = <String>[
      '#5644C9',
      '#A89DEC',
      '#3FD18C',
      '#FF7A59',
      '#F8C42D',
      '#FF6FB5',
      '#3DB6FF',
      '#FF4D6D',
    ];
    int index = 0;
    final results = <AfGenre>[];
    for (final r in rows) {
      final name = r.read<String?>('genre') ?? '';
      if (name.isEmpty) continue;
      results.add(
        AfGenre(
          name,
          palette[index % palette.length],
          imageUrl: r.read<String?>('cover_path') != null
              ? 'file://${r.read<String>('cover_path')}'
              : null,
        ),
      );
      index++;
    }
    return results;
  }
}
