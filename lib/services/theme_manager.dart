import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

class ThemeManager extends ChangeNotifier {
  static const String _tag = "ThemeManager";
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  
  ThemeManager._internal() {
    Logger.d("创建ThemeManager实例", _tag);
  }

  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  Future<void> init() async {
    Logger.i("初始化ThemeManager", _tag);
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
      Logger.d("主题模式初始化完成: ${_isDarkMode ? '深色' : '浅色'}", _tag);
      notifyListeners();
    } catch (e, stackTrace) {
      Logger.e("主题初始化失败", _tag, e, stackTrace);
      rethrow;
    }
  }

  Future<void> toggleTheme() async {
    Logger.i("切换主题模式", _tag);
    try {
      _isDarkMode = !_isDarkMode;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', _isDarkMode);
      Logger.i("主题已切换为: ${_isDarkMode ? '深色' : '浅色'}", _tag);
      notifyListeners();
    } catch (e, stackTrace) {
      Logger.e("切换主题失败", _tag, e, stackTrace);
      rethrow;
    }
  }
}