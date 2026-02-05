import 'package:json_annotation/json_annotation.dart';

part 'playlist_item.g.dart';

/// 统一的播放列表项模型
/// 支持本地音乐、在线音乐、服务器音乐
///
/// 核心设计理念：
/// - 不保存临时的播放URL（会失效），而是保存平台和ID用于重新获取
/// - 缓存封面图URL和歌词内容，避免重复请求
@JsonSerializable()
class PlaylistItem {
  // 🎵 基础信息
  final String title; // 歌曲名（显示用）
  final String artist; // 艺术家
  final String? album; // 专辑名
  final int duration; // 时长（秒）

  // 🎯 核心标识（用于重新获取播放链接）
  final String sourceType; // 来源类型: 'local', 'online', 'server'
  final String? platform; // 平台: 'qq', 'kw', 'wy', 'kg', 'mg', 'youtube'
  final String? songId; // 音乐ID（在线音乐必填）

  // 🖼️ 可缓存内容
  final String? coverUrl; // 封面图URL（可以缓存很久）
  final String? lrc; // 歌词内容（LRC格式，可以缓存）

  // 📁 本地音乐特有
  final String? localPath; // 本地文件路径

  PlaylistItem({
    required this.title,
    required this.artist,
    this.album,
    required this.duration,
    required this.sourceType,
    this.platform,
    this.songId,
    this.coverUrl,
    this.lrc,
    this.localPath,
  });

  factory PlaylistItem.fromJson(Map<String, dynamic> json) =>
      _$PlaylistItemFromJson(json);

  Map<String, dynamic> toJson() => _$PlaylistItemToJson(this);

  /// 从在线音乐结果创建
  factory PlaylistItem.fromOnlineMusic({
    required String title,
    required String artist,
    String? album,
    int duration = 0,
    String? platform,
    String? songId,
    String? coverUrl,
  }) {
    return PlaylistItem(
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      sourceType: 'online',
      platform: platform,
      songId: songId,
      coverUrl: coverUrl,
      lrc: null, // 歌词稍后获取
      localPath: null,
    );
  }

  /// 从本地音乐创建
  factory PlaylistItem.fromLocalMusic({
    required String title,
    required String artist,
    String? album,
    int duration = 0,
    required String localPath,
    String? coverUrl,
  }) {
    return PlaylistItem(
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      sourceType: 'local',
      platform: null,
      songId: null,
      coverUrl: coverUrl,
      lrc: null,
      localPath: localPath,
    );
  }

  /// 从服务器音乐创建（xiaomusic 模式）
  factory PlaylistItem.fromServerMusic({
    required String title,
    required String artist,
    String? album,
    int duration = 0,
    String? coverUrl,
  }) {
    return PlaylistItem(
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      sourceType: 'server',
      platform: null,
      songId: null,
      coverUrl: coverUrl,
      lrc: null,
      localPath: null,
    );
  }

  /// 从 Music 对象创建（音乐库/歌单，xiaomusic 模式）
  ///
  /// Music.name 通常是 "歌名 - 歌手" 格式，本方法会智能解析
  static PlaylistItem fromMusic(dynamic music) {
    // 获取字段（兼容 Music 对象和 Map）
    final String name;
    final String? title;
    final String? artist;
    final String? album;
    final String? duration;
    final String? picture;

    if (music is Map) {
      name = music['name']?.toString() ?? '';
      title = music['title']?.toString();
      artist = music['artist']?.toString();
      album = music['album']?.toString();
      duration = music['duration']?.toString();
      picture = music['picture']?.toString();
    } else {
      // 假设是 Music 对象
      name = music.name ?? '';
      title = music.title;
      artist = music.artist;
      album = music.album;
      duration = music.duration;
      picture = music.picture;
    }

    // 智能解析 name 字段（格式：歌名 - 歌手）
    String parsedTitle = title ?? '';
    String parsedArtist = artist ?? '';

    if (parsedTitle.isEmpty || parsedArtist.isEmpty) {
      // 尝试从 name 解析
      final parts = name.split(' - ');
      if (parts.length >= 2) {
        if (parsedTitle.isEmpty) parsedTitle = parts[0].trim();
        if (parsedArtist.isEmpty) parsedArtist = parts.sublist(1).join(' - ').trim();
      } else if (parts.length == 1) {
        if (parsedTitle.isEmpty) parsedTitle = parts[0].trim();
        if (parsedArtist.isEmpty) parsedArtist = '未知歌手';
      }
    }

    // 确保 title 不为空
    if (parsedTitle.isEmpty) {
      parsedTitle = name.isNotEmpty ? name : '未知歌曲';
    }
    if (parsedArtist.isEmpty) {
      parsedArtist = '未知歌手';
    }

    // 解析 duration（字符串转整数）
    int parsedDuration = 0;
    if (duration != null && duration.isNotEmpty) {
      parsedDuration = int.tryParse(duration) ?? 0;
    }

    return PlaylistItem(
      title: parsedTitle,
      artist: parsedArtist,
      album: album,
      duration: parsedDuration,
      sourceType: 'server', // 来自 xiaomusic 服务器
      platform: null,
      songId: null, // 服务器音乐没有 songId
      coverUrl: picture,
      lrc: null,
      localPath: null,
    );
  }

  /// 复制并更新部分字段
  PlaylistItem copyWith({
    String? title,
    String? artist,
    String? album,
    int? duration,
    String? sourceType,
    String? platform,
    String? songId,
    String? coverUrl,
    String? lrc,
    String? localPath,
  }) {
    return PlaylistItem(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      sourceType: sourceType ?? this.sourceType,
      platform: platform ?? this.platform,
      songId: songId ?? this.songId,
      coverUrl: coverUrl ?? this.coverUrl,
      lrc: lrc ?? this.lrc,
      localPath: localPath ?? this.localPath,
    );
  }

  /// 获取显示名称（格式：歌名 - 歌手）
  String get displayName => '$title - $artist';

  /// 是否为本地音乐
  bool get isLocal => sourceType == 'local';

  /// 是否为在线音乐
  bool get isOnline => sourceType == 'online';

  /// 是否为服务器音乐
  bool get isServer => sourceType == 'server';

  @override
  String toString() {
    return 'PlaylistItem(title: $title, artist: $artist, sourceType: $sourceType, platform: $platform, songId: $songId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PlaylistItem &&
        other.title == title &&
        other.artist == artist &&
        other.sourceType == sourceType &&
        other.platform == platform &&
        other.songId == songId &&
        other.localPath == localPath;
  }

  @override
  int get hashCode {
    return Object.hash(
      title,
      artist,
      sourceType,
      platform,
      songId,
      localPath,
    );
  }
}
