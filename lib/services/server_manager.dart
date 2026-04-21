import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

class ServerInfo {
  final String url;
  final String username;
  final String password;
  final String name;
  final String accessToken;
  final String userId;
  final String credentialKey;

  ServerInfo({
    required this.url,
    required this.username,
    required this.password,
    required this.name,
    required this.accessToken,
    required this.userId,
    required this.credentialKey,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'username': username,
    'name': name,
    'accessToken': accessToken,
    'userId': userId,
    'credentialKey': credentialKey,
  };

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
    url: json['url'],
    username: json['username'],
    password: json['password'] ?? '',
    name: json['name'],
    accessToken: json['accessToken'],
    userId: json['userId'],
    credentialKey: json['credentialKey'] ?? '',
  );

  @override
  String toString() {
    return 'ServerInfo{name: $name, url: $url, username: $username}';
  }
}

class ServerManager {
  static const String _tag = "ServerManager";
  static const _serversKey = 'emby_servers';
  static const _userAgentKey = 'custom_user_agent';
  static const _embyHeadersKey = 'custom_emby_headers';
  static const _credentialPrefix = 'server_credential_';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String defaultUserAgent = 'ma_player/1.0.0';
  static const Map<String, String> defaultEmbyHeaders = {
    'X-Emby-Client': 'ma_player',
    'X-Emby-Device-Name': 'ma_player',
    'X-Emby-Device-Id': 'ma_player',
    'X-Emby-Client-Version': '1.0.0',
    'X-Emby-Language': 'zh-cn',
  };
  static String? _customUserAgent;
  static Map<String, String> _customEmbyHeaders = {};
  late SharedPreferences _prefs;
  List<ServerInfo> _servers = [];
  bool _initialized = false;

  // 单例模式
  static final ServerManager _instance = ServerManager._internal();
  factory ServerManager() => _instance;
  ServerManager._internal() {
    Logger.d("创建ServerManager实例", _tag);
  }

