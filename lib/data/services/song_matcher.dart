import '../models/online_music_result.dart';

class SongMatcher {
  static const double _trustThreshold = 40;

  static OnlineMusicResult? bestMatch({
    required List<OnlineMusicResult> candidates,
    required String targetTitle,
    required String targetArtist,
    int? targetDuration,
  }) {
    if (candidates.isEmpty) return null;

    final normalizedTitle = _normalize(targetTitle);
    final normalizedArtist = _normalize(targetArtist);

    OnlineMusicResult? best;
    double bestScore = -1;

    for (final c in candidates.take(5)) {
      final titleScore = _similarity(normalizedTitle, _normalize(c.title));
      final artistScore = _similarity(normalizedArtist, _normalize(c.author));

      double score = 0;
      score += titleScore * 60;
      score += artistScore * 30;

      if (targetDuration != null && targetDuration > 0 && c.duration != null) {
        final diff = (targetDuration - c.duration!).abs();
        if (diff <= 5) {
          score += 10;
        } else if (diff <= 15) {
          score += 5;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }

    if (bestScore < _trustThreshold) {
      return null;
    }
    return best;
  }

  static String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[·•\-\(\)\[\]【】（）]'), '');
  }

  static double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    if (a.contains(b) || b.contains(a)) return 0.85;

    final aBigrams = _toBigrams(a);
    final bBigrams = _toBigrams(b);
    if (aBigrams.isEmpty || bBigrams.isEmpty) return 0;

    final inter = aBigrams.intersection(bBigrams).length;
    final union = aBigrams.union(bBigrams).length;
    if (union == 0) return 0;
    return inter / union;
  }

  static Set<String> _toBigrams(String s) {
    if (s.length < 2) return {s};
    final set = <String>{};
    for (int i = 0; i < s.length - 1; i++) {
      set.add(s.substring(i, i + 2));
    }
    return set;
  }
}
