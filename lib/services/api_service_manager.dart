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
    
    // 检查并格式化服务器 URL
    String formattedUrl = server.url;
    if (!formattedUrl.startsWith('http')) {
      formattedUrl = 'http://${server.url}';
      Logger.w("服务器URL不包含协议，已自动添加: $formattedUrl", _tag);
    }
    if (formattedUrl.endsWith('/')) {
      formattedUrl = formattedUrl.substring(0, formattedUrl.length - 1);
      Logger.w("服务器URL包含结尾斜杠，已移除: $formattedUrl", _tag);
    }
    
    // 如果已经初始化且是同一个服务器，直接返回
    if (_embyApi != null && _currentServer != null &&
        _currentServer!.url == formattedUrl &&
        _currentServer!.username == server.username &&
        _currentServer!.accessToken == server.accessToken) {
      Logger.d("复用现有EmbyApi实例", _tag);
      return _embyApi!;
    }

    Logger.d("创建新的EmbyApi实例", _tag);
    // 创建新的 API 实例
    _embyApi = EmbyApiService(
      baseUrl: formattedUrl,
      username: server.username,
      password: server.password,
    );
    _embyApi!.accessToken = server.accessToken;
    _embyApi!.userId = server.userId;
    _currentServer = ServerInfo(
      url: formattedUrl,
      username: server.username,
      password: server.password,
      name: server.name,
      accessToken: server.accessToken,
      userId: server.userId,
    );
    
    // 只有当没有 accessToken 时才进行身份验证
    if (server.accessToken.isEmpty) {
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