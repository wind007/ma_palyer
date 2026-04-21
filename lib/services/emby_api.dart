import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../services/server_manager.dart';
import '../utils/logger.dart';

enum ApiErrorType {
  networkUnreachable,
  timeout,
  sslError,
  authFailed,
  serverNotFound,
  serverError,
  unknown,
}

class ApiException implements Exception {
  final ApiErrorType type;
  final String userMessage;
  final String technicalDetails;
  final int? statusCode;

  const ApiException({
    required this.type,
    required this.userMessage,
    required this.technicalDetails,
    this.statusCode,
  });

  @override
  String toString() => userMessage;
}

class EmbyApiService {
  static const String _tag = "EmbyApi";
  static const int _maxAuthRetryCount = 1;
  static const Duration _requestTimeout = Duration(seconds: 15);
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
    // 使用普通的 HTTP 客户端
    _client = IOClient();
  }

  // 统一的网络请求处理方法
  Future<dynamic> _request({
    required String path,
    required String method,
    Map<String, String>? queryParams,
    dynamic body,
    bool requiresAuth = true,
    bool allowNoContent = false,
    int authRetryCount = 0,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: queryParams,
      );
      
      // 准备请求头
      final headers = {
        'Content-Type': 'application/json',
        'User-Agent': ServerManager.effectiveUserAgent,
        ...ServerManager.effectiveEmbyHeaders,
      };

      // 如果需要认证且有token，添加token
      if (requiresAuth && accessToken != null) {
        headers['X-Emby-Token'] = accessToken!;
      }

      http.Response response;
      switch (method.toUpperCase()) {
        case 'GET':
          response = await _client
              .get(uri, headers: headers)
              .timeout(_requestTimeout);
          break;
        case 'POST':
          response = await _client
              .post(
                uri,
                headers: headers,
                body: body != null ? json.encode(body) : null,
              )
              .timeout(_requestTimeout);
          break;
        case 'DELETE':
          response = await _client
              .delete(
                uri,
                headers: headers,
                body: body != null ? json.encode(body) : null,
              )
              .timeout(_requestTimeout);
          break;
        default:
          throw Exception('不支持的请求方法: $method');
      }

      // 处理401状态码，token失效时自动重试
      if (response.statusCode == 401 && requiresAuth) {
        if (authRetryCount >= _maxAuthRetryCount) {
          throw ApiException(
            type: ApiErrorType.authFailed,
            userMessage: '认证失败，请重新检查账号信息',
            technicalDetails: '认证重试超限: path=$path',
            statusCode: 401,
          );
        }
        // 清除旧token
        accessToken = null;
        // 重新认证
        await authenticate();
        // 短暂退避，避免认证异常时高频打满服务端
        await Future.delayed(const Duration(milliseconds: 300));
        // 重试请求
        return _request(
          path: path,
          method: method,
          queryParams: queryParams,
          body: body,
          requiresAuth: requiresAuth,
          allowNoContent: allowNoContent,
          authRetryCount: authRetryCount + 1,
        );
      }

      // 允许204状态码
      if (response.statusCode == 204 && allowNoContent) {
        return null;
      }

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw _mapHttpStatusToException(
          statusCode: response.statusCode,
          path: path,
          body: response.body,
        );
      }

      if (response.body.isEmpty) {
        return null;
      }

      return json.decode(response.body);
    } on ApiException {
      rethrow;
    } on SocketException catch (e) {
      throw ApiException(
        type: ApiErrorType.networkUnreachable,
        userMessage: '无法连接服务器，请检查网络或地址后重试',
        technicalDetails: e.toString(),
      );
    } on HandshakeException catch (e) {
      throw ApiException(
        type: ApiErrorType.sslError,
        userMessage: 'HTTPS 证书校验失败，请检查服务器证书配置',
        technicalDetails: e.toString(),
      );
    } on HttpException catch (e) {
      throw ApiException(
        type: ApiErrorType.networkUnreachable,
        userMessage: '网络连接异常，请稍后重试',
        technicalDetails: e.toString(),
      );
    } on FormatException catch (e) {
      throw ApiException(
        type: ApiErrorType.unknown,
        userMessage: '服务器返回数据格式异常，请稍后重试',
        technicalDetails: e.toString(),
      );
    } on TimeoutException catch (e) {
      throw ApiException(
        type: ApiErrorType.timeout,
        userMessage: '请求超时，请检查网络后重试',
        technicalDetails: e.toString(),
      );
    } catch (e) {
      throw ApiException(
        type: ApiErrorType.unknown,
        userMessage: '请求失败，请稍后重试',
        technicalDetails: e.toString(),
      );
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
    } on ApiException catch (e) {
      // 清除可能存在的旧数据
      accessToken = null;
      userId = null;
      if (e.statusCode == 400 || e.statusCode == 401) {
        throw ApiException(
          type: ApiErrorType.authFailed,
          userMessage: '用户名或密码错误，请重新输入',
          technicalDetails: e.technicalDetails,
          statusCode: e.statusCode,
        );
      }
      rethrow;
    } catch (e) {
      accessToken = null;
      userId = null;
      throw ApiException(
        type: ApiErrorType.unknown,
        userMessage: '认证失败，请稍后重试',
        technicalDetails: e.toString(),
      );
    }
  }

  ApiException _mapHttpStatusToException({
    required int statusCode,
    required String path,
    required String body,
  }) {
    if (statusCode == 400 || statusCode == 401 || statusCode == 403) {
      return ApiException(
        type: ApiErrorType.authFailed,
        userMessage: '认证失败，请检查用户名和密码',
        technicalDetails: 'HTTP $statusCode: $path, body=$body',
        statusCode: statusCode,
      );
    }
    if (statusCode == 404) {
      return ApiException(
        type: ApiErrorType.serverNotFound,
        userMessage: '服务器地址无效或接口不存在，请检查地址',
        technicalDetails: 'HTTP 404: $path, body=$body',
        statusCode: statusCode,
      );
    }
    if (statusCode >= 500) {
      return ApiException(
        type: ApiErrorType.serverError,
        userMessage: '服务器暂时不可用，请稍后重试',
        technicalDetails: 'HTTP $statusCode: $path, body=$body',
        statusCode: statusCode,
      );
    }
    return ApiException(
      type: ApiErrorType.unknown,
      userMessage: '请求失败，请稍后重试',
      technicalDetails: 'HTTP $statusCode: $path, body=$body',
      statusCode: statusCode,
    );
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
  Future<String> getPlaybackUrl(
    String itemId, {
    int? mediaSourceIndex,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String subtitleMethod = 'Embed',
  }) async {
    final info = await getPlaybackInfo(itemId);
    final mediaSources = info['MediaSources'] as List;
    if (mediaSources.isEmpty) {
      throw Exception('没有可用的播放源');
    }
    
    final mediaSource = mediaSources[mediaSourceIndex ?? 0];
    final sourceId = mediaSource['Id'];
    final container = mediaSource['Container'];
    final mediaStreams = mediaSource['MediaStreams'] as List? ?? const [];
    
    // 构建直接流URL
    final streamUrl = '$baseUrl/Videos/$itemId/stream';
    final params = {
      'api_key': accessToken,
      'Static': 'true',
      'MediaSourceId': sourceId,
      'Container': container,
      'AudioCodec': 'aac,mp3,ac3',
      'VideoCodec': 'h264,hevc,h265',
    };

    final hasAudioStreamIndex = mediaStreams.any(
      (s) => s is Map<String, dynamic> &&
          s['Type']?.toString().toLowerCase() == 'audio' &&
          s['Index'] == audioStreamIndex,
    );
    if (audioStreamIndex != null && hasAudioStreamIndex) {
      params['AudioStreamIndex'] = audioStreamIndex.toString();
    }

    final hasSubtitleStreamIndex = mediaStreams.any(
      (s) => s is Map<String, dynamic> &&
          s['Type']?.toString().toLowerCase() == 'subtitle' &&
          s['Index'] == subtitleStreamIndex,
    );
    if (subtitleStreamIndex != null && subtitleStreamIndex >= 0 && hasSubtitleStreamIndex) {
      if (subtitleMethod.isNotEmpty) {
        params['SubtitleMethod'] = subtitleMethod;
      }
      params['SubtitleStreamIndex'] = subtitleStreamIndex.toString();
    } else if (subtitleStreamIndex != null && subtitleStreamIndex >= 0 && !hasSubtitleStreamIndex) {
      Logger.w(
        '字幕索引不在当前媒体源中，已回退到默认字幕策略: subtitleIndex=$subtitleStreamIndex, sourceId=$sourceId',
        _tag,
      );
    } else if (subtitleMethod.toLowerCase() == 'none') {
      // 某些服务端/媒体组合在 direct stream 下不接受 SubtitleMethod=None，
      // 这里不传字幕参数，交给服务端默认关闭/不加载字幕策略。
      Logger.d(
        '请求关闭字幕：跳过 SubtitleMethod 参数以避免媒体打开失败, sourceId=$sourceId',
        _tag,
      );
    }
    
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
    required String mediaSourceId,
    required String playSessionId,
    required int positionTicks,
    required bool isPaused,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    bool isMuted = false,
    int volumeLevel = 100,
  }) async {
    try {
      await _request(
        path: '/Users/$userId/PlayingItems/$itemId/Progress',
        method: 'POST',
        body: {
          'ItemId': itemId,
          'MediaSourceId': mediaSourceId,
          'PositionTicks': positionTicks,
          'IsPaused': isPaused,
          'IsMuted': isMuted,
          'PlayMethod': 'DirectStream',
          'RepeatMode': 'RepeatNone',
          'PlaybackStartTimeTicks': 0,
          'VolumeLevel': volumeLevel,
          if (audioStreamIndex != null) 'AudioStreamIndex': audioStreamIndex,
          if (subtitleStreamIndex != null) 'SubtitleStreamIndex': subtitleStreamIndex,
          'PlaySessionId': playSessionId,
        },
        allowNoContent: true,
      );
      Logger.i(
        '更新播放进度成功: $positionTicks ticks, isPaused: $isPaused, mediaSourceId: $mediaSourceId',
        _tag,
      );
    } catch (e) {
      Logger.e('更新播放进度失败', _tag, e);
      rethrow;
    }
  }

  // 停止播放
  Future<void> stopPlayback(
    String itemId, {
    String? mediaSourceId,
    String? playSessionId,
    int? positionTicks,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    try {
      await _request(
        path: '/Sessions/Playing/Stopped',
        method: 'POST',
        body: {
          'ItemId': itemId,
          'UserId': userId,
          'PlayMethod': 'DirectStream',
          if (mediaSourceId != null && mediaSourceId.isNotEmpty) 'MediaSourceId': mediaSourceId,
          if (playSessionId != null && playSessionId.isNotEmpty) 'PlaySessionId': playSessionId,
          if (positionTicks != null) 'PositionTicks': positionTicks,
          if (audioStreamIndex != null) 'AudioStreamIndex': audioStreamIndex,
          if (subtitleStreamIndex != null) 'SubtitleStreamIndex': subtitleStreamIndex,
        },
        allowNoContent: true,
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
  Future<Map<String, dynamic>> getVideoDetails(
    String itemId, {
    String? fields,
  }) async {
    return await _request(
      path: '/Users/$userId/Items/$itemId',
      method: 'GET',
      queryParams: {
        'Fields': fields ?? 'Overview,Genres,Studios,CommunityRating,CriticRating,People,MediaStreams,MediaSources',
      },
    );
  }

  // 获取最近观看
  Future<Map<String, dynamic>> getResumeItems({
    int? startIndex,
    int? limit,
    String includeItemTypes = 'Movie,Episode,Series',
  }) async {
    return await _request(
      path: '/Users/$userId/Items/Resume',
      method: 'GET',
      queryParams: {
        'Fields': 'PrimaryImageAspectRatio,Overview',
        'ImageTypeLimit': '1',
        'EnableImages': 'true',
        'EnableImageTypes': 'Primary',
        'EnableUserData': 'true',
        'MediaTypes': 'Video',
        'IncludeItemTypes': includeItemTypes,
        'EnableTotalRecordCount': 'true',
        if (startIndex != null) 'StartIndex': startIndex.toString(),
        if (limit != null) 'Limit': limit.toString(),
      },
    );
  }

  // 获取最新添加
  Future<Map<String, dynamic>> getLatestItems({
    int? startIndex,
    int? limit,
  }) async {
    final response = await _request(
      path: '/Users/$userId/Items/Latest',
      method: 'GET',
      queryParams: {
        'EnableImages': 'true',
        'EnableImageTypes': 'Primary',
        'ImageTypeLimit': '1',
        'EnableUserData': 'true',
        'Fields': 'PrimaryImageAspectRatio,Overview',
        'EnableTotalRecordCount': 'true',
        if (startIndex != null) 'StartIndex': startIndex.toString(),
        if (limit != null) 'Limit': limit.toString(),
      },
    );

    // 处理返回的列表数据
    if (response is List) {
      return {
        'Items': response,
        'TotalRecordCount': response.length,
      };
    }
    
    // 如果已经是 Map 格式则直接返回
    return response as Map<String, dynamic>;
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

  String? getImageUrl({
    required String itemId,
    required String imageType,
    int? width,
    int? height,
    int? quality,
    String? tag,
    String? fallbackUrl,
  }) {
    try {
      if (itemId.isEmpty) {
        Logger.w('获取图片URL失败：无效的 itemId', _tag);
        return fallbackUrl;
      }

      // 检查是否有对应类型的图片标签
      if (tag == null) {
        Logger.w('获取图片URL失败：没有找到图片标签', _tag);
        return fallbackUrl;
      }

      // 检查 baseUrl 是否有效
      if (baseUrl.isEmpty || !baseUrl.startsWith('http')) {
        Logger.w('获取图片URL失败：无效的服务器地址 - $baseUrl', _tag);
        return fallbackUrl;
      }

      final params = <String, String>{};

      if (width != null) params['Width'] = width.toString();
      if (height != null) params['Height'] = height.toString();
      if (quality != null) params['Quality'] = quality.toString();
      if (tag.isNotEmpty) params['Tag'] = tag;

      // 确保 baseUrl 不以斜杠结尾
      final cleanBaseUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

      final uri = Uri.parse('$cleanBaseUrl/Items/$itemId/Images/$imageType')
          .replace(queryParameters: params);
      
      final url = uri.toString();
      Logger.d('生成图片URL: $url', _tag);
      return url;
    } catch (e) {
      Logger.e('生成图片URL失败', _tag, e);
      return fallbackUrl;
    }
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

  // 搜索项目
  Future<Map<String, dynamic>> searchItems({
    String? searchTerm,
    String? nameStartsWithOrGreater,
    int? startIndex,
    int? limit,
    String? includeItemTypes,
    String? fields,
    bool? recursive,
  }) async {
    try {
      Logger.d("执行搜索: term=$searchTerm, nameStartsWith=$nameStartsWithOrGreater", _tag);
      final queryParams = {
        'Recursive': (recursive ?? true).toString(),
        'EnableTotalRecordCount': 'true',
        'EnableImages': 'true',
        'ImageTypeLimit': '1',
        'EnableImageTypes': 'Primary',
        'EnableUserData': 'true',
        'Fields': fields ?? 'PrimaryImageAspectRatio,Overview',
        if (searchTerm != null) 'SearchTerm': searchTerm,
        if (nameStartsWithOrGreater != null) 'NameStartsWithOrGreater': nameStartsWithOrGreater,
        if (includeItemTypes != null) 'IncludeItemTypes': includeItemTypes,
        if (startIndex != null) 'StartIndex': startIndex.toString(),
        if (limit != null) 'Limit': limit.toString(),
      };

      final response = await _request(
        path: '/Users/$userId/Items',
        method: 'GET',
        queryParams: queryParams,
      );
      
      Logger.d("搜索完成，获取到 ${(response['Items'] as List).length} 个结果", _tag);
      return response;
    } catch (e) {
      Logger.e("搜索失败", _tag, e);
      rethrow;
    }
  }

  // 获取项目列表
  Future<Map<String, dynamic>> getItems({
    required String parentId,
    required String userId,
    String? fields,
    String? includeItemTypes,
    String? sortBy,
    bool? recursive,
  }) async {
    Logger.d("获取项目列表 - ParentId: $parentId, UserId: $userId", _tag);
    final response = await _request(
      path: '/Users/$userId/Items',
      method: 'GET',
      queryParams: {
        'ParentId': parentId,
        'UserId': userId,
        'Recursive': (recursive ?? true).toString(),
        'ImageTypeLimit': '1',
        'EnableImages': 'true',
        'EnableImageTypes': 'Primary',
        'EnableUserData': 'true',
        'SortBy': sortBy ?? 'SortName,ProductionYear',
        'SortOrder': 'Ascending',
        'Fields': fields ?? 'Path,Overview,MediaSources,UserData,PrimaryImageAspectRatio,MediaType,Type',
        if (includeItemTypes != null) 'IncludeItemTypes': includeItemTypes,
      },
    );
    
    if (response == null) {
      Logger.w('获取项目列表失败：返回数据为空', _tag);
      return {'Items': []};
    }
    
    final items = response['Items'] as List?;
    Logger.d('成功获取项目列表，共 ${items?.length ?? 0} 个项目', _tag);
    if (items != null && items.isNotEmpty) {
      Logger.d('第一个项目信息: Type=${items[0]['Type']}, MediaType=${items[0]['MediaType']}, Name=${items[0]['Name']}', _tag);
    }
    
    return response as Map<String, dynamic>;
  }

  // 获取字幕 URL
  Future<String?> getSubtitleUrl(
    String itemId,
    int subtitleIndex, {
    int? mediaSourceIndex,
    String format = 'srt',
    int? startPositionTicks,
    int? endPositionTicks,
    bool? copyTimestamps,
  }) async {
    try {
      // 获取媒体源信息
      final info = await getPlaybackInfo(itemId);
      final mediaSources = info['MediaSources'] as List;
      if (mediaSources.isEmpty) {
        throw Exception('没有可用的播放源');
      }
      
      final sourceIndex = mediaSourceIndex ?? 0;
      if (sourceIndex < 0 || sourceIndex >= mediaSources.length) {
        throw Exception('无效的播放源索引: $sourceIndex');
      }

      final mediaSource = mediaSources[sourceIndex];
      final mediaSourceId = mediaSource['Id'];

      // 构建基础 URL
      String subtitleUrl;
      if (startPositionTicks != null) {
        // 使用带时间戳的 API
        subtitleUrl = '$baseUrl/Videos/$itemId/$mediaSourceId/Subtitles/$subtitleIndex/$startPositionTicks/Stream.$format';
      } else {
        // 使用基础 API
        subtitleUrl = '$baseUrl/Videos/$itemId/$mediaSourceId/Subtitles/$subtitleIndex/Stream.$format';
      }

      // 添加查询参数
      final params = <String, String>{
        'api_key': accessToken!,
      };

      if (endPositionTicks != null) {
        params['EndPositionTicks'] = endPositionTicks.toString();
      }

      if (copyTimestamps != null) {
        params['CopyTimestamps'] = copyTimestamps.toString();
      }
      
      final uri = Uri.parse(subtitleUrl).replace(queryParameters: params);
      Logger.d('字幕URL: ${uri.toString()}', _tag);
      return uri.toString();
    } catch (e) {
      Logger.e('获取字幕URL失败', _tag, e);
      return null;
    }
  }
}