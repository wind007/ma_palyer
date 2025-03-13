import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class EmbyApiService {
  String baseUrl;
  String username;
  String password;
  String? accessToken;
  String? userId;
  late http.Client _client;

  EmbyApiService({
    required this.baseUrl,
    required this.username,
    required this.password,
  }) {
    // 创建支持自签名证书的 HTTP 客户端
    final httpClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    _client = IOClient(httpClient);
  }

  // 统一的网络请求处理方法
  Future<dynamic> _request({
    required String path,
    required String method,
    Map<String, String>? queryParams,
    dynamic body,
    bool requiresAuth = true,
    bool allowNoContent = false,  // 添加参数来允许204响应
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: queryParams,
      );
      print('请求路径: ${uri.toString()}');
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
      } else if (requiresAuth && accessToken == null) {
        // 只有在需要认证且没有token时才进行认证
        await authenticate();
        headers['X-Emby-Token'] = accessToken!;
      }

      http.Response response;
      switch (method.toUpperCase()) {
        case 'GET':
          response = await _client.get(uri, headers: headers);
          break;
        case 'POST':
          response = await _client.post(
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
          allowNoContent: allowNoContent,
        );
      }

      // 允许204状态码
      if (response.statusCode == 204 && allowNoContent) {
        return null;
      }

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('请求失败: ${response.statusCode}');
      }

      if (response.body.isEmpty) {
        return null;
      }

      return json.decode(response.body);
    } catch (e) {
      throw Exception('请求失败: $e');
    }
  }

  @override
  void dispose() {
    _client.close();
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

      if (authData == null) {
        throw Exception('服务器返回数据为空');
      }

      if (!authData.containsKey('AccessToken') || !authData.containsKey('User')) {
        throw Exception('服务器返回数据格式错误');
      }

      accessToken = authData['AccessToken'];
      userId = authData['User']['Id'];
      
      return {
        'accessToken': accessToken,
        'userId': userId,
        'userInfo': authData['User'],
        'serverInfo': authData['Server'] ?? {},
      };
    } catch (e) {
      // 清除可能存在的旧数据
      accessToken = null;
      userId = null;
      
      if (e.toString().contains('SocketException')) {
        throw Exception('无法连接到服务器，请检查网络或服务器地址');
      } else if (e.toString().contains('400')) {
        throw Exception('用户名或密码错误');
      } else if (e.toString().contains('404')) {
        throw Exception('服务器地址错误');
      } else if (e.toString().contains('证书')) {
        throw Exception('服务器证书验证失败，请检查服务器配置');
      }
      
      throw Exception('认证失败: ${e.toString()}');
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
        path: '/Users/$userId/Items/$itemId',
        method: 'GET',
        queryParams: {
          'Fields': 'UserData',
        },
      );
      return response['UserData']?['PlaybackPositionTicks'] ?? 0;
    } catch (e) {
      print('获取播放进度失败: $e');
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
        path: '/Users/$userId/PlayingItems/$itemId/Progress',
        method: 'POST',
        body: {
          'ItemId': itemId,
          'MediaSourceId': itemId,
          'PositionTicks': positionTicks,
          'IsPaused': isPaused,
          'IsMuted': false,
          'PlayMethod': 'DirectStream',
          'RepeatMode': 'RepeatNone',
          'PlaybackStartTimeTicks': 0,
          'VolumeLevel': 100,
          'AudioStreamIndex': 1,
          'SubtitleStreamIndex': -1,
          'PlaySessionId': 'flutter-app-${DateTime.now().millisecondsSinceEpoch}',
        },
        allowNoContent: true,
      );
      print('更新播放进度成功: $positionTicks ticks, isPaused: $isPaused');
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
    String fields = 'PrimaryImageAspectRatio,Overview',
    String includeItemTypes= 'Movie,Series',
    String? parentId,
    String? sortBy = 'SortName',
    String? sortOrder = 'Descending',
    String filters = '',

  }) async {
    final queryParams = {
      'Recursive': 'true',
      'IncludeItemTypes': includeItemTypes,
      'Fields': fields,
      'ImageTypeLimit': '1',
      'EnableImageTypes': 'Primary,Backdrop',
      'StartIndex': startIndex.toString(),
      'Limit': limit.toString(),
      'EnableTotalRecordCount': 'true',
      'SortBy': sortBy ?? 'SortName',
      'SortOrder': sortOrder ?? 'Descending',
    };

    if (parentId != null) {
      queryParams['ParentId'] = parentId;
    }

    if (filters.isNotEmpty) {
      queryParams.addAll(Uri.splitQueryString(filters));
    }

    final response = await _request(
      path: '/Users/$userId/Items',
      method: 'GET',
      queryParams: queryParams,
    );

    return response;
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

  // 获取用户视图
  Future<List<dynamic>> getUserViews(dynamic server) async {
    try {
      final response = await _request(
        path: '/Users/${server['userId']}/Views',
        method: 'GET',
      );

      if (response != null && response['Items'] is List) {
        return response['Items'] as List<dynamic>;
      }
      return [];
    } catch (e) {
      print('获取 Views 失败: $e');
      return [];
    }
  }
}