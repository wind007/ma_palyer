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
    // 'player': {
    //   'buffer': '10000',
    //   'buffer.range': '2000,60000', // 最小2秒，最大60秒的缓冲
    //   'buffer.max': '536870912', // 512MB 缓冲上限
    //   'buffer.packet': '8000', // 缓存包数量
    //   'timeout': '30000',
    //   'demux.buffer': '1', // 启用 demuxer 缓存
    //   'demux.buffer.ranges': '20', // 增加到20个缓存区间以提升预加载效果
    //   'demux.buffer.size': '33554432', // 32MB demuxer缓存大小
    //   'demux.buffer.protocols': 'http,https', // 指定启用缓存的协议
    //   'event': 'cache.ranges,buffer.progress,buffer.time', // 启用缓存相关事件
    //   'buffer.drop': '0', // 禁止丢弃过时的数据包
    // },
    // 'global': {
    //   'avformat.fflags': 'nobuffer', // 禁用 FFmpeg 内部缓冲
    //   'avformat.analyzeduration': '100000000',
    //   'avformat.probesize': '100000000',
    //   'avformat.thread_queue_size': '102400',
    //   'video.decoders': ['D3D11', 'DXVA', 'FFmpeg'],
    //   'demuxer.max_errors': '100', // 允许更多错误继续播放
    // },
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
