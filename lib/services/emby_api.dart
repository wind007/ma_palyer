import 'dart:convert';
import 'package:http/http.dart' as http;

class EmbyApiService {
  String baseUrl;
  String username;
  String password;
  String? accessToken;
  String? userId;

  EmbyApiService({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  // 统一的网络请求处理方法
  Future<dynamic> _request({
    required String path,
    required String method,
    Map<String, String>? queryParams,
    dynamic body,
    bool requiresAuth = true,
  }) async {
    try {
      // 如果需要认证且没有token，先进行认证
      if (requiresAuth && accessToken == null) {
        await authenticate();
      }

      final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: queryParams,
      );

      // 准备请求头
      final headers = {
        'Content-Type': 'application/json',
        'X-Emby-Client': 'Emby Flutter',
        'X-Emby-Device-Name': 'Flutter App',
        'X-Emby-Device-Id': 'flutter-app',
        'X-Emby-Client-Version': '1.0.0',
        'X-Emby-Language': 'zh-cn',
      };

      // 如果需要认证，添加token
      if (requiresAuth && accessToken != null) {
        headers['X-Emby-Token'] = accessToken!;
      }

      http.Response response;
      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          );
          break;
        default:
          throw Exception('不支持的请求方法: $method');
      }

      // 处理401状态码，token失效时自动重试
      if (response.statusCode == 401 && requiresAuth) {
        // 清除旧token
        accessToken = null;
        // 重新认证
        await authenticate();
        // 重试请求
        return _request(
          path: path,
          method: method,
          queryParams: queryParams,
          body: body,
          requiresAuth: requiresAuth,
        );
      }

      if (response.statusCode != 200) {
        throw Exception('请求失败: ${response.statusCode}');
      }

      return json.decode(response.body);
    } catch (e) {
      throw Exception('请求失败: $e');
    }
  }

  Future<Map<String, dynamic>> authenticate() async {
    try {
      final authData = await _request(
        path: '/Users/AuthenticateByName',
        method: 'POST',
        requiresAuth: false,
        body: {
          'Username': username,
          'Pw': password,
        },
      );

      accessToken = authData['AccessToken'];
      userId = authData['User']['Id'];
      
      return {
        'accessToken': accessToken,
        'userId': userId,
        'userInfo': authData['User'],
        'serverInfo': authData['Server'] ?? {},
      };
    } catch (e) {
      throw Exception('认证失败: $e');
    }
  }

  // 检查服务器连接状态
  Future<bool> checkServerConnection() async {
    try {
      await _request(
        path: '/System/Info/Public',
        method: 'GET',
        requiresAuth: false,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  // 获取视频播放信息
  Future<Map<String, dynamic>> getPlaybackInfo(String itemId) async {
    return await _request(
      path: '/Items/$itemId/PlaybackInfo',
      method: 'GET',
      queryParams: {
        'UserId': userId!,
        'StartTimeTicks': '0',
        'IsPlayback': 'true',
        'AutoOpenLiveStream': 'true',
        'MaxStreamingBitrate': '140000000',
      },
    );
  }

  // 获取视频播放地址
  Future<String> getPlaybackUrl(String itemId) async {
    final info = await getPlaybackInfo(itemId);
    final mediaSources = info['MediaSources'] as List;
    if (mediaSources.isEmpty) {
      throw Exception('没有可用的播放源');
    }
    
    final mediaSource = mediaSources[0];
    final sourceId = mediaSource['Id'];
    final container = mediaSource['Container'];
    
    // 构建直接流URL
    final streamUrl = '$baseUrl/Videos/$itemId/stream';
    final params = {
      'api_key': accessToken,
      'Static': 'true',
      'MediaSourceId': sourceId,
      'Container': container,
      'AudioCodec': 'aac,mp3,ac3',
      'VideoCodec': 'h264,hevc,h265',
      'SubtitleMethod': 'Embed',
    };
    
    final uri = Uri.parse(streamUrl).replace(queryParameters: params);
    print('最终播放URL: ${uri.toString()}');
    return uri.toString();
  }

  // 获取播放进度
  Future<int> getPlaybackPosition(String itemId) async {
    try {
      final response = await _request(
        path: '/Users/$userId/PlaybackProgress/$itemId',
        method: 'GET',
      );
      return response['PositionTicks'] ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // 更新播放进度
  Future<void> updatePlaybackProgress({
    required String itemId,
    required int positionTicks,
    required bool isPaused,
  }) async {
    try {
      await _request(
        path: '/Sessions/Playing/Progress',
        method: 'POST',
        body: {
          'ItemId': itemId,
          'UserId': userId,
          'PositionTicks': positionTicks,
          'IsPaused': isPaused,
          'PlayMethod': 'DirectStream',
          'RepeatMode': 'RepeatNone',
          'PlaybackRate': 1,
          'VolumeLevel': 100,
          'IsMuted': false,
        },
      );
    } catch (e) {
      print('更新播放进度失败: $e');
    }
  }

  // 停止播放
  Future<void> stopPlayback(String itemId) async {
    try {
      await _request(
        path: '/Sessions/Playing/Stopped',
        method: 'POST',
        body: {
          'ItemId': itemId,
          'UserId': userId,
          'PlayMethod': 'DirectStream',
        },
      );
    } catch (e) {
      print('停止播放失败: $e');
    }
  }

  // 获取视频列表
  Future<Map<String, dynamic>> getVideos({
    required int startIndex,
    required int limit,
    String? parentId,
    String? sortBy = 'SortName',
    String? sortOrder = 'Descending',
    String filters = '',
  }) async {
    final queryParams = {
      'Recursive': 'true',
      'Fields': 'PrimaryImageAspectRatio,Overview',
      'ImageTypeLimit': '1',
      'EnableImageTypes': 'Primary,Backdrop',
      'StartIndex': startIndex.toString(),
      'Limit': limit.toString(),
      'EnableTotalRecordCount': 'true',
      'SortBy': sortBy ?? 'SortName',
    };

    if (sortOrder != null) {
      queryParams['SortOrder'] = sortOrder;
    }

    if (parentId != null) {
      queryParams['ParentId'] = parentId;
    }

    if (filters.isNotEmpty) {
      queryParams.addAll(Uri.splitQueryString(filters));
    }

    return await _request(
      path: '/Users/$userId/Items',
      method: 'GET',
      queryParams: queryParams,
    );
  }

  // 获取视频详情
  Future<Map<String, dynamic>> getVideoDetails(String itemId) async {
    return await _request(
      path: '/Users/$userId/Items/$itemId',
      method: 'GET',
      queryParams: {
        'Fields': 'Overview,Genres,Studios,CommunityRating,CriticRating,People,MediaStreams,MediaSources',
      },
    );
  }

  // 获取最近观看
  Future<List<dynamic>> getResumeItems() async {
    final data = await _request(
      path: '/Users/$userId/Items/Resume',
      method: 'GET',
      queryParams: {
        'Fields': 'PrimaryImageAspectRatio,Overview',
        'ImageTypeLimit': '1',
        'EnableImageTypes': 'Primary',
        'MediaTypes': 'Video',
        'Limit': '10',
      },
    );
    return data['Items'] ?? [];
  }

  // 获取最新添加
  Future<List<dynamic>> getLatestItems() async {
    final data = await _request(
      path: '/Users/$userId/Items/Latest',
      method: 'GET',
    );
    return data is List ? data : [];
  }
}