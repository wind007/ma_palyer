import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

class ServerInfo {
  final String url;
  final String username;
  final String password;
  final String name;
  final String accessToken;
  final String userId;

  ServerInfo({
    required this.url,
    required this.username,
    required this.password,
    required this.name,
    required this.accessToken,
    required this.userId,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'username': username,
    'password': password,
    'name': name,
    'accessToken': accessToken,
    'userId': userId,
  };

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
    url: json['url'],
    username: json['username'],
    password: json['password'],
    name: json['name'],
    accessToken: json['accessToken'],
    userId: json['userId'],
  );

  @override
  String toString() {
    return 'ServerInfo{name: $name, url: $url, username: $username}';
  }
}

class ServerManager {
  static const String _tag = "ServerManager";
  static const _serversKey = 'emby_servers';
  late SharedPreferences _prefs;
  List<ServerInfo> _servers = [];

  // 单例模式
  static final ServerManager _instance = ServerManager._internal();
  factory ServerManager() => _instance;
  ServerManager._internal() {
    Logger.d("创建ServerManager实例", _tag);
  }

  // 初始化
  Future<void> init() async {
    Logger.i("初始化ServerManager", _tag);
    try {
      _prefs = await SharedPreferences.getInstance();
      await loadServers();
      Logger.i("ServerManager初始化完成，已加载${_servers.length}个服务器", _tag);
    } catch (e, stackTrace) {
      Logger.e("ServerManager初始化失败", _tag, e, stackTrace);
      rethrow;
    }
  }

  // 加载服务器列表
  Future<void> loadServers() async {
    Logger.d("开始加载服务器列表", _tag);
    try {
      final serversJson = _prefs.getStringList(_serversKey) ?? [];
      Logger.v("从SharedPreferences加载到${serversJson.length}条服务器记录", _tag);
      
      _servers = serversJson
          .map((json) => ServerInfo.fromJson(jsonDecode(json)))
          .toList();
      
      Logger.d("服务器列表加载完成", _tag);
      for (var server in _servers) {
        Logger.v("已加载服务器: ${server.toString()}", _tag);
      }
    } catch (e, stackTrace) {
      Logger.e("加载服务器列表失败", _tag, e, stackTrace);
      rethrow;
    }
  }

  // 保存服务器列表
  Future<void> _saveServers() async {
    Logger.d("开始保存服务器列表", _tag);
    try {
      final serversJson = _servers
          .map((server) => jsonEncode(server.toJson()))
          .toList();
      await _prefs.setStringList(_serversKey, serversJson);
      Logger.i("成功保存${_servers.length}个服务器信息", _tag);
    } catch (e, stackTrace) {
      Logger.e("保存服务器列表失败", _tag, e, stackTrace);
      rethrow;
    }
  }

  // 添加服务器
  Future<void> addServer(ServerInfo server) async {
    Logger.i("添加新服务器: ${server.toString()}", _tag);
    try {
      _servers.add(server);
      await _saveServers();
      Logger.i("新服务器添加成功", _tag);
    } catch (e, stackTrace) {
      Logger.e("添加服务器失败", _tag, e, stackTrace);
      rethrow;
    }
  }

  // 删除服务器
  Future<void> removeServer(String url) async {
    Logger.i("准备删除服务器: $url", _tag);
    try {
      final beforeCount = _servers.length;
      _servers.removeWhere((server) => server.url == url);
      await _saveServers();
      final removedCount = beforeCount - _servers.length;
      Logger.i("成功删除${removedCount}个服务器", _tag);
    } catch (e, stackTrace) {
      Logger.e("删除服务器失败", _tag, e, stackTrace);
      rethrow;
    }
  }

  // 获取所有服务器
  List<ServerInfo> get servers {
    Logger.v("获取服务器列表，当前共${_servers.length}个服务器", _tag);
    return List.unmodifiable(_servers);
  }

  // 更新服务器信息
  Future<void> updateServer(ServerInfo updatedServer) async {
    Logger.i("更新服务器信息: ${updatedServer.toString()}", _tag);
    try {
      final index = _servers.indexWhere((s) => s.url == updatedServer.url);
      if (index != -1) {
        _servers[index] = updatedServer;
        await _saveServers();
        Logger.i("服务器信息更新成功", _tag);
      } else {
        Logger.w("未找到要更新的服务器: ${updatedServer.url}", _tag);
      }
    } catch (e, stackTrace) {
      Logger.e("更新服务器信息失败", _tag, e, stackTrace);
      rethrow;
    }
  }
}