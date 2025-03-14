import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'logger.dart';

class TrustedHttpOverrides extends HttpOverrides {
  static const String _tag = "TrustedHttpOverrides";

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    Logger.d("创建忽略证书验证的 HttpClient", _tag);
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        Logger.d("忽略证书验证: $host:$port", _tag);
        return true;
      };
  }
}

class HttpClientFactory {
  static const String _tag = "HttpClientFactory";
  static HttpClient? _httpClient;
  static http.Client? _client;

  static HttpClient getHttpClient() {
    if (_httpClient == null) {
      _httpClient = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) {
          Logger.d("跳过证书验证: $host:$port", _tag);
          return true;
        };
      Logger.i("创建支持自签名证书的HttpClient", _tag);
    }
    return _httpClient!;
  }

  static http.Client getClient() {
    if (_client == null) {
      _client = IOClient(getHttpClient());
      Logger.i("创建支持自签名证书的http.Client", _tag);
    }
    return _client!;
  }

  static void closeClient() {
    _client?.close();
    _client = null;
    _httpClient = null;
    Logger.i("关闭并清理 HTTP 客户端", _tag);
  }
} 