  // 初始化
  Future<void> init() async {
    Logger.i("初始化ServerManager", _tag);
    if (_initialized) {
      Logger.d("ServerManager已经初始化过", _tag);
      return;
    }
    
    try {
      _prefs = await SharedPreferences.getInstance();
      _customUserAgent = _prefs.getString(_userAgentKey);
      final rawEmbyHeaders = _prefs.getString(_embyHeadersKey);
      if (rawEmbyHeaders != null && rawEmbyHeaders.isNotEmpty) {
        final decoded = jsonDecode(rawEmbyHeaders);
        if (decoded is Map) {
          _customEmbyHeaders = decoded.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          );
        }
      }
      await loadServers();
      _initialized = true;
      Logger.i("ServerManager初始化完成，已加载${_servers.length}个服务器", _tag);
    } catch (e, stackTrace) {
      Logger.e("ServerManager初始化失败", _tag, e, stackTrace);
      _initialized = false;
      rethrow;
    }
  }

  static String get effectiveUserAgent {
    final custom = _customUserAgent?.trim();
    if (custom == null || custom.isEmpty) {
      return defaultUserAgent;
    }
    return custom;
  }

  static Map<String, String> get effectiveEmbyHeaders {
    final merged = <String, String>{...defaultEmbyHeaders};
    for (final entry in _customEmbyHeaders.entries) {
      if (entry.value.trim().isEmpty) continue;
      merged[entry.key] = entry.value.trim();
    }
    return merged;
  }

  Future<void> setCustomUserAgent(String? value) async {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      await _prefs.remove(_userAgentKey);
      _customUserAgent = null;
      Logger.i("已清除自定义 User-Agent，回退默认: $defaultUserAgent", _tag);
      return;
    }

    await _prefs.setString(_userAgentKey, normalized);
    _customUserAgent = normalized;
    Logger.i("已设置自定义 User-Agent: $normalized", _tag);
  }

  String? get customUserAgent => _customUserAgent;

  Map<String, String> get customEmbyHeaders => Map.unmodifiable(_customEmbyHeaders);

  Future<void> setCustomEmbyHeader(String key, String? value) async {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) return;

    final normalizedValue = value?.trim();
    if (normalizedValue == null || normalizedValue.isEmpty) {
      _customEmbyHeaders.remove(normalizedKey);
    } else {
      _customEmbyHeaders[normalizedKey] = normalizedValue;
    }
    await _prefs.setString(_embyHeadersKey, jsonEncode(_customEmbyHeaders));
    Logger.i("已更新自定义 Emby Header: $normalizedKey", _tag);
  }

  Future<void> setCustomEmbyHeaders(Map<String, String>? headers) async {
    if (headers == null || headers.isEmpty) {
      _customEmbyHeaders.clear();
      await _prefs.remove(_embyHeadersKey);
      Logger.i("已清除所有自定义 Emby Headers，回退默认值", _tag);
      return;
    }

    _customEmbyHeaders = {};
    for (final entry in headers.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) continue;
      _customEmbyHeaders[key] = value;
    }
    await _prefs.setString(_embyHeadersKey, jsonEncode(_customEmbyHeaders));
    Logger.i("已批量更新自定义 Emby Headers: ${_customEmbyHeaders.length} 项", _tag);
  }

  // 加载服务器列表
  Future<void> loadServers() async {
    Logger.d("开始加载服务器列表", _tag);
    try {
      final serversJson = _prefs.getStringList(_serversKey) ?? [];
      Logger.v("从SharedPreferences加载到${serversJson.length}条服务器记录", _tag);
      
      var hasLegacyMigration = false;
      final loadedServers = <ServerInfo>[];

      for (final serverRaw in serversJson) {
        final map = jsonDecode(serverRaw) as Map<String, dynamic>;
        final legacyPassword = (map['password'] ?? '').toString();
        var credentialKey = (map['credentialKey'] ?? '').toString();
        if (credentialKey.isEmpty) {
          credentialKey = _generateCredentialKey(
            url: map['url']?.toString() ?? '',
            username: map['username']?.toString() ?? '',
            name: map['name']?.toString() ?? '',
          );
          map['credentialKey'] = credentialKey;
          hasLegacyMigration = true;
        }

        String password = '';
        if (legacyPassword.isNotEmpty) {
          try {
            await saveCredential(credentialKey, legacyPassword);
            map.remove('password');
            hasLegacyMigration = true;
            password = legacyPassword;
            Logger.i('已迁移旧明文密码到安全存储: ${map['name']}', _tag);
          } catch (e, stackTrace) {
            password = legacyPassword;
            Logger.w('迁移旧明文密码失败，保留旧值继续使用: ${map['name']}', _tag);
            Logger.e('旧密码迁移失败详情', _tag, e, stackTrace);
          }
        } else {
          password = await readCredential(credentialKey) ?? '';
        }

        loadedServers.add(
          ServerInfo.fromJson(map).copyWith(
            password: password,
            credentialKey: credentialKey,
          ),
        );
      }

      _servers = loadedServers;
      if (hasLegacyMigration) {
        await _saveServers();
      }
      
      Logger.d("服务器列表加载完成", _tag);
      for (var server in _servers) {
        Logger.v("已加载服务器: ${server.toString()}", _tag);
      }
    } catch (e, stackTrace) {
      Logger.e("加载服务器列表失败", _tag, e, stackTrace);
      _servers = [];
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
      final success = await _prefs.setStringList(_serversKey, serversJson);
      if (!success) {
        throw Exception('保存服务器列表失败');
      }
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
      final normalizedServer = await _normalizeServer(server);
      _servers.add(normalizedServer);
      await _saveServers();
      Logger.i("新服务器添加成功", _tag);
    } catch (e, stackTrace) {
      Logger.e("添加服务器失败", _tag, e, stackTrace);
      rethrow;
    }
  }

  // 删除服务器
  Future<void> removeServer(String serverName) async {
    Logger.i("准备删除服务器: $serverName", _tag);
    try {
      final beforeCount = _servers.length;
      final removedServers = _servers.where((server) => server.name == serverName).toList();
      _servers.removeWhere((server) => server.name == serverName);
      for (final server in removedServers) {
        await deleteCredential(server.credentialKey);
      }
      await _saveServers();
      final removedCount = beforeCount - _servers.length;
      Logger.i("成功删除$removedCount个服务器", _tag);
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
      final index = _servers.indexWhere((s) => s.name == updatedServer.name);
      if (index != -1) {
        final existing = _servers[index];
        final normalizedServer = await _normalizeServer(updatedServer, existingServer: existing);
        _servers[index] = normalizedServer;
        await _saveServers();
        Logger.i("服务器信息更新成功", _tag);
      } else {
        Logger.w("未找到要更新的服务器: ${updatedServer.name}", _tag);
        throw Exception('未找到要更新的服务器');
      }
    } catch (e, stackTrace) {
      Logger.e("更新服务器信息失败", _tag, e, stackTrace);
      rethrow;
    }
  }

  Future<void> saveCredential(String key, String password) async {
    if (key.trim().isEmpty) return;
    await _secureStorage.write(key: key, value: password);
  }

  Future<String?> readCredential(String key) async {
    if (key.trim().isEmpty) return null;
    return _secureStorage.read(key: key);
  }

  Future<void> deleteCredential(String key) async {
    if (key.trim().isEmpty) return;
    await _secureStorage.delete(key: key);
  }

  Future<ServerInfo> _normalizeServer(
    ServerInfo server, {
    ServerInfo? existingServer,
  }) async {
    final credentialKey = server.credentialKey.isNotEmpty
        ? server.credentialKey
        : existingServer?.credentialKey.isNotEmpty == true
            ? existingServer!.credentialKey
            : _generateCredentialKey(
                url: server.url,
                username: server.username,
                name: server.name,
              );
    await saveCredential(credentialKey, server.password);
    return server.copyWith(credentialKey: credentialKey);
  }

  String _generateCredentialKey({
    required String url,
    required String username,
    required String name,
  }) {
    final seed =
        '${url.trim()}|${username.trim()}|${name.trim()}|${DateTime.now().microsecondsSinceEpoch}|${Random().nextInt(1 << 32)}';
    return '$_credentialPrefix${seed.hashCode.abs()}';
  }
}

extension on ServerInfo {
  ServerInfo copyWith({
    String? url,
    String? username,
    String? password,
    String? name,
    String? accessToken,
    String? userId,
    String? credentialKey,
  }) {
    return ServerInfo(
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      name: name ?? this.name,
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
      credentialKey: credentialKey ?? this.credentialKey,
    );
  }
}