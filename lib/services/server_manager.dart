import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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
}

class ServerManager {
  static const _serversKey = 'emby_servers';
  late SharedPreferences _prefs;
  List<ServerInfo> _servers = [];

  // 单例模式
  static final ServerManager _instance = ServerManager._internal();
  factory ServerManager() => _instance;
  ServerManager._internal();

  // 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await loadServers();
  }

  // 加载服务器列表
  Future<void> loadServers() async {
    final serversJson = _prefs.getStringList(_serversKey) ?? [];
    _servers = serversJson
        .map((json) => ServerInfo.fromJson(jsonDecode(json)))
        .toList();
  }

  // 保存服务器列表
  Future<void> _saveServers() async {
    final serversJson = _servers
        .map((server) => jsonEncode(server.toJson()))
        .toList();
    await _prefs.setStringList(_serversKey, serversJson);
  }

  // 添加服务器
  Future<void> addServer(ServerInfo server) async {
    _servers.add(server);
    await _saveServers();
  }

  // 删除服务器
  Future<void> removeServer(String url) async {
    _servers.removeWhere((server) => server.url == url);
    await _saveServers();
  }

  // 获取所有服务器
  List<ServerInfo> get servers => List.unmodifiable(_servers);

  // 根据URL获取服务器
  ServerInfo? getServerByUrl(String url) {
    try {
      return _servers.firstWhere((server) => server.url == url);
    } catch (e) {
      return null;
    }
  }

  // 更新服务器信息
  Future<void> updateServer(ServerInfo updatedServer) async {
    final index = _servers.indexWhere((s) => s.url == updatedServer.url);
    if (index != -1) {
      _servers[index] = updatedServer;
      await _saveServers();
    }
  }
}