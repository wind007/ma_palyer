import 'package:flutter/material.dart';

/// 用于监听路由栈变化（例如从详情页返回首页）。
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
