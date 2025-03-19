import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/server_manager.dart';
import 'services/theme_manager.dart';
import 'pages/server_list_page.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'utils/http_client.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';

void main() async {
  
  Logger.root.level = Level.ALL;
  final df = DateFormat("HH:mm:ss.SSS");
  Logger.root.onRecord.listen((record) {
    debugPrint(
        '${record.loggerName}.${record.level.name}: ${df.format(record.time)}: ${record.message}',
        wrapWidth: 0x7FFFFFFFFFFFFFFF);
  });

  WidgetsFlutterBinding.ensureInitialized();
  
  // 允许应用自动跟随系统横竖屏
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  await ServerManager().init();
  await ThemeManager().init();
  fvp.registerWith(options: {
     'player' :{
      'buffer.range' : '2000+20000',
      'demux.buffer.ranges':'1',

     }
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
