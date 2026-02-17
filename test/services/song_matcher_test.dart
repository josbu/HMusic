import 'package:flutter_test/flutter_test.dart';
import 'package:hmusic/data/models/online_music_result.dart';
import 'package:hmusic/data/services/song_matcher.dart';

OnlineMusicResult _r({
  required String title,
  required String author,
  String? songId,
  int? duration,
}) {
  return OnlineMusicResult(
    title: title,
    author: author,
    url: '',
    songId: songId ?? '${title}_$author',
    duration: duration,
  );
}

void main() {
  group('SongMatcher', () {
    test('优先选择标题歌手最匹配候选', () {
      final candidates = [
        _r(title: '我已经爱上你 (DJ版)', author: '洛先生'),
        _r(title: '我已经爱上你', author: '洛先生', duration: 278),
        _r(title: '我已经爱上你', author: '其他歌手'),
      ];

      final best = SongMatcher.bestMatch(
        candidates: candidates,
        targetTitle: '我已经爱上你',
        targetArtist: '洛先生',
        targetDuration: 278,
      );

      expect(best, isNotNull);
      expect(best!.title, '我已经爱上你');
      expect(best.author, '洛先生');
    });

    test('无可信匹配时返回 null', () {
      final candidates = [
        _r(title: '完全不相关A', author: '歌手A'),
        _r(title: '完全不相关B', author: '歌手B'),
      ];

      final best = SongMatcher.bestMatch(
        candidates: candidates,
        targetTitle: '我已经爱上你',
        targetArtist: '洛先生',
        targetDuration: 278,
      );

      expect(best, isNull);
    });
  });
}
