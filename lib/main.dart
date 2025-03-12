import 'package:flutter/material.dart';
import 'services/server_manager.dart';
import 'pages/add_server_page.dart';
import 'pages/edit_server_page.dart';
import 'pages/video_list_page.dart';
import 'pages/video_detail_page.dart';
import 'pages/video_player_page.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'dart:io';

void main() async {
  
  WidgetsFlutterBinding.ensureInitialized();
  
  ServerManager().init();
  fvp.registerWith();
    
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emby Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ServerListPage(),
    );
  }
}

class ServerListPage extends StatefulWidget {
  const ServerListPage({super.key});

  @override
  State<ServerListPage> createState() => _ServerListPageState();
}

class _ServerListPageState extends State<ServerListPage> {
  final _serverManager = ServerManager();
  List<ServerInfo> _servers = [];

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  void _loadServers() {
    setState(() {
      _servers = _serverManager.servers;
    });
  }

  void _addServer() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const AddServerPage()),
    );

    if (result != null && mounted) {
      final serverInfo = ServerInfo(
        url: result['url']!,
        username: result['username']!,
        password: result['password']!,
        name: result['name']!,
        accessToken: result['accessToken']!,
        userId: result['userId']!,
      );
      await _serverManager.addServer(serverInfo);
      _loadServers();
    }
  }

  void _onServerTap(ServerInfo server) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoListPage(server: server),
      ),
    );
  }

  void _editServer(ServerInfo server) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => EditServerPage(server: server)),
    );

    if (result != null && mounted) {
      final updatedServer = ServerInfo(
        url: result['url']!,
        username: result['username']!,
        password: result['password']!,
        name: result['name']!,
        accessToken: result['accessToken']!,
        userId: result['userId']!,
      );
      await _serverManager.updateServer(updatedServer);
      _loadServers();
    }
  }

  void _deleteServer(ServerInfo server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定要删除服务器 "${server.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _serverManager.removeServer(server.url);
      _loadServers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('服务器列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addServer,
            tooltip: '添加服务器',
          ),
        ],
      ),
      body: _servers.isEmpty
          ? const Center(
              child: Text('暂无服务器'),
            )
          : ListView.builder(
              itemCount: _servers.length,
              itemBuilder: (context, index) {
                final server = _servers[index];
                return ListTile(
                  leading: const Icon(Icons.computer),
                  title: Text(server.name),
                  subtitle: Text(server.url),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editServer(server),
                        tooltip: '编辑服务器',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteServer(server),
                        tooltip: '删除服务器',
                      ),
                    ],
                  ),
                  onTap: () => _onServerTap(server),
                );
              },
            ),
    );
  }
}
