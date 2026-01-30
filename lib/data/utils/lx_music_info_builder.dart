import '../models/online_music_result.dart';
import '../models/playlist_item.dart';
import '../models/local_playlist.dart';

String? _asNonEmptyString(dynamic value) {
  if (value == null) return null;
  if (value is Map || value is List) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _pickString(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = _asNonEmptyString(source[key]);
    if (value != null) return value;
  }
  return null;
}

int? _pickInt(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = _asInt(source[key]);
    if (value != null) return value;
  }
  return null;
}

String? _extractAlbumIdFromCoverUrl(String? coverUrl) {
  if (coverUrl == null || coverUrl.isEmpty) return null;
  final match = RegExp(r'T002R\d+x\d+M000([A-Za-z0-9]+)\.jpg').firstMatch(
    coverUrl,
  );
  return match?.group(1);
}

Map<String, dynamic> _flattenExtra(Map<String, dynamic>? extra) {
  if (extra == null || extra.isEmpty) return <String, dynamic>{};
  final flattened = <String, dynamic>{}..addAll(extra);
  final raw = extra['rawData'];
  if (raw is Map) {
    for (final entry in raw.entries) {
      if (entry.key != null) {
        flattened[entry.key.toString()] = entry.value;
      }
    }
  }
  return flattened;
}

Map<String, dynamic> buildLxMusicInfo({
  required String songId,
  String? title,
  String? artist,
  String? album,
  int? duration,
  String? coverUrl,
  Map<String, dynamic>? extra,
}) {
  final flattened = _flattenExtra(extra);
  final albumIdFromCover = _extractAlbumIdFromCoverUrl(coverUrl);

  final pickedSongMid =
      _pickString(flattened, ['songmid', 'songMid', 'mid']) ?? songId;
  final pickedHash =
      _pickString(flattened, ['hash', 'songId', 'songid']) ?? songId;
  final pickedId =
      _pickString(flattened, ['id', 'songId', 'songid']) ?? songId;
  final pickedStrMediaMid =
      _pickString(flattened, ['strMediaMid', 'mediaMid', 'songmid', 'songMid']) ??
      songId;

  final pickedTitle =
      title ?? _pickString(flattened, ['name', 'title']) ?? '';
  final pickedArtist =
      artist ?? _pickString(flattened, ['singer', 'artist', 'author']) ?? '';
  final pickedAlbum =
      album ?? _pickString(flattened, ['album', 'albumName']) ?? '';

  final pickedAlbumMid =
      _pickString(flattened, ['albumMid', 'albummid', 'album_mid', 'albummid']) ??
      '';
  final pickedAlbumId =
      _pickString(flattened, ['albumId', 'album_id', 'albumid']) ??
      albumIdFromCover ??
      '';

  final pickedDuration =
      duration ?? _pickInt(flattened, ['duration', 'interval', 'time']) ?? 0;

  return {
    'songmid': pickedSongMid,
    'hash': pickedHash,
    'strMediaMid': pickedStrMediaMid,
    'id': pickedId,
    'name': pickedTitle,
    'singer': pickedArtist,
    'album': pickedAlbum,
    'albumMid': pickedAlbumMid,
    'albumId': pickedAlbumId,
    'duration': pickedDuration,
    'interval': pickedDuration,
  };
}

Map<String, dynamic> buildLxMusicInfoFromOnlineResult(OnlineMusicResult result) {
  return buildLxMusicInfo(
    songId: result.songId ?? '',
    title: result.title,
    artist: result.author,
    album: result.album,
    duration: result.duration,
    coverUrl: result.picture,
    extra: result.extra,
  );
}

Map<String, dynamic> buildLxMusicInfoFromPlaylistItem(PlaylistItem item) {
  return buildLxMusicInfo(
    songId: item.songId ?? '',
    title: item.title,
    artist: item.artist,
    album: item.album,
    duration: item.duration,
    coverUrl: item.coverUrl,
  );
}

Map<String, dynamic> buildLxMusicInfoFromLocalPlaylistSong(
  LocalPlaylistSong song,
) {
  return buildLxMusicInfo(
    songId: song.songId ?? '',
    title: song.title,
    artist: song.artist,
    album: null,
    duration: null,
    coverUrl: song.coverUrl,
  );
}
