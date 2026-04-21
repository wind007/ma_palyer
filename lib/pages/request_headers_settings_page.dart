import 'package:flutter/material.dart';
import '../services/server_manager.dart';
import '../utils/logger.dart';
import '../widgets/adaptive_app_bar.dart';

class RequestHeadersSettingsPage extends StatefulWidget {
  const RequestHeadersSettingsPage({super.key});

  @override
  State<RequestHeadersSettingsPage> createState() => _RequestHeadersSettingsPageState();
}

class _RequestHeadersSettingsPageState extends State<RequestHeadersSettingsPage> {
  static const String _tag = "RequestHeadersSettings";
  final _manager = ServerManager();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _userAgentController;
  late final TextEditingController _embyClientController;
  late final TextEditingController _embyDeviceNameController;
  late final TextEditingController _embyDeviceIdController;
  late final TextEditingController _embyClientVersionController;
  late final TextEditingController _embyLanguageController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final customHeaders = _manager.customEmbyHeaders;
    _userAgentController = TextEditingController(text: _manager.customUserAgent ?? '');
    _embyClientController = TextEditingController(text: customHeaders['X-Emby-Client'] ?? '');
    _embyDeviceNameController = TextEditingController(text: customHeaders['X-Emby-Device-Name'] ?? '');
    _embyDeviceIdController = TextEditingController(text: customHeaders['X-Emby-Device-Id'] ?? '');
    _embyClientVersionController = TextEditingController(text: customHeaders['X-Emby-Client-Version'] ?? '');
    _embyLanguageController = TextEditingController(text: customHeaders['X-Emby-Language'] ?? '');
  }

  @override
  void dispose() {
    _userAgentController.dispose();
    _embyClientController.dispose();
    _embyDeviceNameController.dispose();
    _embyDeviceIdController.dispose();
    _embyClientVersionController.dispose();
    _embyLanguageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _manager.setCustomUserAgent(_userAgentController.text);
      await _manager.setCustomEmbyHeaders({
        'X-Emby-Client': _embyClientController.text,
        'X-Emby-Device-Name': _embyDeviceNameController.text,
        'X-Emby-Device-Id': _embyDeviceIdController.text,
        'X-Emby-Client-Version': _embyClientVersionController.text,
        'X-Emby-Language': _embyLanguageController.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请求头设置已保存')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      Logger.e('保存请求头设置失败', _tag, e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetToDefault() async {
    setState(() {
      _userAgentController.clear();
      _embyClientController.clear();
      _embyDeviceNameController.clear();
      _embyDeviceIdController.clear();
      _embyClientVersionController.clear();
      _embyLanguageController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AdaptiveAppBar(
        title: '请求头设置',
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: '恢复默认',
            onPressed: _resetToDefault,
          ),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            tooltip: '保存',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.of(context).padding.top + kToolbarHeight + 16,
            16,
            24,
          ),
          children: [
            const Text('留空表示使用默认值', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            _buildField(_userAgentController, 'User-Agent', '例如: ma_player/1.0.0'),
            const SizedBox(height: 12),
            _buildField(_embyClientController, 'X-Emby-Client', ServerManager.defaultEmbyHeaders['X-Emby-Client']!),
            const SizedBox(height: 12),
            _buildField(_embyDeviceNameController, 'X-Emby-Device-Name', ServerManager.defaultEmbyHeaders['X-Emby-Device-Name']!),
            const SizedBox(height: 12),
            _buildField(_embyDeviceIdController, 'X-Emby-Device-Id', ServerManager.defaultEmbyHeaders['X-Emby-Device-Id']!),
            const SizedBox(height: 12),
            _buildField(_embyClientVersionController, 'X-Emby-Client-Version', ServerManager.defaultEmbyHeaders['X-Emby-Client-Version']!),
            const SizedBox(height: 12),
            _buildField(_embyLanguageController, 'X-Emby-Language', ServerManager.defaultEmbyHeaders['X-Emby-Language']!),
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, String hint) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
