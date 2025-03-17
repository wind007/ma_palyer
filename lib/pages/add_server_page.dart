import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../utils/error_dialog.dart';
import '../utils/logger.dart';
import '../widgets/adaptive_app_bar.dart';

class AddServerPage extends StatefulWidget {
  const AddServerPage({super.key});

  @override
  State<AddServerPage> createState() => _AddServerPageState();
}

class _AddServerPageState extends State<AddServerPage> {
  static const String _tag = "AddServer";
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
    Logger.i("初始化添加服务器页面", _tag);
  }

  @override
  void dispose() {
    Logger.d("释放资源", _tag);
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

    Logger.i("开始添加服务器: ${_serverUrlController.text}", _tag);
    setState(() => _isLoading = true);

    try {
      Logger.d("创建API服务实例", _tag);
      final api = EmbyApiService(
        baseUrl: _serverUrlController.text,
        username: _usernameController.text,
        password: _passwordController.text,
      );

      // 先检查服务器连接状态并获取服务器信息
      Logger.d("获取服务器信息", _tag);
      final serverInfo = await api.getServerInfo();
      Logger.d("服务器信息获取成功: ${serverInfo['ServerName']}", _tag);
      
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
          : serverInfo['ServerName'] ?? '未知服务器';
      
      Logger.i("返回服务器信息: $serverName", _tag);
      // 返回服务器信息到上一页
      Navigator.of(context).pop({
        'url': _serverUrlController.text,
        'username': _usernameController.text,
        'password': _passwordController.text,
        'name': serverName,
        'accessToken': authResult['accessToken'],
        'userId': authResult['userInfo']['Id'],
      });
    } catch (e) {
      Logger.e("添加服务器失败", _tag, e);
      if (!mounted) {
        Logger.w("页面已卸载，取消错误处理", _tag);
        return;
      }
      
      final retry = await ErrorDialog.show(
        context: context,
        title: '登录失败',
        message: e.toString(),
      );

      if (retry && mounted) {
        Logger.i("重试添加服务器", _tag);
        _submitForm();
      } else {
        Logger.d("取消重试", _tag);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AdaptiveAppBar(
        title: '添加 Emby 服务器',
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16.0,
            MediaQuery.of(context).padding.top + kToolbarHeight + 16,
            16.0,
            16.0,
          ),
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
                  : const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}