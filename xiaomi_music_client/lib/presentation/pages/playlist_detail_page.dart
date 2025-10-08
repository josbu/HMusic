import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/playlist_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/device_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_layout.dart';
import '../../data/models/music.dart';

class PlaylistDetailPage extends ConsumerStatefulWidget {
  final String playlistName;
  const PlaylistDetailPage({super.key, required this.playlistName});

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(playlistProvider.notifier)
          .loadPlaylistMusics(widget.playlistName);
    });
  }

  Future<void> _playWholePlaylist() async {
    final did = ref.read(deviceProvider).selectedDeviceId;
    if (did == null) {
      if (mounted) {
        AppSnackBar.showText(context, '请先在设置中配置 NAS 服务器');
      }
      return;
    }
    await ref
        .read(playlistProvider.notifier)
        .playPlaylist(deviceId: did, playlistName: widget.playlistName);
  }

  Future<void> _playSingle(String musicName) async {
    final did = ref.read(deviceProvider).selectedDeviceId;
    if (did == null) {
      if (mounted) {
        AppSnackBar.showText(context, '请先在控制页选择播放设备');
      }
      return;
    }

    // 🎵 获取当前播放列表的歌曲，并转换为 Music 对象列表
    final state = ref.read(playlistProvider);
    final musicNames = state.currentPlaylist == widget.playlistName
        ? state.currentPlaylistMusics
        : <String>[];

    final playlist = musicNames.map((name) => Music(name: name)).toList();

    await ref.read(playbackProvider.notifier).playMusic(
          deviceId: did,
          musicName: musicName,
          playlist: playlist, // 🎵 传递播放列表
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playlistProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final musics =
        state.currentPlaylist == widget.playlistName
            ? state.currentPlaylistMusics
            : <String>[];

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(widget.playlistName),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_fill_rounded),
            onPressed: _playWholePlaylist,
          ),
        ],
      ),
      body:
          state.isLoading && musics.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : musics.isEmpty
              ? Center(
                child: Text(
                  '此列表暂无歌曲',
                  style: TextStyle(color: onSurface.withOpacity(0.6)),
                ),
              )
              : ListView.builder(
                padding: EdgeInsets.only(
                  bottom: AppLayout.contentBottomPadding(context),
                  top: 6,
                ),
                itemCount: musics.length,
                itemBuilder: (context, index) {
                  final musicName = musics[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    dense: true,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                    minLeadingWidth: 0,
                    leading: Icon(
                      Icons.music_note_rounded,
                      size: 18,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                    title: Text(
                      musicName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_arrow_rounded),
                      iconSize: 22,
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: () => _playSingle(musicName),
                    ),
                    onTap: () => _playSingle(musicName),
                  );
                },
              ),
    );
  }
}
