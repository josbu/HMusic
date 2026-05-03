import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/playlist_provider.dart';
import '../providers/local_playlist_provider.dart'; // 🆕 本地播放列表 Provider
import '../providers/device_provider.dart';
import '../providers/direct_mode_provider.dart';
import 'playlist_detail_page.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_bottom_sheet.dart';
import '../providers/auth_provider.dart';
import '../../core/utils/platform_id.dart';
import '../../data/services/playlist_import_service.dart';

class PlaylistPage extends ConsumerStatefulWidget {
  final bool showCreateDialog; // 🎯 新增：是否自动弹出创建对话框

  const PlaylistPage({super.key, this.showCreateDialog = false});

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

enum _PlaylistSourceTab { server, local }

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  _PlaylistSourceTab _selectedSource = _PlaylistSourceTab.server;

  bool get _showLocalPlaylists => _selectedSource == _PlaylistSourceTab.local;

  @override
  void initState() {
    super.initState();
    // 同时预加载两套歌单数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(localPlaylistProvider.notifier).refreshPlaylists();

      final auth = ref.read(authProvider);
      if (auth is AuthAuthenticated) {
        ref.read(playlistProvider.notifier).refreshPlaylists();
      }

      // 🎯 如果需要自动弹出创建对话框
      if (widget.showCreateDialog) {
        // 延迟一点确保页面已经渲染完成
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _showPlaylistActionSheet();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final localState = ref.watch(localPlaylistProvider);
    final serverState = ref.watch(playlistProvider);
    final playbackMode = ref.watch(playbackModeProvider);
    final isDirectMode = playbackMode == PlaybackMode.miIoTDirect;
    final visibleLocalPlaylists = ref
        .read(localPlaylistProvider.notifier)
        .getVisiblePlaylists(playbackMode);
    final showLocalPlaylists = isDirectMode || _showLocalPlaylists;

    final isLoading =
        showLocalPlaylists ? localState.isLoading : serverState.isLoading;
    final error = showLocalPlaylists ? localState.error : serverState.error;
    final playlists =
        showLocalPlaylists ? visibleLocalPlaylists : serverState.playlists;

    return Scaffold(
      key: const ValueKey('playlist_scaffold'),
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false, // 底部由 AppLayout 处理
        child: _buildContent(
          isLoading: isLoading,
          error: error,
          playlists: playlists,
          showLocalPlaylists: showLocalPlaylists,
          isDirectMode: isDirectMode,
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: AppLayout.bottomOverlayHeight(context) + 8,
        ),
        child: FloatingActionButton(
          key: const ValueKey('playlist_fab'),
          onPressed: () => _showPlaylistActionSheet(),
          tooltip: '新建歌单',
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: const Icon(Icons.add_rounded),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildContent({
    required bool isLoading,
    required String? error,
    required List<dynamic> playlists,
    required bool showLocalPlaylists,
    required bool isDirectMode,
  }) {
    if (isDirectMode) {
      return _buildBodyForSource(
        isLoading: isLoading,
        error: error,
        playlists: playlists,
        showLocalPlaylists: true,
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    final currentChild = _buildBodyForSource(
      isLoading: isLoading,
      error: error,
      playlists: playlists,
      showLocalPlaylists: showLocalPlaylists,
    );
    final serverState = ref.watch(playlistProvider);
    final localState = ref.watch(localPlaylistProvider);
    final playbackMode = ref.watch(playbackModeProvider);
    final visibleLocalPlaylists = ref
        .read(localPlaylistProvider.notifier)
        .getVisiblePlaylists(playbackMode);
    final serverChild =
        showLocalPlaylists
            ? _buildBodyForSource(
              isLoading: serverState.isLoading,
              error: serverState.error,
              playlists: serverState.playlists,
              showLocalPlaylists: false,
            )
            : currentChild;
    final localChild =
        showLocalPlaylists
            ? currentChild
            : _buildBodyForSource(
              isLoading: localState.isLoading,
              error: localState.error,
              playlists: visibleLocalPlaylists,
              showLocalPlaylists: true,
            );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
          child: Container(
            height: 40,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.35),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeInOutCubicEmphasized,
                  alignment:
                      _showLocalPlaylists
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colorScheme.primary.withOpacity(0.32),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    _buildSourceSegment(
                      title: '服务端歌单',
                      selected: !_showLocalPlaylists,
                      onTap: () {
                        if (_selectedSource == _PlaylistSourceTab.server) {
                          return;
                        }
                        setState(() {
                          _selectedSource = _PlaylistSourceTab.server;
                        });
                        ref.read(playlistProvider.notifier).refreshPlaylists();
                      },
                    ),
                    _buildSourceSegment(
                      title: '本地元歌单',
                      selected: _showLocalPlaylists,
                      onTap: () {
                        if (_selectedSource == _PlaylistSourceTab.local) return;
                        setState(() {
                          _selectedSource = _PlaylistSourceTab.local;
                        });
                        ref
                            .read(localPlaylistProvider.notifier)
                            .refreshPlaylists();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ClipRect(
            child: Stack(
              children: [
                IgnorePointer(
                  ignoring: _showLocalPlaylists,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubicEmphasized,
                    offset:
                        _showLocalPlaylists
                            ? const Offset(-0.08, 0)
                            : Offset.zero,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeInOut,
                      opacity: _showLocalPlaylists ? 0 : 1,
                      child: serverChild,
                    ),
                  ),
                ),
                IgnorePointer(
                  ignoring: !_showLocalPlaylists,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubicEmphasized,
                    offset:
                        _showLocalPlaylists
                            ? Offset.zero
                            : const Offset(0.08, 0),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeInOut,
                      opacity: _showLocalPlaylists ? 1 : 0,
                      child: localChild,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBodyForSource({
    required bool isLoading,
    required String? error,
    required List<dynamic> playlists,
    required bool showLocalPlaylists,
  }) {
    if (isLoading && playlists.isEmpty) {
      return _buildLoadingIndicator();
    }
    if (error != null) {
      return _buildErrorState(error, showLocalPlaylists);
    }
    if (playlists.isEmpty) {
      return _buildInitialState(showLocalPlaylists);
    }
    return _buildPlaylistsList(playlists, showLocalPlaylists);
  }

  Widget _buildSourceSegment({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color:
                    selected
                        ? colorScheme.primary
                        : colorScheme.onSurface.withOpacity(0.72),
              ),
              child: Text(title),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialState(bool showLocalPlaylists) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      key: const ValueKey('playlist_initial'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.queue_music_rounded,
            size: 80,
            color: onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 20),
          Text(
            '你的歌单',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            showLocalPlaylists ? '点击右下角 + 创建你的第一个本地元歌单' : '在这里创建和管理服务端歌单',
            style: TextStyle(fontSize: 16, color: onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 16),
          if (showLocalPlaylists)
            FilledButton.icon(
              onPressed: _showPlaylistActionSheet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('创建歌单'),
            )
          else
            FilledButton.icon(
              onPressed: () {
                ref.read(playlistProvider.notifier).refreshPlaylists();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新歌单'),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      key: const ValueKey('playlist_loading'),
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildErrorState(String error, bool showLocalPlaylists) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      key: const ValueKey('playlist_error'),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 60,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 20),
            Text(
              '加载列表失败',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(fontSize: 15, color: onSurface.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                if (showLocalPlaylists) {
                  ref.read(localPlaylistProvider.notifier).refreshPlaylists();
                } else {
                  ref.read(playlistProvider.notifier).refreshPlaylists();
                }
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistsList(List<dynamic> playlists, bool showLocalPlaylists) {
    final deletablePlaylists =
        showLocalPlaylists
            ? <String>{}
            : ref.watch(playlistProvider).deletablePlaylists;

    return RefreshIndicator(
      key: const ValueKey('playlist_refresh'),
      onRefresh: () {
        if (showLocalPlaylists) {
          return ref.read(localPlaylistProvider.notifier).refreshPlaylists();
        } else {
          return ref.read(playlistProvider.notifier).refreshPlaylists();
        }
      },
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              AppLayout.contentBottomPadding(context),
            ),
            sliver: SliverList.builder(
              key: const ValueKey('playlist_list'),
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                final String playlistName = playlist.name;
                final int playlistCount =
                    showLocalPlaylists ? playlist.count : (playlist.count ?? 0);
                final bool deletable =
                    showLocalPlaylists
                        ? true
                        : deletablePlaylists.contains(playlistName);

                final isLight =
                    Theme.of(context).brightness == Brightness.light;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 3.0),
                  decoration: BoxDecoration(
                    color:
                        isLight
                            ? Colors.black.withOpacity(0.03)
                            : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          isLight
                              ? Colors.black.withOpacity(0.06)
                              : Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -3,
                    ),
                    minLeadingWidth: 0,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.queue_music_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      playlistName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      _buildPlaylistSubtitle(
                        playlist,
                        playlistCount,
                        showLocalPlaylists,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 服务端歌单支持一键播放
                        if (!showLocalPlaylists)
                          IconButton(
                            icon: const Icon(Icons.play_circle_fill_rounded),
                            color: Theme.of(context).colorScheme.primary,
                            iconSize: 20,
                            tooltip: '播放歌单',
                            onPressed: () async {
                              final did =
                                  ref.read(deviceProvider).selectedDeviceId;
                              if (did == null) {
                                if (mounted) {
                                  AppSnackBar.showWarning(
                                    context,
                                    '请先在设置中配置 NAS 服务器',
                                  );
                                }
                                return;
                              }
                              await ref
                                  .read(playlistProvider.notifier)
                                  .playPlaylist(
                                    deviceId: did,
                                    playlistName: playlistName,
                                  );
                            },
                          ),
                        PopupMenuButton<String>(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          onSelected: (value) async {
                            switch (value) {
                              case 'open':
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder:
                                        (_) => PlaylistDetailPage(
                                          playlistName: playlistName,
                                          isLocalPlaylist: showLocalPlaylists,
                                        ),
                                  ),
                                );
                                break;
                              case 'delete':
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder:
                                      (ctx) => AlertDialog(
                                        title: const Text('删除歌单'),
                                        content: Text(
                                          '确定删除 "$playlistName" 吗？此操作不可撤销。',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed:
                                                () => Navigator.pop(ctx, false),
                                            child: const Text('取消'),
                                          ),
                                          FilledButton(
                                            onPressed:
                                                () => Navigator.pop(ctx, true),
                                            child: const Text('删除'),
                                          ),
                                        ],
                                      ),
                                );
                                if (ok == true) {
                                  try {
                                    if (showLocalPlaylists) {
                                      await ref
                                          .read(localPlaylistProvider.notifier)
                                          .deletePlaylist(playlistName);
                                    } else {
                                      await ref
                                          .read(playlistProvider.notifier)
                                          .deletePlaylist(playlistName);
                                    }
                                    if (mounted) {
                                      AppSnackBar.showSuccess(
                                        context,
                                        '已删除歌单：$playlistName',
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      AppSnackBar.showError(context, '删除失败：$e');
                                    }
                                  }
                                }
                                break;
                            }
                          },
                          itemBuilder:
                              (context) => [
                                const PopupMenuItem(
                                  value: 'open',
                                  child: Text('打开'),
                                ),
                                if (deletable)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除歌单'),
                                  ),
                              ],
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => PlaylistDetailPage(
                                playlistName: playlistName,
                                isLocalPlaylist: showLocalPlaylists,
                              ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _buildPlaylistSubtitle(dynamic playlist, int count, bool isLocal) {
    final countText = '$count首歌曲';
    if (!isLocal) return countText;

    final sourcePlatform = playlist.sourcePlatform?.toString();
    if (sourcePlatform == null || sourcePlatform.isEmpty) return countText;
    return '$countText · 来自 ${PlatformId.toDisplayName(sourcePlatform)}';
  }

  Future<void> _showPlaylistActionSheet() async {
    final action = await showAppBottomSheet<String>(
      context: context,
      builder: (context) => AppBottomSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.note_add_rounded),
                title: const Text('新建空歌单'),
                subtitle: const Text('手动创建空歌单'),
                onTap: () => Navigator.pop(context, 'create'),
              ),
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('导入外部歌单'),
                subtitle: const Text('粘贴 QQ/酷我/网易云链接'),
                onTap: () => Navigator.pop(context, 'import'),
              ),
            ],
          ),
        ),
      ),
    );

    if (action == 'create') {
      _showCreatePlaylistDialog();
      return;
    }
    if (action == 'import') {
      await _showImportBottomSheet();
    }
  }

  Future<void> _showImportBottomSheet() async {
    final controller = TextEditingController();
    final playbackMode = ref.read(playbackModeProvider);
    final modeScope =
        playbackMode == PlaybackMode.miIoTDirect ? 'direct' : 'xiaomusic';

    final result = await showAppBottomSheet<ImportResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final importService = ref.read(playlistImportServiceProvider);
        ImportStage? stage;
        bool importing = false;
        CancelToken? cancelToken;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> startImport() async {
              if (importing) return;
              final text = controller.text.trim();
              if (text.isEmpty) return;

              setSheetState(() => importing = true);
              cancelToken = CancelToken();

              final importResult = await importService.importFromUrl(
                text,
                modeScope: modeScope,
                cancelToken: cancelToken,
                onInfo: (message) {
                  if (context.mounted) {
                    AppSnackBar.showInfo(context, message);
                  }
                },
                onStageChanged: (s) {
                  if (context.mounted) {
                    setSheetState(() => stage = s);
                  }
                },
                onNeedLargePlaylistConfirm: (summary) async {
                  if (!context.mounted) return false;
                  return await showDialog<bool>(
                        context: context,
                        builder: (ctx) {
                          return AlertDialog(
                            title: const Text('歌单过大'),
                            content: Text(
                              '该歌单共 ${summary.totalCount} 首，仅支持导入前 500 首，是否继续？',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('继续'),
                              ),
                            ],
                          );
                        },
                      ) ??
                      false;
                },
                onImportedConflict: (summary) async {
                  if (!context.mounted) return ImportAction.cancel;
                  return await showDialog<ImportAction>(
                        context: context,
                        builder: (ctx) {
                          return AlertDialog(
                            title: const Text('歌单已导入'),
                            content: Text(
                              '该歌单已导入为「${summary.existingPlaylistName ?? summary.name}」，请选择操作。',
                            ),
                            actions: [
                              TextButton(
                                onPressed:
                                    () =>
                                        Navigator.pop(ctx, ImportAction.cancel),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed:
                                    () => Navigator.pop(
                                      ctx,
                                      ImportAction.mergeUpdate,
                                    ),
                                child: const Text('增量更新'),
                              ),
                              FilledButton(
                                onPressed:
                                    () => Navigator.pop(
                                      ctx,
                                      ImportAction.reimport,
                                    ),
                                child: const Text('重新导入'),
                              ),
                            ],
                          );
                        },
                      ) ??
                      ImportAction.cancel;
                },
              );

              if (context.mounted) {
                Navigator.pop(context, importResult);
              }
            }

            String stageText() {
              switch (stage) {
                case ImportStage.identifying:
                  return '正在识别平台...';
                case ImportStage.resolving:
                  return '正在解析链接...';
                case ImportStage.fetching:
                  return '正在获取歌曲列表...';
                case ImportStage.cleaning:
                  return '正在整理歌曲...';
                case ImportStage.saving:
                  return '正在写入本地...';
                default:
                  return '';
              }
            }

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: AppBottomSheet(
                title: '导入外部歌单',
                centerTitle: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!importing)
                      TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: '粘贴歌单链接或分享文案...',
                          border: OutlineInputBorder(),
                        ),
                      )
                    else ...[
                      const SizedBox(height: 8),
                      Text(stageText(), textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              if (importing) {
                                cancelToken?.cancel('user_cancelled');
                              }
                              Navigator.pop(context);
                            },
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: importing ? null : startImport,
                            child:
                                importing
                                    ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Text('导入'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ),
            );
          },
        );
      },
    );

    if (result == null) return;

    if (!result.success) {
      if (result.error != ImportError.cancelled && mounted) {
        AppSnackBar.showError(context, _importErrorText(result.error));
      }
      return;
    }

    if (mounted) {
      setState(() {
        _selectedSource = _PlaylistSourceTab.local;
      });
      await ref.read(localPlaylistProvider.notifier).refreshPlaylists();
      AppSnackBar.showSuccess(context, _buildImportSuccessText(result));
    }
  }

  String _importErrorText(ImportError? error) {
    switch (error) {
      case ImportError.invalidUrl:
        return '不支持的链接格式，请粘贴 QQ音乐/酷我/网易云的歌单链接';
      case ImportError.unsupportedPlatform:
        return '暂不支持该平台';
      case ImportError.playlistNotFound:
        return '歌单不存在或已被删除';
      case ImportError.alreadyImported:
        return '该歌单已导入';
      case ImportError.fetchFailed:
        return '解析失败，请检查网络后重试';
      case ImportError.cancelled:
        return '已取消导入';
      default:
        return '导入失败，请重试';
    }
  }

  String _buildImportSuccessText(ImportResult result) {
    final name = result.playlistName ?? '歌单';
    final sb = StringBuffer('已导入「$name」，共 ${result.importedCount} 首');

    if (result.mergedCount > 0) {
      sb
        ..clear()
        ..write('已更新「$name」，新增 ${result.mergedCount} 首');
    }

    if ((result.truncatedCount ?? 0) > 0) {
      sb.write('（原歌单 ${result.totalCount} 首，截断 ${result.truncatedCount} 首）');
    }

    final duplicate = result.skippedReasons[SkipReason.duplicate] ?? 0;
    final emptyTitle = result.skippedReasons[SkipReason.emptyTitle] ?? 0;
    final skipped = duplicate + emptyTitle;
    if (skipped > 0) {
      sb.write('，跳过 $skipped 首');
      final parts = <String>[];
      if (duplicate > 0) parts.add('重复 $duplicate');
      if (emptyTitle > 0) parts.add('无标题 $emptyTitle');
      if (parts.isNotEmpty) sb.write('（${parts.join('，')}）');
    }

    return sb.toString();
  }

  void _showCreatePlaylistDialog() {
    final controller = TextEditingController();
    bool _requestedFocus = false;

    final playbackMode = ref.read(playbackModeProvider);
    final isDirectMode = playbackMode == PlaybackMode.miIoTDirect;
    final showLocalPlaylists = isDirectMode || _showLocalPlaylists;
    final modeScope =
        playbackMode == PlaybackMode.miIoTDirect ? 'direct' : 'xiaomusic';

    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      builder: (context) {
        final onSurface = Theme.of(context).colorScheme.onSurface;
        final focusNode = FocusNode();
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final canCreate = controller.text.trim().isNotEmpty;
            // 延后聚焦，避免与底部面板动画同时触发造成卡顿
            if (!_requestedFocus) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await Future.delayed(const Duration(milliseconds: 180));
                if (focusNode.canRequestFocus) {
                  FocusScope.of(context).requestFocus(focusNode);
                }
              });
              _requestedFocus = true;
            }

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: AppBottomSheet(
                title: '新建歌单',
                centerTitle: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: false,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: InputDecoration(
                        labelText: '歌单名称',
                        hintText: '例如：我的最爱',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: onSurface.withOpacity(0.1),
                          ),
                        ),
                        filled: true,
                        fillColor: onSurface.withOpacity(0.04),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                !canCreate
                                    ? null
                                    : () async {
                                      final name = controller.text.trim();
                                      try {
                                        if (showLocalPlaylists) {
                                          await ref
                                              .read(
                                                localPlaylistProvider.notifier,
                                              )
                                              .createPlaylist(
                                                name,
                                                modeScope: modeScope,
                                              );
                                        } else {
                                          await ref
                                              .read(playlistProvider.notifier)
                                              .createPlaylist(name);
                                        }
                                        if (mounted) Navigator.pop(context);
                                        if (mounted) {
                                          AppSnackBar.showSuccess(
                                            context,
                                            '"$name" 已创建',
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) Navigator.pop(context);
                                        if (mounted) {
                                          AppSnackBar.showError(
                                            context,
                                            '创建失败: $e',
                                          );
                                        }
                                      }
                                    },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('创建'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ),
            );
          },
        );
      },
    );
  }
}
