import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/platform_id.dart';
import '../../data/models/local_playlist.dart';
import '../../data/services/song_resolver_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_bottom_sheet.dart';
import '../providers/music_library_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/device_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/local_playlist_provider.dart'; // 🎯 本地歌单Provider
import '../providers/direct_mode_provider.dart'; // 🎯 播放模式Provider
import '../widgets/music_list_item.dart';
import '../widgets/app_layout.dart';
import '../../data/models/music.dart'; // 🎯 Music模型

class MusicLibraryPage extends ConsumerStatefulWidget {
  const MusicLibraryPage({super.key});

  @override
  ConsumerState<MusicLibraryPage> createState() => _MusicLibraryPageState();
}

class _MusicLibraryPageState extends ConsumerState<MusicLibraryPage>
    with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  late AnimationController _refreshController;
  late AnimationController _listAnimationController;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _listAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // 启动列表动画
    _listAnimationController.forward();

    // 🎯 根据播放模式加载对应的数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playbackMode = ref.read(playbackModeProvider);
      final isDirectMode = playbackMode == PlaybackMode.miIoTDirect;

      if (isDirectMode) {
        // 直连模式：加载本地歌单（已在 LocalPlaylistProvider 初始化时自动加载）
        debugPrint('🎯 [MusicLibrary] 直连模式：显示所有歌单音乐');
      } else {
        // xiaomusic 模式：检查音乐库是否需要加载
        _refreshXiaomusicLibraryIfNeeded();
      }

      // 🔧 监听模式切换，确保切换到 xiaomusic 模式时刷新数据
      ref.listenManual(playbackModeProvider, (previous, next) {
        if (previous == PlaybackMode.miIoTDirect &&
            next == PlaybackMode.xiaomusic) {
          debugPrint('🎯 [MusicLibrary] 从直连模式切换到 xiaomusic 模式，刷新音乐库');
          _refreshXiaomusicLibraryIfNeeded();
        }
      });
    });
  }

  /// 如果需要则刷新 xiaomusic 音乐库
  void _refreshXiaomusicLibraryIfNeeded() {
    final libraryState = ref.read(musicLibraryProvider);
    if (libraryState.musicList.isEmpty && !libraryState.isLoading) {
      debugPrint('🎯 [MusicLibrary] xiaomusic 模式：手动触发音乐库加载');
      ref.read(musicLibraryProvider.notifier).refreshLibrary();
    } else {
      debugPrint(
        '🎯 [MusicLibrary] xiaomusic 模式：音乐库已加载 ${libraryState.musicList.length} 首',
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _refreshController.dispose();
    _listAnimationController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(musicLibraryProvider.notifier).filterMusic(query);
    // 重建搜索按钮状态
    setState(() {});
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(musicLibraryProvider.notifier).filterMusic('');
    // 刷新音乐库，显示全部歌曲
    ref.read(musicLibraryProvider.notifier).refreshLibrary();
    setState(() {});
  }

  _DirectModeSongRef? _findDirectModeSongRef(Music music) {
    final visiblePlaylists = ref
        .read(localPlaylistProvider.notifier)
        .getVisiblePlaylists(PlaybackMode.miIoTDirect);

    for (final playlist in visiblePlaylists) {
      for (var index = 0; index < playlist.songs.length; index++) {
        final song = playlist.songs[index];
        final isSameDisplayName = song.displayName == music.name;
        final isSameSong =
            (music.title?.isNotEmpty == true
                ? song.title == music.title
                : true) &&
            (music.artist?.isNotEmpty == true
                ? song.artist == music.artist
                : true);
        if (isSameDisplayName || isSameSong) {
          return _DirectModeSongRef(
            playlistName: playlist.name,
            songIndex: index,
            song: song,
          );
        }
      }
    }

    return null;
  }

  Future<({String? url, int? duration})> _resolveDirectModeSongUrl(
    _DirectModeSongRef songRef,
  ) async {
    final song = songRef.song;

    if (song.localPath != null && song.localPath!.isNotEmpty) {
      return (url: song.localPath, duration: song.duration);
    }

    if (song.isCacheValid) {
      return (url: song.cachedUrl, duration: song.duration);
    }

    final platform = PlatformId.normalize(song.platform ?? PlatformId.tx);
    final songId = song.songId ?? '';
    if (songId.isEmpty) {
      return (url: null, duration: song.duration);
    }

    final resolver = ref.read(songResolverServiceProvider);
    final resolved = await resolver.resolveSong(
      SongResolveRequest(
        title: song.title,
        artist: song.artist,
        coverUrl: song.coverUrl,
        duration: song.duration,
        originalPlatform: platform,
        originalSongId: songId,
        knownPlatformSongIds: song.platformSongIds ?? const {},
        quality: '320k',
      ),
    );

    if (resolved == null) {
      return (url: null, duration: song.duration);
    }

    await ref
        .read(localPlaylistProvider.notifier)
        .updateSongFields(
          playlistName: songRef.playlistName,
          songIndex: songRef.songIndex,
          cachedUrl: resolved.url,
          duration: resolved.duration ?? song.duration,
          platformSongIds: resolved.platformSongIds,
        );

    return (url: resolved.url, duration: resolved.duration ?? song.duration);
  }

  Future<void> _playMusic(Music music, MusicLibraryState libraryState) async {
    final playbackMode = ref.read(playbackModeProvider);
    final isDirectMode = playbackMode == PlaybackMode.miIoTDirect;

    try {
      if (isDirectMode) {
        final directState = ref.read(directModeProvider);
        if (directState is! DirectModeAuthenticated) {
          if (mounted) {
            AppSnackBar.showWarning(context, '请先登录直连模式');
          }
          return;
        }
        if (directState.playbackDeviceType.isEmpty) {
          if (mounted) {
            AppSnackBar.showWarning(context, '请先在控制页选择播放设备');
          }
          return;
        }

        final songRef = _findDirectModeSongRef(music);
        if (songRef == null) {
          if (mounted) {
            AppSnackBar.showError(context, '未找到可播放的直连歌曲信息');
          }
          return;
        }

        final resolved = await _resolveDirectModeSongUrl(songRef);
        final playUrl = resolved.url;
        if (playUrl == null || playUrl.isEmpty) {
          if (mounted) {
            AppSnackBar.showError(context, '无法解析播放链接: ${music.name}');
          }
          return;
        }

        final playlist = libraryState.filteredMusicList.cast<Music>();
        final startIndex = playlist.indexWhere(
          (item) => item.name == music.name,
        );

        await ref
            .read(playbackProvider.notifier)
            .playMusic(
              deviceId: directState.playbackDeviceType,
              musicName: music.name,
              url: playUrl,
              albumCoverUrl: songRef.song.coverUrl,
              playlist: playlist,
              startIndex: startIndex >= 0 ? startIndex : null,
              playlistName:
                  libraryState.searchQuery.isNotEmpty
                      ? '搜索: ${libraryState.searchQuery}'
                      : '曲库',
              duration: resolved.duration,
            );
      } else {
        final selectedDid = ref.read(deviceProvider).selectedDeviceId;
        if (selectedDid == null) {
          if (mounted) {
            AppSnackBar.showWarning(context, '请先在设置中配置 NAS 服务器');
          }
          return;
        }

        final playlist =
            libraryState.searchQuery.isEmpty
                ? libraryState.musicList
                : libraryState.filteredMusicList;

        await ref
            .read(playbackProvider.notifier)
            .playMusic(
              deviceId: selectedDid,
              musicName: music.name,
              playlist: playlist,
              playlistName:
                  libraryState.searchQuery.isNotEmpty
                      ? '搜索: ${libraryState.searchQuery}'
                      : '曲库',
            );
      }

      if (mounted) {
        AppSnackBar.showSuccess(context, '正在播放: ${music.name}');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, '播放失败: $e');
      }
    }
  }

  // NAS 播放以本地为主，设备选择逻辑移除

  void _deleteMusic(String musicName) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('删除音乐'),
            content: const Text('确定要删除该音乐吗？此操作不可撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  ref
                      .read(musicLibraryProvider.notifier)
                      .deleteMusic(musicName);
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('删除'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 检测当前播放模式
    final playbackMode = ref.watch(playbackModeProvider);
    final isDirectMode = playbackMode == PlaybackMode.miIoTDirect;

    // 🎯 根据模式选择数据源
    final libraryState =
        isDirectMode
            ? _buildDirectModeLibraryState() // 直连模式：从本地歌单收集
            : ref.watch(musicLibraryProvider); // xiaomusic 模式：从服务器读取

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      key: const ValueKey('music_library_scaffold'),
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      floatingActionButton:
          libraryState.isSelectionMode &&
                  libraryState.selectedMusicNames.isNotEmpty
              ? _buildFloatingDeleteButton(libraryState)
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: RefreshIndicator(
        key: const ValueKey('music_library_refresh'),
        onRefresh: () async {
          _refreshController.repeat();
          try {
            // 🎯 根据模式刷新不同的数据源
            if (isDirectMode) {
              await ref.read(localPlaylistProvider.notifier).refreshPlaylists();
            } else {
              await ref.read(musicLibraryProvider.notifier).refreshLibrary();
            }
          } finally {
            _refreshController.reset();
          }
        },
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              Transform.translate(
                offset: const Offset(0, -4),
                child: _buildHeader(onSurface),
              ),
              const SizedBox(height: 12),
              _buildStatistics(libraryState, onSurface),
              const SizedBox(height: 8),
              Expanded(child: _buildContent(libraryState)),
            ],
          ),
        ),
      ),
    );
  }

  /// 🎯 直连模式：从所有本地歌单收集歌曲，构建虚拟的 MusicLibraryState
  MusicLibraryState _buildDirectModeLibraryState() {
    final localState = ref.watch(localPlaylistProvider);

    // 从所有歌单中收集歌曲
    final allSongs = <Music>[];
    final seenSongs = <String>{}; // 去重

    for (final playlist in localState.playlists) {
      for (final song in playlist.songs) {
        // 使用歌曲的唯一标识去重（歌名 + 歌手）
        final key = '${song.title}_${song.artist}';
        if (!seenSongs.contains(key)) {
          seenSongs.add(key);
          allSongs.add(
            Music(
              name: song.displayName, // 显示名称（标题 - 歌手）
              title: song.title,
              artist: song.artist,
              picture: song.coverUrl,
            ),
          );
        }
      }
    }

    // 构建虚拟的 MusicLibraryState
    return MusicLibraryState(
      musicList: allSongs,
      filteredMusicList: allSongs, // 初始不过滤
      isLoading: localState.isLoading,
      error: localState.error,
      searchQuery: '',
      isSelectionMode: false,
      selectedMusicNames: const {},
    );
  }

  Widget _buildHeader(Color onSurface) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: TextStyle(color: onSurface),
        decoration: InputDecoration(
          hintText: '搜索本地音乐...',
          hintStyle: TextStyle(color: onSurface.withOpacity(0.5)),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: onSurface.withOpacity(0.6),
          ),
          suffixIcon:
              _searchController.text.isNotEmpty
                  ? IconButton(
                    icon: Icon(
                      Icons.clear_rounded,
                      color: onSurface.withOpacity(0.6),
                    ),
                    onPressed: _clearSearch,
                  )
                  : null,
          filled: true,
          fillColor: onSurface.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.0),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildStatistics(MusicLibraryState libraryState, Color onSurface) {
    if (libraryState.filteredMusicList.isEmpty &&
        libraryState.searchQuery.isEmpty) {
      return const SizedBox.shrink();
    }

    // 选择模式下显示选择状态栏
    if (libraryState.isSelectionMode) {
      return _buildSelectionBar(libraryState, onSurface);
    }

    // 普通模式下显示统计信息
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.music_note_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '${libraryState.filteredMusicList.length} 首',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (libraryState.searchQuery.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              '从 ${libraryState.musicList.length} 首中筛选',
              style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 13),
            ),
          ],

          const Spacer(),

          // 批量选择按钮
          if (libraryState.filteredMusicList.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: onSurface.withOpacity(0.1), width: 1),
              ),
              child: IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.checklist_rounded,
                  color: onSurface.withOpacity(0.7),
                  size: 18,
                ),
                onPressed: () {
                  ref.read(musicLibraryProvider.notifier).toggleSelectionMode();
                },
                tooltip: '批量选择',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(MusicLibraryState libraryState, Color onSurface) {
    final isAllSelected =
        libraryState.selectedMusicNames.length ==
            libraryState.filteredMusicList.length &&
        libraryState.filteredMusicList.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // 全选按钮
          GestureDetector(
            onTap: () {
              if (isAllSelected) {
                ref.read(musicLibraryProvider.notifier).clearSelection();
              } else {
                ref.read(musicLibraryProvider.notifier).selectAllMusic();
              }
            },
            child: Text(
              '全选',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const Spacer(),

          // 选中数量显示
          Text(
            '已选中 ${libraryState.selectedMusicNames.length} 项',
            style: TextStyle(
              color: onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),

          const Spacer(),

          // 关闭按钮
          GestureDetector(
            onTap: () {
              ref.read(musicLibraryProvider.notifier).toggleSelectionMode();
            },
            child: Icon(
              Icons.close,
              color: onSurface.withOpacity(0.7),
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingDeleteButton(MusicLibraryState libraryState) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 120, // 向上移动更多，避免遮挡最后一个选择框
        right: 56, // 调整位置使按钮中心与选择框中心对齐
      ),
      child: FloatingActionButton(
        onPressed: () => _showBatchDeleteDialog(libraryState),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 6,
        heroTag: "delete_fab",
        child: Badge(
          label: Text(
            '${libraryState.selectedMusicNames.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.red.shade800,
          child: const Icon(Icons.delete, size: 24),
        ),
      ),
    );
  }

  Widget _buildContent(MusicLibraryState libraryState) {
    if (libraryState.isLoading) {
      return _buildLoadingIndicator();
    }
    if (libraryState.error != null) {
      return _buildErrorState(libraryState.error!);
    }
    // 🔧 修复：统一使用 filteredMusicList 判断，与 _buildStatistics 保持一致
    // 当 filteredMusicList 为空且无搜索关键词时，显示空状态
    if (libraryState.filteredMusicList.isEmpty &&
        libraryState.searchQuery.isEmpty) {
      return _buildEmptyState();
    }
    if (libraryState.filteredMusicList.isEmpty &&
        libraryState.searchQuery.isNotEmpty) {
      return _buildNoResultsState();
    }
    return _buildMusicList(libraryState.filteredMusicList, libraryState);
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      key: const ValueKey('music_library_loading'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在加载音乐库...', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      key: const ValueKey('music_library_error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 80,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 20),
            Text(
              '加载失败',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(fontSize: 16, color: onSurface.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(musicLibraryProvider.notifier).clearError();
                ref.read(musicLibraryProvider.notifier).refreshLibrary();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      key: const ValueKey('music_library_empty'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 80,
            color: onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 20),
          Text(
            '音乐库为空',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '尚未找到任何音乐文件\n请先添加音乐到您的设备',
            style: TextStyle(fontSize: 16, color: onSurface.withOpacity(0.6)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      key: const ValueKey('music_library_no_results'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 80,
              color: onSurface.withOpacity(0.4),
            ),
            const SizedBox(height: 20),
            Text(
              '没有找到匹配的音乐',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '尝试使用其他关键词搜索',
              style: TextStyle(fontSize: 16, color: onSurface.withOpacity(0.6)),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                ref.read(musicLibraryProvider.notifier).filterMusic('');
                setState(() {});
              },
              icon: const Icon(Icons.clear_all_rounded),
              label: const Text('清除搜索'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicList(
    List<dynamic> musicList,
    MusicLibraryState libraryState,
  ) {
    return FadeTransition(
      key: const ValueKey('music_library_list'),
      opacity: _listAnimationController,
      child: ListView.builder(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: AppLayout.contentBottomPadding(context),
        ),
        itemCount: musicList.length,
        itemBuilder: (context, index) {
          final music = musicList[index];
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.3, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: _listAnimationController,
                curve: Interval(
                  (index / musicList.length) * 0.5,
                  ((index + 1) / musicList.length) * 0.5 + 0.5,
                  curve: Curves.easeOutCubic,
                ),
              ),
            ),
            child: FadeTransition(
              opacity: Tween<double>(begin: 0, end: 1).animate(
                CurvedAnimation(
                  parent: _listAnimationController,
                  curve: Interval(
                    (index / musicList.length) * 0.5,
                    ((index + 1) / musicList.length) * 0.5 + 0.5,
                    curve: Curves.easeOut,
                  ),
                ),
              ),
              child: MusicListItem(
                music: music,
                onTap: () {
                  if (libraryState.isSelectionMode) {
                    ref
                        .read(musicLibraryProvider.notifier)
                        .toggleMusicSelection(music.name);
                  } else {
                    _playMusic(music, libraryState);
                  }
                },
                onPlay: () => _playMusic(music, libraryState),
                trailing:
                    libraryState.isSelectionMode
                        ? _buildSelectionCheckbox(music, libraryState)
                        : _buildMusicItemMenu(music, libraryState),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMusicItemMenu(dynamic music, MusicLibraryState libraryState) {
    return PopupMenuButton<String>(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.more_vert_rounded,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          size: 18,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        switch (value) {
          case 'play':
            _playMusic(music, libraryState);
            break;
          case 'add':
            _showAddToPlaylistDialog(music.name);
            break;
          case 'delete':
            _deleteMusic(music.name);
            break;
          case 'info':
            _showMusicInfo(music, libraryState);
            break;
        }
      },
      itemBuilder:
          (context) => [
            PopupMenuItem(
              value: 'play',
              child: Row(
                children: [
                  Icon(Icons.play_arrow_rounded, color: Colors.green, size: 20),
                  const SizedBox(width: 12),
                  const Text('播放'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'add',
              child: Row(
                children: [
                  Icon(
                    Icons.playlist_add_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Text('添加到...'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'info',
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Text('详细信息'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Text('删除', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
    );
  }

  Widget _buildSelectionCheckbox(
    dynamic music,
    MusicLibraryState libraryState,
  ) {
    final isSelected = libraryState.selectedMusicNames.contains(music.name);
    return Container(
      padding: const EdgeInsets.all(8),
      child: Checkbox(
        value: isSelected,
        onChanged: (value) {
          ref
              .read(musicLibraryProvider.notifier)
              .toggleMusicSelection(music.name);
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  void _showBatchDeleteDialog(MusicLibraryState libraryState) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('批量删除音乐'),
            content: Text(
              '确定要删除选中的 ${libraryState.selectedMusicNames.length} 首音乐吗？\n\n此操作不可撤销。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await ref
                      .read(musicLibraryProvider.notifier)
                      .deleteSelectedMusic();
                  if (mounted) {
                    AppSnackBar.showSuccess(
                      context,
                      '已删除 ${libraryState.selectedMusicNames.length} 首音乐',
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('删除'),
              ),
            ],
          ),
    );
  }

  /// 检查是否为虚拟播放列表
  bool _isVirtualPlaylist(String playlistName) {
    const virtualPlaylists = ['下载', '所有歌曲', '全部', '临时搜索列表', '在线播放', '最近新增'];
    return virtualPlaylists.contains(playlistName);
  }

  /// 显示添加到歌单的对话框
  Future<void> _showAddToPlaylistDialog(String musicName) async {
    if (!mounted) return;

    final playlistState = ref.read(playlistProvider);
    final allPlaylists = playlistState.playlists;

    // 过滤掉虚拟歌单(虚拟列表不能作为目标)
    final availablePlaylists =
        allPlaylists.where((p) => !_isVirtualPlaylist(p.name)).toList();

    if (availablePlaylists.isEmpty) {
      if (mounted) {
        AppSnackBar.showWarning(context, '没有可用的歌单,请先创建一个歌单');
      }
      return;
    }

    final selectedPlaylist = await showAppBottomSheet<String>(
      context: context,
      builder: (context) {
        return AppBottomSheet(
          title: '添加到歌单',
          centerTitle: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availablePlaylists.length,
                  itemBuilder: (context, index) {
                    final playlist = availablePlaylists[index];
                    return ListTile(
                      leading: const Icon(Icons.playlist_play_rounded),
                      title: Text(playlist.name),
                      subtitle:
                          playlist.count != null
                              ? Text('${playlist.count} 首歌曲')
                              : null,
                      onTap: () => Navigator.pop(context, playlist.name),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selectedPlaylist == null || !mounted) return;

    // 添加到歌单
    try {
      await ref
          .read(playlistProvider.notifier)
          .addMusicToPlaylist(
            musicNames: [musicName],
            playlistName: selectedPlaylist,
          );
      if (mounted) {
        AppSnackBar.showSuccess(context, '已添加到 $selectedPlaylist');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, '添加失败: $e');
      }
    }
  }

  /// 获取包含指定歌曲的歌单(从当前已加载的歌单数据中查找)
  List<String> _getPlaylistsContainingMusic(
    String musicName,
    PlaylistState playlistState,
  ) {
    final containingPlaylists = <String>[];

    for (final playlist in playlistState.playlists) {
      // 跳过虚拟歌单,不显示在结果中
      if (_isVirtualPlaylist(playlist.name)) {
        continue;
      }

      // 检查歌单的歌曲列表中是否包含此歌曲
      if (playlist.musicList != null &&
          playlist.musicList!.contains(musicName)) {
        containingPlaylists.add(playlist.name);
      }
    }

    return containingPlaylists;
  }

  void _showMusicInfo(music, MusicLibraryState libraryState) {
    final primary = Theme.of(context).colorScheme.primary;
    final colorScheme = Theme.of(context).colorScheme;
    final ext = music.name.contains('.') ? music.name.split('.').last : '未知';

    // 获取包含此歌曲的歌单
    final playlistState = ref.read(playlistProvider);
    final containingPlaylists = _getPlaylistsContainingMusic(
      music.name,
      playlistState,
    );

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              music.title ?? music.name,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (music.artist != null)
                    Row(
                      children: [
                        Icon(Icons.person_rounded, color: primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            music.artist!,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (music.artist != null) const SizedBox(height: 8),
                  if (music.album != null)
                    Row(
                      children: [
                        Icon(Icons.album_rounded, color: primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            music.album!,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (music.album != null) const SizedBox(height: 8),
                  if (music.duration != null)
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          color: primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            music.duration!,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (music.duration != null) const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.insert_drive_file_rounded,
                        color: primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          music.name,
                          style: TextStyle(color: colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.tag_rounded, color: primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '后缀: $ext',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  // 显示包含此歌曲的歌单
                  if (containingPlaylists.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.playlist_play_rounded,
                          color: primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '所属歌单:',
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children:
                                    containingPlaylists.map((playlistName) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primary.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: primary.withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          playlistName,
                                          style: TextStyle(
                                            color: primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  _playMusic(music, libraryState);
                },
                child: const Text('播放'),
              ),
            ],
          ),
    );
  }
}

class _DirectModeSongRef {
  const _DirectModeSongRef({
    required this.playlistName,
    required this.songIndex,
    required this.song,
  });

  final String playlistName;
  final int songIndex;
  final LocalPlaylistSong song;
}
