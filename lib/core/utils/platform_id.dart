import 'package:flutter/foundation.dart' show mapEquals;

class PlatformId {
  static const tx = 'tx';
  static const kw = 'kw';
  static const wy = 'wy';

  /// Normalize aliases to canonical platform IDs.
  static String normalize(String raw) {
    switch (raw.toLowerCase()) {
      case 'qq':
      case 'tx':
      case 'tencent':
        return tx;
      case 'kuwo':
      case 'kw':
        return kw;
      case 'netease':
      case 'wy':
      case 'wangyi':
      case '163':
        return wy;
      case 'kugou':
      case 'kg':
        return 'kg';
      case 'migu':
      case 'mg':
        return 'mg';
      default:
        return raw.toLowerCase();
    }
  }

  /// Canonical platform to native search key.
  static String toSearchKey(String canonical) {
    switch (normalize(canonical)) {
      case tx:
        return 'qq';
      case kw:
        return 'kuwo';
      case wy:
        return 'netease';
      default:
        return canonical;
    }
  }

  static String toDisplayName(String canonical) {
    switch (normalize(canonical)) {
      case tx:
        return 'QQ音乐';
      case kw:
        return '酷我';
      case wy:
        return '网易云';
      default:
        return canonical;
    }
  }

  /// Default fallback for unknown platforms is [tx, kw, wy].
  static List<String> degradeOrder(String originalPlatform) {
    final norm = normalize(originalPlatform);
    const base = [tx, kw, wy];
    if (!base.contains(norm)) return base;
    return [norm, ...base.where((p) => p != norm)];
  }

  static bool platformSongIdsEqual(
    Map<String, String>? a,
    Map<String, String>? b,
  ) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return mapEquals(a, b);
  }
}
