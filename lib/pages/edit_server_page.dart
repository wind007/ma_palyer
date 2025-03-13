import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../utils/logger.dart';

class EditServerPage extends StatefulWidget {
  final ServerInfo server;

  const EditServerPage({super.key, required this.server});

  @override
  State<EditServerPage> createState() => _EditServerPageState();
}

class _EditServerPageState extends State<EditServerPage> {
  static const String _tag = "EditServer";
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverNameController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    Logger.i("初始化编辑服务器页面: ${widget.server.name}", _tag);
    // 预填充服务器信息
    _serverUrlController.text = widget.server.url;
    _usernameController.text = widget.server.username;
    _passwordController.text = widget.server.password;
    _serverNameController.text = widget.server.name;
  }

  @override
  void dispose() {
    Logger.d("释放编辑服务器页面资源", _tag);
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _serverNameController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      Logger.w("表单验证失败", _tag);
      return;
    }

    Logger.i("开始更新服务器: ${widget.server.name}", _tag);
    setState(() => _isLoading = true);

    try {
      Logger.d("创建API服务实例", _tag);
      final api = EmbyApiService(
        baseUrl: _serverUrlController.text,
        username: _usernameController.text,
        password: _passwordController.text,
      );

      // 先检查服务器连接状态
      Logger.d("检查服务器连接状态", _tag);
      final isConnected = await api.checkServerConnection();
      if (!isConnected) {
        Logger.e("服务器连接失败", _tag);
        throw Exception('无法连接到服务器，请检查服务器地址是否正确');
      }
      Logger.d("服务器连接成功", _tag);

      // 进行身份验证
      Logger.d("开始身份验证", _tag);
      final authResult = await api.authenticate();
      Logger.i("身份验证成功: ${authResult['userInfo']['Name']}", _tag);

      if (!mounted) {
        Logger.w("页面已卸载，取消后续操作", _tag);
        return;
      }

      final serverName = _serverNameController.text.isNotEmpty
          ? _serverNameController.text
          : authResult['serverInfo']['ServerName'] ?? '新服务器';

      Logger.i("返回更新后的服务器信息: $serverName", _tag);
      // 返回更新后的服务器信息到上一页
      Navigator.of(context).pop({
        'url': _serverUrlController.text,
        'username': _usernameController.text,
        'password': _passwordController.text,
        'name': serverName,
        'accessToken': authResult['accessToken'],
        'userId': authResult['userInfo']['Id'],
      });
    } catch (e) {
      Logger.e("更新服务器失败", _tag, e);
      if (!mounted) {
        Logger.w("页面已卸载，取消错误处理", _tag);
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('更新失败'),
          content: Text(e.toString().replaceAll('Exception: ', '')),
          actions: [
            TextButton(
              onPressed: () {
                Logger.d("用户选择重试", _tag);
                Navigator.of(context).pop(); // 关闭对话框
              },
              child: const Text('重试'),
            ),
            TextButton(
              onPressed: () {
                Logger.d("用户选择返回上一页", _tag);
                Navigator.of(context).pop(); // 关闭对话框
                Navigator.of(context).pop(); // 返回上一页
              },
              child: const Text('返回上一页'),
            ),
          ],
        ),
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
                  Logger.w("服务器地址为空", _tag);
                  return '请输入服务器地址';
                }
                if (!value.startsWith('http://') && !value.startsWith('https://')) {
                  Logger.w("服务器地址格式错误: $value", _tag);
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
                  Logger.w("用户名为空", _tag);
                  return '请输入用户名';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    Logger.v("切换密码显示状态", _tag);
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  Logger.w("密码为空", _tag);
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