import '../../core/network/dio_client.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';

class UploadFile {
  final String fieldName;
  final String filePath;

  const UploadFile({required this.fieldName, required this.filePath});
}

class MusicApiService {
  final DioClient _client;

  MusicApiService(this._client);

  Future<Map<String, dynamic>> getVersion() async {
    final response = await _client.get('/getversion');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMusicList() async {
    final response = await _client.get('/musiclist');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCurrentPlaying({String? did}) async {
    final response = await _client.get(
      '/playingmusic',
      queryParameters: did != null ? {'did': did} : null,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getVolume({String? did}) async {
    final response = await _client.get(
      '/getvolume',
      queryParameters: did != null ? {'did': did} : null,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> setVolume({required String did, required int volume}) async {
    await _client.post('/setvolume', data: {'did': did, 'volume': volume});
  }

  // 可选：若服务端支持拖动进度
  Future<void> seek({required String did, required int seconds}) async {
    await _client.post('/seek', data: {'did': did, 'seconds': seconds});
  }

  Future<void> playMusic({
    required String did,
    String? musicName,
    String? searchKey,
  }) async {
    await _client.post(
      '/playmusic',
      data: {
        'did': did,
        'musicname': musicName ?? '',
        'searchkey': searchKey ?? '',
      },
    );
  }

  Future<void> pauseMusic({required String did}) async {
    await _client.post('/cmd', data: {'did': did, 'cmd': '暂停'});
  }

  Future<void> resumeMusic({required String did}) async {
    await _client.post('/cmd', data: {'did': did, 'cmd': '播放歌曲'});
  }

  Future<void> shutdown({required String did}) async {
    await _client.post('/cmd', data: {'did': did, 'cmd': '关机'});
  }

  Future<void> executeCommand({
    required String did,
    required String command,
  }) async {
    await _client.post('/cmd', data: {'did': did, 'cmd': command});
  }

  Future<Map<String, dynamic>> getCommandStatus() async {
    final response = await _client.get('/cmdstatus');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSettings({
    bool needDeviceList = false,
  }) async {
    final response = await _client.get(
      '/getsetting',
      queryParameters: {'need_device_list': needDeviceList},
    );
    return response.data as Map<String, dynamic>;
  }

  // 保存设置接口
  Future<dynamic> saveSetting(Map<String, dynamic> settings) async {
    final response = await _client.post('/savesetting', data: settings);
    return response.data; // 直接返回原始数据，可能是字符串或Map
  }

  // 播放音乐列表接口
  Future<dynamic> playMusicList({
    required String did,
    required String listName,
    required String musicName,
  }) async {
    final response = await _client.post('/playmusiclist', data: {
      'did': did,
      'listname': listName,
      'musicname': musicName,
    });
    return response.data; // 直接返回原始数据，可能是字符串或Map
  }

  // 通过设置在线播放列表来播放音乐
  Future<void> playOnlineMusic({
    required String did,
    required String musicUrl,
    required String musicTitle,
    required String musicAuthor,
  }) async {
    // 第一步：构造音乐列表数据
    final musicListJson = [
      {
        "name": "在线播放",
        "musics": [
          {
            "name": "$musicTitle - $musicAuthor",
            "url": musicUrl,
          }
        ]
      }
    ];

    // 第二步：获取当前设置，然后更新音乐列表
    final currentSettings = await getSettings();
    final updatedSettings = Map<String, dynamic>.from(currentSettings);
    updatedSettings['music_list_json'] = jsonEncode(musicListJson);

    // 第三步：保存设置
    final saveResult = await saveSetting(updatedSettings);
    debugPrint('保存设置结果: $saveResult');

    // 第四步：播放音乐
    final playResult = await playMusicList(
      did: did,
      listName: "在线播放",
      musicName: "$musicTitle - $musicAuthor",
    );
    debugPrint('播放结果: $playResult');
  }

  Future<List<dynamic>> searchMusic(String name) async {
    final response = await _client.get(
      '/searchmusic',
      queryParameters: {'name': name},
    );
    return response.data as List<dynamic>;
  }

  // 第三方在线搜索（txqq.pro 简易代理）
  Future<List<dynamic>> searchOnlineByTxqq({
    required String keyword,
    String sourceType = 'qq',
    int page = 1,
  }) async {
    // 使用后端代理或直接请求第三方服务。这里走直接请求。
    // 关键：为防止无限等待，这里显式设置合理的网络超时。
    final String encodedKw = Uri.encodeQueryComponent(keyword);

    final Dio http = Dio(
      BaseOptions(
        connectTimeout: Duration(seconds: AppConstants.connectTimeout),
        receiveTimeout: Duration(seconds: AppConstants.receiveTimeout),
        sendTimeout: Duration(seconds: AppConstants.sendTimeout),
        // 容忍非 JSON 的 content-type，后续手动解析
        responseType: ResponseType.plain,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Origin': 'https://music.txqq.pro',
          // Referer 中的中文参数必须进行 URL 编码，否则在移动端会触发 Header 格式错误
          'Referer': 'https://music.txqq.pro/?name=$encodedKw&type=$sourceType',
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json, text/javascript, */*; q=0.01',
        },
      ),
    );

    // 日志拦截器：便于在控制台查看完整的请求/响应信息
    http.interceptors.add(
      LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
      ),
    );

    Response resp;
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        resp = await http.post(
          'https://music.txqq.pro/',
          data: 'input=$encodedKw&filter=name&type=$sourceType&page=$page',
        );
        break;
      } catch (e) {
        if (attempts >= 2) rethrow;
      }
    }

    // 统一手动解析
    var body = resp.data;
    if (body is! String) {
      body = body.toString();
    }
    dynamic jsonBody;
    try {
      jsonBody = jsonDecode(body);
    } catch (_) {
      jsonBody = {};
    }

    if (jsonBody is Map && jsonBody['data'] is List) {
      return (jsonBody['data'] as List).cast<dynamic>();
    }
    return const [];
  }

  Future<void> playUrl({required String did, required String url}) async {
    await _client.get('/playurl', queryParameters: {'did': did, 'url': url});
  }

  // 代理播放 - 用于需要代理的链接
  Future<void> playUrlWithProxy({required String did, required String url}) async {
    // 构建完整的代理URL
    final baseUrl = _client.baseUrl;
    final proxyUrl = '$baseUrl/proxy?urlb64=${_encodeUrlToBase64(url)}';
    debugPrint('构建代理URL: $proxyUrl');
    await _client.get('/playurl', queryParameters: {'did': did, 'url': proxyUrl});
  }

  // 智能播放 - 自动判断是否需要代理
  Future<void> playUrlSmart({required String did, required String url}) async {
    if (_needsProxy(url)) {
      debugPrint('使用代理播放: $url');
      await playUrlWithProxy(did: did, url: url);
    } else {
      debugPrint('直接播放: $url');
      await playUrl(did: did, url: url);
    }
  }

  // 判断URL是否需要代理
  bool _needsProxy(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    
    // 需要代理的域名列表
    const proxyDomains = [
      'ws.stream.qqmusic.qq.com',    // QQ音乐
      'music.163.com',               // 网易云音乐  
      'freetyst.nf.migu.cn',         // 咪咕音乐
      'antiserver.kuwo.cn',          // 酷我音乐
      'fs.taihe.com',                // 百度音乐
      // 可以根据需要添加更多需要代理的域名
    ];
    
    return proxyDomains.any((domain) => uri.host.contains(domain));
  }

  // Base64编码URL
  String _encodeUrlToBase64(String url) {
    return base64Encode(utf8.encode(url));
  }

  Future<void> playTts({required String did, required String text}) async {
    await _client.get('/playtts', queryParameters: {'did': did, 'text': text});
  }

  // 预留：本地音乐上传（待确认服务端路径/参数）
  Future<Map<String, dynamic>> uploadMusic({
    required List<({String fieldName, String filePath})> files,
    Map<String, dynamic>? extraFields,
    String endpoint = '/uploadmusic',
  }) async {
    final formData = FormData();
    for (final f in files) {
      formData.files.add(
        MapEntry(f.fieldName, await MultipartFile.fromFile(f.filePath)),
      );
    }
    if (extraFields != null) {
      formData.fields.addAll(
        extraFields.entries.map((e) => MapEntry(e.key, e.value.toString())),
      );
    }
    final resp = await _client.post(endpoint, data: formData);
    return (resp.data as Map).cast<String, dynamic>();
  }

  // 预留：网络音乐下载（待确认服务端路径/参数）
  Future<Map<String, dynamic>> downloadMusicByUrl({
    required String url,
    Map<String, dynamic>? extraFields,
    String endpoint = '/downloadjson',
  }) async {
    final body = {'url': url, ...?extraFields};
    final resp = await _client.post(endpoint, data: body);
    return (resp.data as Map).cast<String, dynamic>();
  }

  // Download raw log/file text from /downloadlog
  Future<String> getDownloadLog() async {
    final resp = await _client.getPlain('/downloadlog');
    return resp.data ?? '';
  }

  // 播放列表相关方法
  Future<dynamic> getPlaylistNames() async {
    // 兼容不同服务端实现：可能返回 List 或 Map
    final response = await _client.get('/playlistnames');
    return response.data;
  }

  Future<Map<String, dynamic>> getPlaylistMusics(String playlistName) async {
    final response = await _client.get(
      '/playlistmusics',
      queryParameters: {'name': playlistName},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> createPlaylist(String name) async {
    await _client.post('/playlistadd', data: {'name': name});
  }

  Future<void> deletePlaylist(String name) async {
    await _client.post('/playlistdel', data: {'name': name});
  }

  Future<void> renamePlaylist({
    required String oldName,
    required String newName,
  }) async {
    await _client.post(
      '/playlistupdatename',
      data: {'oldname': oldName, 'newname': newName},
    );
  }

  Future<void> addMusicToPlaylist({
    required String playlistName,
    required List<String> musicList,
  }) async {
    await _client.post(
      '/playlistaddmusic',
      data: {'name': playlistName, 'music_list': musicList},
    );
  }

  Future<void> removeMusicFromPlaylist({
    required String playlistName,
    required List<String> musicList,
  }) async {
    await _client.post(
      '/playlistdelmusic',
      data: {'name': playlistName, 'music_list': musicList},
    );
  }

  // 音乐库相关方法
  Future<void> deleteMusic(String musicName) async {
    await _client.post('/delmusic', data: {'name': musicName});
  }

  Future<Map<String, dynamic>> getMusicInfo(
    String musicName, {
    bool includeTag = false,
  }) async {
    final response = await _client.get(
      '/musicinfo',
      queryParameters: {'name': musicName, 'musictag': includeTag},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getMusicInfos(
    List<String> musicNames, {
    bool includeTag = false,
  }) async {
    final response = await _client.get(
      '/musicinfos',
      queryParameters: {'name': musicNames, 'musictag': includeTag},
    );
    return response.data as List<dynamic>;
  }

  Future<void> setMusicTag(Map<String, dynamic> musicInfo) async {
    await _client.post('/setmusictag', data: musicInfo);
  }

  // 网络下载：整表
  Future<Map<String, dynamic>> downloadPlaylist({
    required String playlistName,
    String? url,
  }) async {
    final payload = {'dirname': playlistName, if (url != null) 'url': url};
    final resp = await _client.post('/downloadplaylist', data: payload);
    return (resp.data as Map).cast<String, dynamic>();
  }

  // 网络下载：单曲
  Future<Map<String, dynamic>> downloadOneMusic({
    required String musicName,
    String? url,
  }) async {
    final payload = {'name': musicName, if (url != null) 'url': url};
    final resp = await _client.post('/downloadonemusic', data: payload);
    return (resp.data as Map).cast<String, dynamic>();
  }

  // 通用文件上传方法
  Future<Map<String, dynamic>> uploadFiles({
    required String endpoint,
    required List<UploadFile> files,
    Map<String, dynamic>? extraFields,
  }) async {
    final formData = FormData();

    // 添加文件
    for (final f in files) {
      formData.files.add(
        MapEntry(f.fieldName, await MultipartFile.fromFile(f.filePath)),
      );
    }

    // 添加额外字段
    if (extraFields != null) {
      formData.fields.addAll(
        extraFields.entries.map((e) => MapEntry(e.key, e.value.toString())),
      );
    }

    final resp = await _client.post(endpoint, data: formData);
    return (resp.data as Map).cast<String, dynamic>();
  }

  // 上传 ytdlp Cookie 文件供后端下载器使用
  Future<Map<String, dynamic>> uploadYtDlpCookie(String filePath) async {
    return uploadFiles(
      endpoint: '/uploadytdlpcookie',
      files: [UploadFile(fieldName: 'file', filePath: filePath)],
    );
  }
}
