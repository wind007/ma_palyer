import 'dart:io';
import 'package:flutter/material.dart';
import 'services/server_manager.dart';
import 'services/theme_manager.dart';
import 'pages/server_list_page.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'utils/http_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ServerManager().init();
  await ThemeManager().init();
  fvp.registerWith(options: {
    'player': {
      'buffer': '30000', // 播放缓冲时间(ms)
      'buffer.max': '16000000', // 最大缓冲大小(bytes)
      'buffer.packet': '2000', // 缓冲包数量
      'buffer.duration': '100000', // 缓冲时长(ms)
      'demux.buffer.ranges': '200', // 缓冲区间数量
      'preload': '1', // 启用预加载
      'lowLatency': '0', // 关闭低延迟以优化预加载
    },

    // 'buffer': 10000, // 5秒缓冲
    // 'timeout': 10000, // 10秒超时
    // 'network_timeout': 30000, // 30秒网络超时
    // 'reconnect': 3, // 断线重连3次
    // 'demux.buffer.ranges': '10', // 增加缓冲区间数量
    // //'lowLatency': 0, // 关闭低延迟模式以增加预加载
    // 'preload': 1, // 启用预加载
    // // 启用低延迟模式
    // 'lowLatency': 1,

    // // 配置视频解码器优先级
    // 'video.decoders': ['D3D11', 'NVDEC', 'FFmpeg'],
  });

  // 设置全局 HTTPS 证书验证
  HttpOverrides.global = TrustedHttpOverrides();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _themeManager = ThemeManager();

  @override
  void initState() {
    super.initState();
    _themeManager.addListener(() {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emby Client',
      themeMode: _themeManager.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const ServerListPage(),
    );
  }
}
