import 'emby_api.dart';
import 'server_manager.dart';

class ApiServiceManager {
  static final ApiServiceManager _instance = ApiServiceManager._internal();
  EmbyApiService? _embyApi;
  ServerInfo? _currentServer;

  factory ApiServiceManager() {
    return _instance;
  }

  ApiServiceManager._internal();

  Future<EmbyApiService> initializeEmbyApi(ServerInfo server) async {
    // 如果已经初始化且是同一个服务器，直接返回
    if (_embyApi != null && _currentServer != null &&
        _currentServer!.url == server.url &&
        _currentServer!.username == server.username &&
        _currentServer!.accessToken == server.accessToken) {
      return _embyApi!;
    }

    // 创建新的 API 实例
    _embyApi = EmbyApiService(
      baseUrl: server.url,
      username: server.username,
      password: server.password,
    );
    _embyApi!.accessToken = server.accessToken;
    _embyApi!.userId = server.userId;
    _currentServer = server;
    
    // 只有当没有 accessToken 时才进行身份验证
    if (server.accessToken == null || server.accessToken!.isEmpty) {
      try {
        final authResult = await _embyApi!.authenticate();
        _embyApi!.accessToken = authResult['accessToken'];
        _embyApi!.userId = authResult['userId'];
      } catch (e) {
        print('EmbyApi 初始化失败: $e');
        rethrow;
      }
    }
    
    return _embyApi!;
  }

  EmbyApiService get embyApi {
    if (_embyApi == null) {
      throw Exception('EmbyApi 尚未初始化，请先调用 initializeEmbyApi');
    }
    return _embyApi!;
  }

  void resetEmbyApi() {
    _embyApi = null;
    _currentServer = null;
  }
} 