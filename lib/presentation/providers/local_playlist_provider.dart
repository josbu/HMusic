import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/platform_id.dart';
import '../../data/models/local_playlist.dart';
import '../../data/models/local_playlist_model.dart';
import 'direct_mode_provider.dart';

/// 本地播放列表状态
class LocalPlaylistState {
  final List<LocalPlaylist> playlists;
  final bool isLoading;
  final String? error;

  const LocalPlaylistState({
    this.playlists = const [],
    this.isLoading = false,
    this.error,
  });

  LocalPlaylistState copyWith({
    List<LocalPlaylist>? playlists,
    bool? isLoading,
    String? error,
  }) {
    return LocalPlaylistState(
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 本地播放列表管理器（用于本地元歌单）
/// SharedPreferences 存储优化：歌单元数据 + 每个歌单歌曲分 key
class LocalPlaylistNotifier extends StateNotifier<LocalPlaylistState> {
  LocalPlaylistNotifier() : super(const LocalPlaylistState()) {
    _init();
  }

  static const String _legacyCacheKey = 'local_playlists_cache';
  static const String _legacyDirectModeKey = 'direct_mode_playlists';
  static const String _migrationDoneKey = 'playlist_migration_done';

  static const String _metaKey = 'local_playlists_meta';
  static const String _songsKeyPrefix = 'local_playlist_songs_';

  Future<void>? _writeLock;

  Future<void> _init() async {
    await loadPlaylists();
  }

  Future<T> _serialWrite<T>(Future<T> Function() action) async {
    while (_writeLock != null) {
      await _writeLock;
    }

    final completer = Completer<void>();
    _writeLock = completer.future;
    try {
      return await action();
    } finally {
      _writeLock = null;
      completer.complete();
    }
  }

  Future<void> loadPlaylists() async {
    try {
      state = state.copyWith(isLoading: true);

      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacyIfNeeded(prefs);

      final metaJson = prefs.getString(_metaKey);
      if (metaJson == null || metaJson.isEmpty) {
        state = state.copyWith(playlists: [], isLoading: false, error: null);
        return;
      }

      final List<dynamic> metaList = jsonDecode(metaJson) as List<dynamic>;
      final playlists = <LocalPlaylist>[];

      for (final entry in metaList) {
        final meta = Map<String, dynamic>.from(entry as Map);
        final playlistId = (meta['id'] ?? '').toString();
        if (playlistId.isEmpty) continue;

        final songsJson = prefs.getString('$_songsKeyPrefix$playlistId');
        final songs = <LocalPlaylistSong>[];
        if (songsJson != null && songsJson.isNotEmpty) {
          final List<dynamic> rawSongs = jsonDecode(songsJson) as List<dynamic>;
          songs.addAll(
            rawSongs.map(
              (s) => _normalizeSong(
                LocalPlaylistSong.fromJson(Map<String, dynamic>.from(s as Map)),
              ),
            ),
          );
        }

        final playlist = LocalPlaylist(
          id: playlistId,
          name: (meta['name'] ?? '').toString(),
          songs: songs,
          sourcePlatform: _normalizeNullablePlatform(
            meta['sourcePlatform']?.toString(),
          ),
          sourcePlaylistId: meta['sourcePlaylistId']?.toString(),
          sourceUrl: meta['sourceUrl']?.toString(),
          importedAt: _parseDate(meta['importedAt']),
          modeScope: _normalizeModeScope(meta['modeScope']?.toString()),
          createdAt: _parseDate(meta['createdAt']) ?? DateTime.now(),
          updatedAt: _parseDate(meta['updatedAt']) ?? DateTime.now(),
        );
        playlists.add(playlist);
      }

      state = state.copyWith(
        playlists: playlists,
        isLoading: false,
        error: null,
      );
      debugPrint('✅ [LocalPlaylist] 加载了 ${playlists.length} 个播放列表');
    } catch (e) {
      debugPrint('❌ [LocalPlaylist] 加载播放列表失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refreshPlaylists() async {
    await loadPlaylists();
  }

  Future<void> _savePlaylists(List<LocalPlaylist> playlists) async {
    final prefs = await SharedPreferences.getInstance();

    final meta =
        playlists
            .map(
              (p) => {
                'id': p.id,
                'name': p.name,
                'sourcePlatform': p.sourcePlatform,
                'sourcePlaylistId': p.sourcePlaylistId,
                'sourceUrl': p.sourceUrl,
                'importedAt': p.importedAt?.toIso8601String(),
                'modeScope': p.modeScope,
                'createdAt': p.createdAt.toIso8601String(),
                'updatedAt': p.updatedAt.toIso8601String(),
              },
            )
            .toList();

    await prefs.setString(_metaKey, jsonEncode(meta));

    for (final playlist in playlists) {
      final songsJson = jsonEncode(
        playlist.songs.map((s) => s.toJson()).toList(),
      );
      await prefs.setString('$_songsKeyPrefix${playlist.id}', songsJson);
    }

    final allKeys = prefs.getKeys();
    final activeSongKeys =
        playlists.map((p) => '$_songsKeyPrefix${p.id}').toSet();
    for (final key in allKeys) {
      if (key.startsWith(_songsKeyPrefix) && !activeSongKeys.contains(key)) {
        await prefs.remove(key);
      }
    }

    final totalJson = jsonEncode(playlists.map((p) => p.toJson()).toList());
    final totalBytes = utf8.encode(totalJson).length;
    debugPrint(
      '💾 [LocalPlaylist] 已保存 ${playlists.length} 个播放列表，约 ${totalBytes} bytes',
    );
  }

  Future<void> createPlaylist(String name, {String modeScope = 'xiaomusic'}) {
    return _serialWrite(() async {
      final scope = _normalizeModeScope(modeScope);
      final exists = state.playlists.any(
        (p) => p.name == name && _normalizeModeScope(p.modeScope) == scope,
      );
      if (exists) {
        throw Exception('播放列表"$name"已存在');
      }

      final now = DateTime.now();
      final newPlaylist = LocalPlaylist(
        id: now.millisecondsSinceEpoch.toString(),
        name: name,
        songs: const [],
        modeScope: scope,
        createdAt: now,
        updatedAt: now,
      );

      final updated = [...state.playlists, newPlaylist];
      state = state.copyWith(playlists: updated, isLoading: false, error: null);
      await _savePlaylists(updated);
    });
  }

  Future<void> deletePlaylist(String playlistName, {String? modeScope}) {
    return _serialWrite(() async {
      final scope = modeScope == null ? null : _normalizeModeScope(modeScope);
      final updated =
          state.playlists.where((p) {
            final nameMatch = p.name == playlistName;
            if (!nameMatch) return true;
            if (scope == null) return false;
            return p.modeScope != scope;
          }).toList();

      state = state.copyWith(playlists: updated, isLoading: false, error: null);
      await _savePlaylists(updated);
    });
  }

  Future<void> addMusicToPlaylist({
    required String playlistName,
    required List<LocalPlaylistSong> songs,
  }) {
    return _serialWrite(() async {
      final index = state.playlists.indexWhere((p) => p.name == playlistName);
      if (index == -1) {
        throw Exception('播放列表"$playlistName"不存在');
      }

      final playlist = state.playlists[index];
      final updatedSongs = [...playlist.songs];

      for (final song in songs) {
        final normalized = _normalizeSong(song);
        final exists = updatedSongs.any(
          (s) =>
              s.title == normalized.title &&
              s.artist == normalized.artist &&
              PlatformId.normalize(s.platform ?? '') ==
                  PlatformId.normalize(normalized.platform ?? '') &&
              s.songId == normalized.songId,
        );
        if (!exists) {
          updatedSongs.add(normalized);
        }
      }

      final updatedPlaylist = playlist.copyWith(
        songs: updatedSongs,
        updatedAt: DateTime.now(),
      );

      final updated = [...state.playlists];
      updated[index] = updatedPlaylist;
      state = state.copyWith(playlists: updated, isLoading: false, error: null);
      await _savePlaylists(updated);
    });
  }

  Future<int> mergePlaylistSongs({
    required String playlistName,
    required List<LocalPlaylistSong> newSongs,
  }) {
    return _serialWrite(() async {
      final index = state.playlists.indexWhere((p) => p.name == playlistName);
      if (index == -1) {
        throw Exception('播放列表"$playlistName"不存在');
      }

      final playlist = state.playlists[index];
      final updatedSongs = [...playlist.songs];
      int added = 0;

      for (final song in newSongs.map(_normalizeSong)) {
        final exists = updatedSongs.any(
          (s) =>
              PlatformId.normalize(s.platform ?? '') ==
                  PlatformId.normalize(song.platform ?? '') &&
              s.songId == song.songId,
        );
        if (!exists) {
          updatedSongs.add(song);
          added++;
        }
      }

      final updatedPlaylist = playlist.copyWith(
        songs: updatedSongs,
        updatedAt: DateTime.now(),
      );
      final updated = [...state.playlists];
      updated[index] = updatedPlaylist;
      state = state.copyWith(playlists: updated);
      await _savePlaylists(updated);

      return added;
    });
  }

  Future<void> removeMusicFromPlaylist({
    required String playlistName,
    required List<int> songIndices,
  }) {
    return _serialWrite(() async {
      final index = state.playlists.indexWhere((p) => p.name == playlistName);
      if (index == -1) {
        throw Exception('播放列表"$playlistName"不存在');
      }

      final playlist = state.playlists[index];
      final songs = [...playlist.songs];
      final sorted = songIndices.toList()..sort((a, b) => b.compareTo(a));
      for (final songIndex in sorted) {
        if (songIndex >= 0 && songIndex < songs.length) {
          songs.removeAt(songIndex);
        }
      }

      final updatedPlaylist = playlist.copyWith(
        songs: songs,
        updatedAt: DateTime.now(),
      );

      final updated = [...state.playlists];
      updated[index] = updatedPlaylist;
      state = state.copyWith(playlists: updated, isLoading: false, error: null);
      await _savePlaylists(updated);
    });
  }

  List<LocalPlaylistSong> getPlaylistSongs(String playlistName) {
    try {
      final playlist = state.playlists.firstWhere(
        (p) => p.name == playlistName,
      );
      return playlist.songs;
    } catch (e) {
      debugPrint('❌ [LocalPlaylist] 获取播放列表歌曲失败: $e');
      return [];
    }
  }

  List<LocalPlaylist> getVisiblePlaylists(PlaybackMode mode) {
    final allowed =
        mode == PlaybackMode.xiaomusic
            ? const ['xiaomusic']
            : const ['direct'];
    return state.playlists
        .where((p) => allowed.contains(_normalizeModeScope(p.modeScope)))
        .toList();
  }

  String? isPlaylistImported(
    String modeScope,
    String sourcePlatform,
    String sourcePlaylistId,
  ) {
    final scope = _normalizeModeScope(modeScope);
    final platform = PlatformId.normalize(sourcePlatform);
    try {
      final playlist = state.playlists.firstWhere(
        (p) =>
            p.modeScope == scope &&
            PlatformId.normalize(p.sourcePlatform ?? '') == platform &&
            p.sourcePlaylistId == sourcePlaylistId,
      );
      return playlist.name;
    } catch (_) {
      return null;
    }
  }

  String _deduplicateName(String name, String modeScope) {
    final scope = _normalizeModeScope(modeScope);
    final names =
        state.playlists
            .where((p) => _normalizeModeScope(p.modeScope) == scope)
            .map((p) => p.name)
            .toSet();

    if (!names.contains(name)) return name;
    for (int i = 2; i <= 99; i++) {
      final candidate = '$name ($i)';
      if (!names.contains(candidate)) return candidate;
    }
    return '$name (${DateTime.now().millisecondsSinceEpoch})';
  }

  Future<void> importPlaylist({
    required String name,
    required String sourcePlatform,
    required String sourcePlaylistId,
    String? sourceUrl,
    DateTime? importedAt,
    required List<LocalPlaylistSong> songs,
    String modeScope = 'xiaomusic',
  }) {
    return _serialWrite(() async {
      final scope = _normalizeModeScope(modeScope);
      final now = DateTime.now();
      final deduped = _deduplicateName(name, scope);

      final normalizedSongs = songs.map(_normalizeSong).toList();
      final playlist = LocalPlaylist(
        id: now.millisecondsSinceEpoch.toString(),
        name: deduped,
        songs: normalizedSongs,
        sourcePlatform: PlatformId.normalize(sourcePlatform),
        sourcePlaylistId: sourcePlaylistId,
        sourceUrl: sourceUrl,
        importedAt: importedAt ?? now,
        modeScope: scope,
        createdAt: now,
        updatedAt: now,
      );

      final updated = [...state.playlists, playlist];
      state = state.copyWith(playlists: updated, isLoading: false, error: null);
      await _savePlaylists(updated);
    });
  }

  Future<void> updateSongFields({
    required String playlistName,
    required int songIndex,
    String? cachedUrl,
    DateTime? urlExpireTime,
    int? duration,
    Map<String, String>? platformSongIds,
  }) {
    return _serialWrite(() async {
      final playlistIndex = state.playlists.indexWhere(
        (p) => p.name == playlistName,
      );
      if (playlistIndex == -1) {
        throw Exception('播放列表"$playlistName"不存在');
      }

      final playlist = state.playlists[playlistIndex];
      if (songIndex < 0 || songIndex >= playlist.songs.length) {
        throw Exception('歌曲索引越界: $songIndex');
      }

      final song = playlist.songs[songIndex];
      Map<String, String>? mergedIds = song.platformSongIds;
      if (platformSongIds != null) {
        mergedIds = {
          ...?song.platformSongIds,
          ...platformSongIds.map(
            (key, value) => MapEntry(PlatformId.normalize(key), value),
          ),
        };
      }

      final updatedSong = song.copyWith(
        cachedUrl: cachedUrl ?? song.cachedUrl,
        urlExpireTime:
            urlExpireTime ??
            (cachedUrl != null
                ? _calculateUrlExpireTime(cachedUrl)
                : song.urlExpireTime),
        duration: duration ?? song.duration,
        platformSongIds: mergedIds,
      );

      final updatedSongs = [...playlist.songs];
      updatedSongs[songIndex] = updatedSong;

      final updatedPlaylist = playlist.copyWith(
        songs: updatedSongs,
        updatedAt: DateTime.now(),
      );

      final updated = [...state.playlists];
      updated[playlistIndex] = updatedPlaylist;
      state = state.copyWith(playlists: updated);
      await _savePlaylists(updated);
    });
  }

  Future<void> updateSongCache({
    required String playlistName,
    required int songIndex,
    required String cachedUrl,
  }) {
    return updateSongFields(
      playlistName: playlistName,
      songIndex: songIndex,
      cachedUrl: cachedUrl,
    );
  }

  Future<void> updateSongDuration({
    required String playlistName,
    required int songIndex,
    required int duration,
  }) {
    return updateSongFields(
      playlistName: playlistName,
      songIndex: songIndex,
      duration: duration,
    );
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<void> _migrateLegacyIfNeeded(SharedPreferences prefs) async {
    if (prefs.getBool(_migrationDoneKey) == true) {
      return;
    }

    final migrated = <LocalPlaylist>[];

    final legacyJson = prefs.getString(_legacyCacheKey);
    if (legacyJson != null && legacyJson.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(legacyJson) as List<dynamic>;
        for (final item in list) {
          final playlist = LocalPlaylist.fromJson(
            Map<String, dynamic>.from(item as Map),
          );
          migrated.add(
            playlist.copyWith(
              modeScope: _normalizeModeScope(playlist.modeScope),
              sourcePlatform: _normalizeNullablePlatform(
                playlist.sourcePlatform,
              ),
              sourceUrl: playlist.sourceUrl,
              importedAt: playlist.importedAt,
              songs: playlist.songs.map(_normalizeSong).toList(),
            ),
          );
        }
      } catch (e) {
        debugPrint('⚠️ [LocalPlaylist] 旧 local_playlists_cache 迁移失败: $e');
      }
    }

    final legacyDirectJson = prefs.getString(_legacyDirectModeKey);
    if (legacyDirectJson != null && legacyDirectJson.isNotEmpty) {
      try {
        final List<dynamic> list =
            jsonDecode(legacyDirectJson) as List<dynamic>;
        for (final item in list) {
          final model = LocalPlaylistModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          );
          final songs =
              model.songs.map((name) => _fromLegacySongName(name)).toList();
          migrated.add(
            LocalPlaylist(
              id: model.id,
              name: model.name,
              songs: songs,
              sourcePlatform: null,
              sourcePlaylistId: null,
              sourceUrl: null,
              importedAt: null,
              modeScope: 'direct',
              createdAt: model.createdAt,
              updatedAt: model.updatedAt,
            ),
          );
        }
      } catch (e) {
        debugPrint('⚠️ [LocalPlaylist] 旧 direct_mode_playlists 迁移失败: $e');
      }
    }

    if (migrated.isNotEmpty) {
      final merged = <String, LocalPlaylist>{};
      for (final playlist in migrated) {
        final key = '${playlist.modeScope}:${playlist.id}:${playlist.name}';
        merged[key] = playlist;
      }
      final result = merged.values.toList();
      await _savePlaylists(result);
      state = state.copyWith(playlists: result);
      debugPrint('✅ [LocalPlaylist] 旧数据迁移完成，共 ${result.length} 个歌单');
    }

    await prefs.setBool(_migrationDoneKey, true);
    await prefs.remove(_legacyCacheKey);
    await prefs.remove(_legacyDirectModeKey);
  }

  LocalPlaylistSong _normalizeSong(LocalPlaylistSong song) {
    final normalizedPlatform = _normalizeNullablePlatform(song.platform);
    Map<String, String>? normalizedIds;
    if (song.platformSongIds != null) {
      normalizedIds = {
        for (final e in song.platformSongIds!.entries)
          PlatformId.normalize(e.key): e.value,
      };
    }

    if (normalizedPlatform != null &&
        song.songId != null &&
        song.songId!.isNotEmpty) {
      normalizedIds ??= <String, String>{};
      normalizedIds.putIfAbsent(normalizedPlatform, () => song.songId!);
    }

    return song.copyWith(
      platform: normalizedPlatform,
      platformSongIds: normalizedIds,
    );
  }

  LocalPlaylistSong _fromLegacySongName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const LocalPlaylistSong(title: '未知歌曲', artist: '未知歌手');
    }

    final parts = trimmed.split(' - ');
    if (parts.length >= 2) {
      return LocalPlaylistSong(
        title: parts.first.trim(),
        artist: parts.sublist(1).join(' - ').trim(),
      );
    }

    return LocalPlaylistSong(title: trimmed, artist: '未知歌手');
  }

  String _normalizeModeScope(String? scope) {
    switch ((scope ?? 'xiaomusic').toLowerCase()) {
      case 'direct':
      case 'shared':
      case 'xiaomusic':
        return (scope ?? 'xiaomusic').toLowerCase();
      default:
        return 'xiaomusic';
    }
  }

  String? _normalizeNullablePlatform(String? platform) {
    if (platform == null || platform.trim().isEmpty) return null;
    return PlatformId.normalize(platform);
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  /// 🎯 根据 CDN URL 智能计算过期时间
  ///
  /// 网易云 CDN URL 格式: http://m702.music.126.net/yyyyMMddHHmmss/...
  /// 其中嵌入了 URL 生成时间戳，CDN TTL 约为 30 分钟。
  /// 本方法提取该时间戳，设置为「生成时间 + 25 分钟」（预留 5 分钟余量）。
  ///
  /// 其他 CDN（QQ 音乐、酷狗等）无法提取生成时间，使用保守的 30 分钟 TTL。
  static DateTime _calculateUrlExpireTime(String url) {
    // 尝试从网易云 CDN URL 中提取时间戳（格式：yyyyMMddHHmmss）
    // 例: http://m702.music.126.net/20260301194652/eb/7ae6/...
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('music.126.net') || lowerUrl.contains('ntes.com')) {
      final pattern = RegExp(r'/(\d{14})/');
      final match = pattern.firstMatch(url);
      if (match != null) {
        try {
          final ts = match.group(1)!;
          final year = int.parse(ts.substring(0, 4));
          final month = int.parse(ts.substring(4, 6));
          final day = int.parse(ts.substring(6, 8));
          final hour = int.parse(ts.substring(8, 10));
          final minute = int.parse(ts.substring(10, 12));
          final second = int.parse(ts.substring(12, 14));
          final generationTime = DateTime(year, month, day, hour, minute, second);

          // CDN TTL ~30 分钟，提前 5 分钟过期，有效窗口 = 25 分钟
          final expireTime = generationTime.add(const Duration(minutes: 25));

          if (expireTime.isBefore(DateTime.now())) {
            // 生成时间戳已超过 25 分钟，URL 视为立即过期
            debugPrint('⏰ [LocalPlaylist] 网易云 URL 已超过 25 分钟，立即标记过期: $ts');
            return DateTime.now().subtract(const Duration(seconds: 1));
          }

          debugPrint('⏰ [LocalPlaylist] 网易云 URL 过期时间: $expireTime（生成时间: $ts）');
          return expireTime;
        } catch (e) {
          debugPrint('⚠️ [LocalPlaylist] 解析网易云 URL 时间戳失败: $e');
        }
      }
    }

    // 其他 CDN：保守使用 30 分钟 TTL
    return DateTime.now().add(const Duration(minutes: 30));
  }
}

final localPlaylistProvider =
    StateNotifierProvider<LocalPlaylistNotifier, LocalPlaylistState>((ref) {
      return LocalPlaylistNotifier();
    });
