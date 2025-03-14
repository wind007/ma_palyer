import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../services/server_manager.dart';
import '../utils/logger.dart';

class EmbyApiService {
  static const String _tag = "EmbyApi";
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
    bool allowNoContent = false,
  }) async {
    try {
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

      // 如果需要认证且有token，添加token
      if (requiresAuth && accessToken != null) {
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
        case 'DELETE':
          response = await _client.delete(
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
    Logger.d('最终播放URL: ${uri.toString()}', _tag);
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
      Logger.e('获取播放进度失败', _tag, e);
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
      Logger.i('更新播放进度成功: $positionTicks ticks, isPaused: $isPaused', _tag);
    } catch (e) {
      Logger.e('更新播放进度失败', _tag, e);
      rethrow;
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
      Logger.e('停止播放失败', _tag, e);
      rethrow;
    }
  }

  // 获取视频列表
  Future<Map<String, dynamic>> getVideos({
    required int startIndex,
    required int limit,
    String fields = 'PrimaryImageAspectRatio,Overview',
    String includeItemTypes = 'Movie,Series',
    String imageTypes = 'Primary,Backdrop',
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
      'EnableImages': 'true',
      'EnableImageTypes': imageTypes,
      'EnableUserData': 'true',
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
        'EnableImages': 'true',
        'EnableImageTypes': 'Primary',
        'EnableUserData': 'true',
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
      queryParams: {
        'Limit': '20',
        'EnableImages': 'true',
        'EnableImageTypes': 'Primary',
        'ImageTypeLimit': '1',
        'EnableUserData': 'true',
        'Fields': 'PrimaryImageAspectRatio,Overview',
      },
    );
    return data is List ? data : [];
  }

  // 获取用户视图
  Future<List<dynamic>> getUserViews(ServerInfo server) async {
    try {
      userId ??= server.userId;
      
      final response = await _request(
        path: '/Users/$userId/Views',
        method: 'GET',
        queryParams: {
          'EnableImages': 'true',
          'EnableImageTypes': 'Primary,Backdrop',
          'ImageTypeLimit': '1',
          'EnableUserData': 'true',
          'Fields': 'PrimaryImageAspectRatio,Overview',
        },
      );

      if (response != null && response['Items'] is List) {
        return response['Items'] as List<dynamic>;
      }
      return [];
    } catch (e) {
      Logger.e('获取 Views 失败', _tag, e);
      rethrow;
    }
  }

  String getImageUrl({
    required String itemId,
    required String imageType,
    int? width,
    int? height,
    int? quality,
    String? tag,
  }) {
    final params = <String, String>{
      'X-Emby-Token': accessToken!,
    };

    if (width != null) params['Width'] = width.toString();
    if (height != null) params['Height'] = height.toString();
    if (quality != null) params['Quality'] = quality.toString();
    if (tag != null) params['Tag'] = tag;

    final uri = Uri.parse('$baseUrl/Items/$itemId/Images/$imageType')
        .replace(queryParameters: params);
    return uri.toString();
  }

  // 获取服务器信息
  Future<Map<String, dynamic>> getServerInfo() async {
    final response = await _request(
      path: '/System/Info/Public',
      method: 'GET',
      requiresAuth: false,
    );
    
    if (response == null) {
      throw Exception('获取服务器信息失败：服务器返回数据为空');
    }
    
    return response;
  }

  // 获取电视剧的季信息
  Future<Map<String, dynamic>> getSeasons({
    required String seriesId,
    required String userId,
    String? fields,
  }) async {
    final response = await _request(
      path: '/Shows/$seriesId/Seasons',
      method: 'GET',
      queryParams: {
        'UserId': userId,
        if (fields != null) 'Fields': fields,
      },
    );
    
    if (response == null) {
      return {'Items': []};
    }
    return response as Map<String, dynamic>;
  }

  // 获取季的剧集信息
  Future<Map<String, dynamic>> getEpisodes({
    required String seriesId,
    required String userId,
    String? seasonId,
    int? seasonNumber,
    String? fields,
  }) async {
    final response = await _request(
      path: '/Shows/$seriesId/Episodes',
      method: 'GET',
      queryParams: {
        'UserId': userId,
        if (seasonId != null) 'SeasonId': seasonId,
        if (seasonNumber != null) 'Season': seasonNumber.toString(),
        if (fields != null) 'Fields': fields,
      },
    );
    
    if (response == null) {
      return {'Items': []};
    }
    return response as Map<String, dynamic>;
  }

  // 添加到收藏夹
  Future<void> addToFavorites(String itemId) async {
    try {
      Logger.i('添加到收藏夹: $itemId', _tag);
      await _request(
        path: '/Users/$userId/FavoriteItems/$itemId',
        method: 'POST',
        allowNoContent: true,
      );
    } catch (e) {
      Logger.e('添加收藏失败', _tag, e);
      rethrow;
    }
  }

  // 从收藏夹移除
  Future<void> removeFromFavorites(String itemId) async {
    try {
      Logger.i('从收藏夹移除: $itemId', _tag);
      await _request(
        path: '/Users/$userId/FavoriteItems/$itemId',
        method: 'POST',
        queryParams: {'IsFavorite': 'false'},
        allowNoContent: true,
      );
    } catch (e) {
      Logger.e('移除收藏失败', _tag, e);
      rethrow;
    }
  }

  // 标记为已播放
  Future<void> markAsPlayed(String itemId) async {
    try {
      Logger.i('标记为已播放: $itemId', _tag);
      await _request(
        path: '/Users/$userId/PlayedItems/$itemId',
        method: 'POST',
        allowNoContent: true,
      );
    } catch (e) {
      Logger.e('标记已播放失败', _tag, e);
      rethrow;
    }
  }

  // 标记为未播放
  Future<void> markAsUnplayed(String itemId) async {
    try {
      Logger.i('标记为未播放: $itemId', _tag);
      await _request(
        path: '/Users/$userId/PlayedItems/$itemId',
        method: 'POST',
        queryParams: {'IsPlayed': 'false'},
        allowNoContent: true,
      );
    } catch (e) {
      Logger.e('标记未播放失败', _tag, e);
      rethrow;
    }
  }

  // 切换收藏状态
  Future<void> toggleFavorite(String itemId, bool isFavorite) async {
    try {
      if (!isFavorite) {
        // 添加到收藏
        await _request(
          path: '/Users/$userId/FavoriteItems/$itemId',
          method: 'POST',
          allowNoContent: true,
        );
      } else {
        // 从收藏中移除
        await _request(
          path: '/Users/$userId/FavoriteItems/$itemId',
          method: 'DELETE',
          allowNoContent: true,
        );
      }
    } catch (e) {
      Logger.e('切换收藏状态失败', _tag, e);
      rethrow;
    }
  }

  // 切换播放状态
  Future<void> togglePlayed(String itemId, bool isPlayed) async {
    try {
      if (!isPlayed) {
        // 标记为已播放
        await _request(
          path: '/Users/$userId/PlayedItems/$itemId',
          method: 'POST',
          allowNoContent: true,
        );
      } else {
        // 标记为未播放
        await _request(
          path: '/Users/$userId/PlayedItems/$itemId',
          method: 'DELETE',
          allowNoContent: true,
        );
      }
    } catch (e) {
      Logger.e('切换播放状态失败', _tag, e);
      rethrow;
    }
  }
}