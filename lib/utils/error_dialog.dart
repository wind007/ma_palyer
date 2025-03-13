import 'package:flutter/material.dart';
import 'logger.dart';

class ErrorDialog {
  static const String _tag = "ErrorDialog";

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    String retryText = '重试',
    String closeText = '关闭',
  }) async {
    Logger.w("显示错误对话框 - 标题: $title, 消息: $message", _tag);
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message.replaceAll('Exception: ', '')),
        actions: [
          TextButton(
            onPressed: () {
              Logger.d("用户选择重试", _tag);
              Navigator.of(context).pop(true); // 返回true表示重试
            },
            child: Text(retryText),
          ),
          TextButton(
            onPressed: () {
              Logger.d("用户选择关闭", _tag);
              Navigator.of(context).pop(false); // 返回false表示不重试
            },
            child: Text(closeText),
          ),
        ],
      ),
    );
    
    final finalResult = result ?? false;
    Logger.d("错误对话框结果: ${finalResult ? '重试' : '关闭'}", _tag);
    return finalResult;
  }
} 