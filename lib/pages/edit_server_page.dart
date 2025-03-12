import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';

class EditServerPage extends StatefulWidget {
  final ServerInfo server;

  const EditServerPage({super.key, required this.server});

  @override
  State<EditServerPage> createState() => _EditServerPageState();
}

class _EditServerPageState extends State<EditServerPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverNameController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 预填充服务器信息
    _serverUrlController.text = widget.server.url;
    _usernameController.text = widget.server.username;
    _passwordController.text = widget.server.password;
    _serverNameController.text = widget.server.name;
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _serverNameController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final api = EmbyApiService(
        baseUrl: _serverUrlController.text,
        username: _usernameController.text,
        password: _passwordController.text,
      );

      // 先检查服务器连接状态
      final isConnected = await api.checkServerConnection();
      if (!isConnected) {
        throw Exception('无法连接到服务器，请检查服务器地址是否正确');
      }

      // 进行身份验证
      final authResult = await api.authenticate();

      if (!mounted) return;

      // 返回更新后的服务器信息到上一页
      Navigator.of(context).pop({
        'url': _serverUrlController.text,
        'username': _usernameController.text,
        'password': _passwordController.text,
        'name': _serverNameController.text.isNotEmpty
            ? _serverNameController.text
            : authResult['serverInfo']['ServerName'] ?? '新服务器',
        'accessToken': authResult['accessToken'],
        'userId': authResult['userInfo']['Id'],
      });
    } catch (e) {
      if (!mounted) return;
      print('$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑服务器'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _serverUrlController,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'http://your-server:8096',
                prefixIcon: Icon(Icons.computer),
              ),
              keyboardType: TextInputType.url,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入服务器地址';
                }
                if (!value.startsWith('http://') && !value.startsWith('https://')) {
                  return '服务器地址必须以 http:// 或 https:// 开头';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入用户名';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: '密码',
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入密码';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _serverNameController,
              decoration: const InputDecoration(
                labelText: '服务器名称（可选）',
                prefixIcon: Icon(Icons.drive_file_rename_outline),
                hintText: '留空将使用服务器默认名称',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitForm,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}