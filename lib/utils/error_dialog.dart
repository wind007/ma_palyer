import 'package:flutter/material.dart';

class ErrorDialog {
  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    String retryText = '重试',
    String backText = '返回上一页',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message.replaceAll('Exception: ', '')),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true); // 返回true表示重试
            },
            child: Text(retryText),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false); // 返回false表示不重试
            },
            child: Text(backText),
          ),
        ],
      ),
    );
    
    // 如果用户选择返回上一页
    if (result == false) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
    
    return result ?? false;
  }
} 