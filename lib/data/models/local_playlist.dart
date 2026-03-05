import 'package:json_annotation/json_annotation.dart';
import '../../core/utils/platform_id.dart';

part 'local_playlist.g.dart';

/// 本地播放列表（用于直连模式）
/// 存储在 SharedPreferences 中，使用 JSON 序列化
@JsonSerializable(explicitToJson: true)
class LocalPlaylist {
  final String id; // 播放列表唯一标识
  final String name; // 播放列表名称
  final List<LocalPlaylistSong> songs; // 歌曲列表
  final String? sourcePlatform; // 导入来源平台（tx/kw/wy）
  final String? sourcePlaylistId; // 导入来源歌单ID
  final String? sourceUrl; // 导入来源链接
  final DateTime? importedAt; // 导入时间
  @JsonKey(defaultValue: 'xiaomusic')
  final String modeScope; // 可见范围：xiaomusic/direct/shared
  final DateTime createdAt; // 创建时间
  final DateTime updatedAt; // 更新时间

  const LocalPlaylist({
    required this.id,
    required this.name,
    required this.songs,
    this.sourcePlatform,
    this.sourcePlaylistId,
    this.sourceUrl,
    this.importedAt,
    this.modeScope = 'xiaomusic',
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) =>
      _$LocalPlaylistFromJson(json);

  Map<String, dynamic> toJson() => _$LocalPlaylistToJson(this);

  /// 创建新的播放列表
  factory LocalPlaylist.create({required String name}) {
    final now = DateTime.now();
    return LocalPlaylist(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      songs: [],
      sourcePlatform: null,
      sourcePlaylistId: null,
      sourceUrl: null,
      importedAt: null,
      modeScope: 'xiaomusic',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 复制并更新部分字段
  LocalPlaylist copyWith({
    String? id,
    String? name,
    List<LocalPlaylistSong>? songs,
    String? sourcePlatform,
    String? sourcePlaylistId,
    String? sourceUrl,
    DateTime? importedAt,
    String? modeScope,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LocalPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      songs: songs ?? this.songs,
      sourcePlatform: sourcePlatform ?? this.sourcePlatform,
      sourcePlaylistId: sourcePlaylistId ?? this.sourcePlaylistId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      importedAt: importedAt ?? this.importedAt,
      modeScope: modeScope ?? this.modeScope,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 歌曲数量
  int get count => songs.length;

  @override
  String toString() {
    return 'LocalPlaylist(id: $id, name: $name, count: $count)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LocalPlaylist &&
        other.id == id &&
        other.name == name &&
        other.sourcePlatform == sourcePlatform &&
        other.sourcePlaylistId == sourcePlaylistId &&
        other.sourceUrl == sourceUrl &&
        other.importedAt == importedAt &&
        other.modeScope == modeScope;
  }

  @override
  int get hashCode =>
      Object.hash(
        id,
        name,
        sourcePlatform,
        sourcePlaylistId,
        sourceUrl,
        importedAt,
        modeScope,
      );
}

/// 本地播放列表中的歌曲信息（简化版）
/// 只存储必要信息，避免冗余
@JsonSerializable()
class LocalPlaylistSong {
  final String title; // 歌曲名称
  final String artist; // 艺术家
  final String? platform; // 平台（在线音乐：qq/netease/kuwo等）
  final String? songId; // 歌曲ID（在线音乐）
  final String? localPath; // 本地路径（本地音乐）
  final String? coverUrl; // 封面图URL
  final String? cachedUrl; // 🎯 缓存的播放链接
  final DateTime? urlExpireTime; // 🎯 链接过期时间（6小时有效期）
  final int? duration; // 🎯 歌曲时长（秒），用于进度条显示
  final Map<String, String>? platformSongIds; // 跨平台 songId 映射

  const LocalPlaylistSong({
    required this.title,
    required this.artist,
    this.platform,
    this.songId,
    this.localPath,
    this.coverUrl,
    this.cachedUrl,
    this.urlExpireTime,
    this.duration,
    this.platformSongIds,
  });

  factory LocalPlaylistSong.fromJson(Map<String, dynamic> json) =>
      _$LocalPlaylistSongFromJson(json);

  Map<String, dynamic> toJson() => _$LocalPlaylistSongToJson(this);

  /// 从在线搜索结果创建
  factory LocalPlaylistSong.fromOnlineMusic({
    required String title,
    required String artist,
    required String platform,
    required String songId,
    String? coverUrl,
    int? duration,
  }) {
    return LocalPlaylistSong(
      title: title,
      artist: artist,
      platform: platform,
      songId: songId,
      coverUrl: coverUrl,
      duration: duration,
      platformSongIds: {PlatformId.normalize(platform): songId},
    );
  }

  /// 从本地音乐创建
  factory LocalPlaylistSong.fromLocalMusic({
    required String title,
    required String artist,
    required String localPath,
    String? coverUrl,
  }) {
    return LocalPlaylistSong(
      title: title,
      artist: artist,
      localPath: localPath,
      coverUrl: coverUrl,
    );
  }

  /// 显示名称（歌名 - 歌手）
  /// 智能检测 title 是否已包含 artist，避免重复拼接
  String get displayName {
    if (artist.isEmpty || artist == '未知歌手') return title;
    if (title.endsWith(' - $artist')) return title;
    return '$title - $artist';
  }

  /// 是否为在线音乐
  bool get isOnline => platform != null && songId != null;

  /// 是否为本地音乐
  bool get isLocal => localPath != null;

  /// 🎯 检查缓存的播放链接是否有效
  ///
  /// 双重验证：
  /// 1. 通用：检查 urlExpireTime 是否在当前时间之后
  /// 2. 网易云专项：从 CDN URL 内嵌的 yyyyMMddHHmmss 时间戳提取生成时间，
  ///    确保距生成时间不超过 25 分钟（CDN TTL ~30 分钟，保留 5 分钟余量）。
  ///    这可以修复旧缓存条目使用 6 小时 TTL 导致 URL 实际已过期但仍被判定有效的问题。
  /// 3. QQ专项：wx.music.tc.qq.com/qqmusic 直链短时易失效，强制短 TTL + 基础参数检查。
  bool get isCacheValid {
    if (cachedUrl == null || cachedUrl!.isEmpty) return false;
    if (urlExpireTime == null) return false;
    if (!DateTime.now().isBefore(urlExpireTime!)) return false;

    // 🎯 网易云 CDN 专项检查：提取内嵌时间戳，超过 25 分钟即视为过期
    // 格式: http(s)://mXXX.music.126.net/yyyyMMddHHmmss/...
    final url = cachedUrl!.toLowerCase();
    if (url.contains('music.126.net') || url.contains('ntes.com')) {
      final match = RegExp(r'/(\d{14})/').firstMatch(cachedUrl!);
      if (match != null) {
        try {
          final ts = match.group(1)!;
          final generationTime = DateTime(
            int.parse(ts.substring(0, 4)),
            int.parse(ts.substring(4, 6)),
            int.parse(ts.substring(6, 8)),
            int.parse(ts.substring(8, 10)),
            int.parse(ts.substring(10, 12)),
            int.parse(ts.substring(12, 14)),
          );
          // 距生成时间超过 25 分钟视为过期
          if (DateTime.now().difference(generationTime).inMinutes >= 25) {
            return false;
          }
        } catch (_) {
          // 解析失败，回退到通用 TTL 判断（已在上方通过）
        }
      }
    }

    // QQ CDN 专项检查：
    // 1) 旧版本缓存可能给了 30 分钟 TTL，这里强制把 QQ 缓存窗口压到 2 分钟
    // 2) guid/vkey 缺失或明显异常时，视为无效缓存
    if (url.contains('wx.music.tc.qq.com') ||
        url.contains('qqmusic.qq.com') ||
        url.contains('stream.qqmusic')) {
      final remain = urlExpireTime!.difference(DateTime.now());
      if (remain > const Duration(minutes: 2, seconds: 10)) {
        return false;
      }

      final uri = Uri.tryParse(cachedUrl!);
      if (uri == null) return false;
      final guid = uri.queryParameters['guid'] ?? '';
      final vkey = uri.queryParameters['vkey'] ?? '';
      if (vkey.isEmpty) return false;
      if (guid.isEmpty || !RegExp(r'^\d+$').hasMatch(guid)) {
        return false;
      }
    }

    return true;
  }

  /// 🎯 复制并更新缓存信息
  LocalPlaylistSong copyWith({
    String? title,
    String? artist,
    String? platform,
    String? songId,
    String? localPath,
    String? coverUrl,
    String? cachedUrl,
    DateTime? urlExpireTime,
    int? duration,
    Map<String, String>? platformSongIds,
  }) {
    return LocalPlaylistSong(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      platform: platform ?? this.platform,
      songId: songId ?? this.songId,
      localPath: localPath ?? this.localPath,
      coverUrl: coverUrl ?? this.coverUrl,
      cachedUrl: cachedUrl ?? this.cachedUrl,
      urlExpireTime: urlExpireTime ?? this.urlExpireTime,
      duration: duration ?? this.duration,
      platformSongIds: platformSongIds ?? this.platformSongIds,
    );
  }

  @override
  String toString() {
    return 'LocalPlaylistSong(title: $title, artist: $artist, platform: $platform, songId: $songId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LocalPlaylistSong &&
        other.title == title &&
        other.artist == artist &&
        other.platform == platform &&
        other.songId == songId &&
        other.localPath == localPath &&
        other.cachedUrl == cachedUrl &&
        other.urlExpireTime == urlExpireTime &&
        PlatformId.platformSongIdsEqual(other.platformSongIds, platformSongIds);
  }

  @override
  int get hashCode {
    return Object.hash(
      title,
      artist,
      platform,
      songId,
      localPath,
      cachedUrl,
      urlExpireTime,
      Object.hashAll(
        (platformSongIds?.entries.toList() ??
                const <MapEntry<String, String>>[])
            .map((e) => Object.hash(e.key, e.value)),
      ),
    );
  }
}
