import 'emby_api.dart';
import 'server_manager.dart';
import '../utils/logger.dart';

class ApiServiceManager {
  static const String _tag = "ApiServiceManager";
  static final ApiServiceManager _instance = ApiServiceManager._internal();
  EmbyApiService? _embyApi;
  ServerInfo? _currentServer;

  factory ApiServiceManager() {
    return _instance;
  }

  ApiServiceManager._internal() {
    Logger.d("创建ApiServiceManager实例", _tag);
  }

  Future<EmbyApiService> initializeEmbyApi(ServerInfo server) async {
    Logger.i("初始化EmbyApi - 服务器: ${server.toString()}", _tag);
    
    // 如果已经初始化且是同一个服务器，直接返回
    if (_embyApi != null && _currentServer != null &&
        _currentServer!.url == server.url &&
        _currentServer!.username == server.username &&
        _currentServer!.accessToken == server.accessToken) {
      Logger.d("复用现有EmbyApi实例", _tag);
      return _embyApi!;
    }

    Logger.d("创建新的EmbyApi实例", _tag);
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
      Logger.d("accessToken为空，进行身份验证", _tag);
      try {
        final authResult = await _embyApi!.authenticate();
        _embyApi!.accessToken = authResult['accessToken'];
        _embyApi!.userId = authResult['userId'];
        Logger.i("身份验证成功，获取到新的accessToken", _tag);
      } catch (e, stackTrace) {
        Logger.e("EmbyApi初始化失败", _tag, e, stackTrace);
        rethrow;
      }
    } else {
      Logger.d("使用现有accessToken", _tag);
    }
    
    Logger.i("EmbyApi初始化完成", _tag);
    return _embyApi!;
  }

  EmbyApiService get embyApi {
    if (_embyApi == null) {
      Logger.e("尝试访问未初始化的EmbyApi", _tag);
      throw Exception('EmbyApi 尚未初始化，请先调用 initializeEmbyApi');
    }
    Logger.v("获取EmbyApi实例", _tag);
    return _embyApi!;
  }

  void resetEmbyApi() {
    Logger.i("重置EmbyApi", _tag);
    _embyApi = null;
    _currentServer = null;
  }
} 