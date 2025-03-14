// ignore_for_file: constant_identifier_names

import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class Logger {
  // 日志级别定义
  static const int VERBOSE = 0;
  static const int DEBUG = 1;
  static const int INFO = 2;
  static const int WARN = 3;
  static const int ERROR = 4;

  static int _minLevel = kDebugMode ? VERBOSE : INFO;
  static bool _includeTimestamp = true;

  // 设置最小日志级别
  static void setMinLevel(int level) {
    _minLevel = level;
  }

  // 启用/禁用时间戳
  static void setIncludeTimestamp(bool include) {
    _includeTimestamp = include;
  }

  // 获取日志级别名称
  static String _getLevelName(int level) {
    switch (level) {
      case VERBOSE:
        return 'V';
      case DEBUG:
        return 'D';
      case INFO:
        return 'I';
      case WARN:
        return 'W';
      case ERROR:
        return 'E';
      default:
        return '?';
    }
  }

  // 获取带颜色的日志级别标记
  static String _getColoredLevel(int level) {
    final levelName = _getLevelName(level);
    switch (level) {
      case VERBOSE:
        return '\x1B[37m$levelName\x1B[0m'; // 白色
      case DEBUG:
        return '\x1B[36m$levelName\x1B[0m'; // 青色
      case INFO:
        return '\x1B[32m$levelName\x1B[0m'; // 绿色
      case WARN:
        return '\x1B[33m$levelName\x1B[0m'; // 黄色
      case ERROR:
        return '\x1B[31m$levelName\x1B[0m'; // 红色
      default:
        return levelName;
    }
  }

  // 格式化日志消息
  static String _formatMessage(int level, String message, String? tag) {
    final buffer = StringBuffer();
    
    if (_includeTimestamp) {
      buffer.write('${DateTime.now().toString().split('.').first} ');
    }
    
    buffer.write('[${_getColoredLevel(level)}]');
    
    if (tag != null && tag.isNotEmpty) {
      buffer.write('[$tag]');
    }
    
    buffer.write(' $message');
    return buffer.toString();
  }

  // 记录日志的核心方法
  static void _log(int level, String message, String? tag, [Object? error, StackTrace? stackTrace]) {
    if (level < _minLevel) return;

    final formattedMessage = _formatMessage(level, message, tag);
    
    if (error != null) {
      developer.log(
        formattedMessage,
        time: DateTime.now(),
        error: error,
        stackTrace: stackTrace,
      );
    } else {
      developer.log(
        formattedMessage,
        time: DateTime.now(),
      );
    }
  }

  // 详细日志
  static void v(String message, [String? tag]) {
    _log(VERBOSE, message, tag);
  }

  // 调试日志
  static void d(String message, [String? tag]) {
    _log(DEBUG, message, tag);
  }

  // 信息日志
  static void i(String message, [String? tag]) {
    _log(INFO, message, tag);
  }

  // 警告日志
  static void w(String message, [String? tag, Object? error, StackTrace? stackTrace]) {
    _log(WARN, message, tag, error, stackTrace);
  }

  // 错误日志
  static void e(String message, [String? tag, Object? error, StackTrace? stackTrace]) {
    _log(ERROR, message, tag, error, stackTrace);
  }

  // 记录数据日志
  static void data(String message, Object data, [String? tag]) {
    if (_minLevel <= DEBUG) {
      _log(DEBUG, '$message: ${data.toString()}', tag);
    }
  }

  // 记录HTTP请求日志
  static void http(String method, String url, int statusCode, [String? body, String? tag]) {
    if (_minLevel <= DEBUG) {
      final message = 'HTTP $method $url [Status: $statusCode]${body != null ? '\nBody: $body' : ''}';
      _log(DEBUG, message, tag ?? 'HTTP');
    }
  }

  // 记录性能日志
  static void performance(String operation, int durationMs, [String? tag]) {
    if (_minLevel <= DEBUG) {
      _log(DEBUG, '$operation 耗时: ${durationMs}ms', tag ?? 'PERF');
    }
  }
} 