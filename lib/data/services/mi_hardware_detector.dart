/// 小米设备硬件检测工具类
/// 基于 xiaomusic NEED_USE_PLAY_MUSIC_API + miservice _USE_PLAY_MUSIC_API 合并
class MiHardwareDetector {
  /// 必须使用 player_play_music API 的设备硬件列表
  /// 合并来源：
  ///   xiaomusic const.py NEED_USE_PLAY_MUSIC_API
  ///   miservice minaservice.py _USE_PLAY_MUSIC_API
  /// 这些设备使用 player_play_url 会无效或不稳定
  static const List<String> NEED_USE_PLAY_MUSIC_API = [
    // --- 来自 xiaomusic NEED_USE_PLAY_MUSIC_API ---
    'X08C',   // 小爱音箱 Play 增强版 (触屏)
    'X08E',   // 小爱音箱 Play (触屏)
    'X8F',    // 小爱音箱 Pro (触屏)
    'X4B',    // 小爱音箱
    'LX05',   // 小爱音箱 Play (2019款)
    'OH2',    // XIAOMI 智能音箱
    'OH2P',   // XIAOMI 智能音箱 Pro
    'X6A',    // 小爱音箱 Art 电池版
    // --- 来自 miservice _USE_PLAY_MUSIC_API (补充) ---
    'LX04',   // 小爱音箱 (触屏)
    'L05B',   // 小爱音箱 Play
    'L05C',   // 小米小爱音箱 Play 增强版
    'L06',    // 小爱音箱
    'L06A',   // 小爱音箱
    'X08A',   // 小爱音箱 (触屏)
    'X10A',   // 小爱音箱 (触屏)
  ];

  /// 检查设备硬件是否需要使用 player_play_music API
  static bool needsPlayMusicApi(String hardware) {
    if (hardware.isEmpty) return false;

    final upperHardware = hardware.toUpperCase();
    return NEED_USE_PLAY_MUSIC_API.any((need) => upperHardware.contains(need));
  }

  /// 获取设备的推荐播放方式
  static String getRecommendedPlayMethod(String hardware) {
    if (needsPlayMusicApi(hardware)) {
      return 'player_play_music';
    }
    return 'player_play_url';
  }

  /// 获取设备硬件类型描述
  static String getHardwareDescription(String hardware) {
    if (hardware.isEmpty) return '未知设备';

    final upperHardware = hardware.toUpperCase();

    if (upperHardware.contains('X08C')) return '小爱音箱 Play 增强版';
    if (upperHardware.contains('X08E')) return '小爱音箱 Play';
    if (upperHardware.contains('X8F')) return '小爱音箱 Pro';
    if (upperHardware.contains('X4B')) return '小爱音箱';
    if (upperHardware.contains('LX05')) return '小爱音箱 Play (LX05)';
    if (upperHardware.contains('OH2')) return '小爱音箱 HD';
    if (upperHardware.contains('OH2P')) return '小爱音箱 HD Plus';
    if (upperHardware.contains('X6A')) return '小爱音箱 Art 电池版';

    return '小爱音箱';
  }

  /// 检查设备是否支持高级功能
  static bool supportsAdvancedFeatures(String hardware) {
    if (hardware.isEmpty) return false;

    final upperHardware = hardware.toUpperCase();
    // HD系列和Pro系列支持更多功能
    return upperHardware.contains('PRO') ||
           upperHardware.contains('HD') ||
           upperHardware.contains('ART');
  }
}