import 'package:flutter/material.dart';
import '../services/server_manager.dart';
import '../services/theme_manager.dart';
import '../utils/logger.dart';
import '../widgets/adaptive_app_bar.dart';
import 'add_server_page.dart';
import 'edit_server_page.dart';
import 'video_list_page.dart';

class ServerListPage extends StatefulWidget {
  const ServerListPage({super.key});

  @override
  State<ServerListPage> createState() => _ServerListPageState();
}

class _ServerListPageState extends State<ServerListPage> {
  static const String _tag = "ServerList";
  final _serverManager = ServerManager();
  final _listKey = GlobalKey<AnimatedListState>();
  final List<ServerInfo> _servers = <ServerInfo>[];

  @override
  void initState() {
    super.initState();
    Logger.i("初始化服务器列表页面", _tag);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadServers();
    });
  }

  Future<void> _loadServers() async {
    Logger.d("加载服务器列表", _tag);
    try {
      await _serverManager.loadServers();
      if (mounted) {
        final newServers = List<ServerInfo>.from(_serverManager.servers);
        setState(() {
          // 清空当前列表
          while (_servers.isNotEmpty) {
            _servers.removeLast();
            _listKey.currentState?.removeItem(
              _servers.length,
              (context, animation) => const SizedBox.shrink(),
              duration: Duration.zero,
            );
          }
          
          // 添加新的服务器
          for (var server in newServers) {
            _servers.add(server);
            _listKey.currentState?.insertItem(_servers.length - 1);
          }
        });
      }
      Logger.d("已加载 ${_servers.length} 个服务器", _tag);
    } catch (e) {
      Logger.e("加载服务器列表失败", _tag, e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载服务器列表失败: $e')),
        );
      }
    }
  }

  Widget _buildServerItem(ServerInfo server, Animation<double> animation) {
    return SlideTransition(
      position: animation.drive(Tween(
        begin: const Offset(-1, 0),
        end: Offset.zero,
      )),
      child: Card(
        margin: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).primaryColor,
            child: const Icon(
              Icons.computer,
              color: Colors.white,
            ),
          ),
          title: Text(
            server.name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
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
                color: Colors.red[300],
                onPressed: () => _deleteServer(server),
                tooltip: '删除服务器',
              ),
            ],
          ),
          onTap: () => _onServerTap(server),
        ),
      ),
    );
  }

  Future<void> _addServer() async {
    Logger.i("打开添加服务器页面", _tag);
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const AddServerPage()),
    );

    if (result != null && mounted) {
      Logger.d("添加新服务器: ${result['name']}", _tag);
      try {
        final serverInfo = ServerInfo(
          url: result['url']!,
          username: result['username']!,
          password: result['password']!,
          name: result['name']!,
          accessToken: result['accessToken']!,
          userId: result['userId']!,
        );
        await _serverManager.addServer(serverInfo);
        Logger.i("服务器添加成功: ${serverInfo.name}", _tag);
        
        setState(() {
          _servers.add(serverInfo);
          _listKey.currentState?.insertItem(_servers.length - 1);
        });
      } catch (e) {
        Logger.e("添加服务器失败", _tag, e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('添加服务器失败: $e')),
          );
        }
      }
    } else {
      Logger.d("取消添加服务器", _tag);
    }
  }

  void _onServerTap(ServerInfo server) {
    Logger.i("进入服务器: ${server.name}", _tag);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoListPage(server: server),
      ),
    );
  }

  Future<void> _editServer(ServerInfo server) async {
    Logger.i("编辑服务器: ${server.name}", _tag);
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => EditServerPage(server: server)),
    );

    if (result != null && mounted) {
      Logger.d("更新服务器信息: ${result['name']}", _tag);
      try {
        final updatedServer = ServerInfo(
          url: result['url']!,
          username: result['username']!,
          password: result['password']!,
          name: result['name']!,
          accessToken: result['accessToken']!,
          userId: result['userId']!,
        );
        await _serverManager.updateServer(updatedServer);
        Logger.i("服务器更新成功: ${updatedServer.name}", _tag);
        
        final index = _servers.indexWhere((s) => s.name == server.name);
        if (index != -1) {
          setState(() {
            _servers[index] = updatedServer;
          });
        }
      } catch (e) {
        Logger.e("更新服务器失败", _tag, e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新服务器失败: $e')),
          );
        }
      }
    } else {
      Logger.d("取消编辑服务器", _tag);
    }
  }

  Future<void> _deleteServer(ServerInfo server) async {
    Logger.i("准备删除服务器: ${server.name}", _tag);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定要删除服务器 "${server.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () {
              Logger.d("取消删除服务器: ${server.name}", _tag);
              Navigator.of(context).pop(false);
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Logger.d("确认删除服务器: ${server.name}", _tag);
              Navigator.of(context).pop(true);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final index = _servers.indexOf(server);
        if (index != -1) {
          await _serverManager.removeServer(server.name);
          Logger.i("服务器删除成功: ${server.name}", _tag);
          
          setState(() {
            _servers.removeAt(index);
            _listKey.currentState?.removeItem(
              index,
              (context, animation) => _buildServerItem(server, animation),
            );
          });
        }
      } catch (e) {
        Logger.e("删除服务器失败", _tag, e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除服务器失败: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AdaptiveAppBar(
        title: '服务器列表',
        actions: [
          IconButton(
            icon: Icon(ThemeManager().isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              Logger.d("切换主题模式: ${ThemeManager().isDarkMode ? '浅色' : '深色'}", _tag);
              ThemeManager().toggleTheme();
            },
            tooltip: '切换主题',
          )
        ],
      ),
      body: _servers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.computer_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无服务器',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _addServer(),
                    icon: const Icon(Icons.add),
                    label: const Text('添加服务器'),
                  ),
                ],
              ),
            )
          : AnimatedList(
              key: _listKey,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
                bottom: 8,
              ),
              initialItemCount: _servers.length,
              itemBuilder: (context, index, animation) {
                return _buildServerItem(_servers[index], animation);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addServer(),
        tooltip: '添加服务器',
        child: const Icon(Icons.add),
      ),
    );
  }
} 