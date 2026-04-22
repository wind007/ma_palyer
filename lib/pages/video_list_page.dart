import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../services/api_service_manager.dart';
import './video_detail_page.dart';
import './tv_show_detail_page.dart';
import './video_search_page.dart';
import '../utils/logger.dart';
import './video_list_more_page.dart';
import '../widgets/video_card.dart';
import '../widgets/adaptive_app_bar.dart';
import '../app_route_observer.dart';

class VideoListPage extends StatefulWidget {
  final ServerInfo server;

  const VideoListPage({super.key, required this.server});

  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage>
    with RouteAware, SingleTickerProviderStateMixin {
  static const String _tag = "VideoList";
  static const String _genrePreviewCachePrefix = 'genre_preview_cache_v1';
  // 与首页普通视频卡片保持一致的视觉尺寸
  static const double _genreSectionHeight = 240;
  static const double _genreCardWidth = 130;
  static const double _genreMetaAreaHeight = 40;
  static const double _genreCardGap = 4;
  late final EmbyApiService _api;
  bool _routeAwareSubscribed = false;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _shimmerController;
  final Random _random = Random();
  
  // 分区数据
  final Map<String, List<dynamic>> _videoSections = {
    'latest': [], // 最新添加
    'continue': [], // 继续观看
    'favorites': [], // 收藏
    'genres': [], // 分类
    'views': [], // 媒体库视图
  };
  
  // 分区加载状态
  final Map<String, bool> _isLoadingMore = {};
  final Map<String, bool> _hasMoreData = {};
  final Map<String, int> _sectionStartIndexes = {};
  final Map<String, Map<String, dynamic>> _genrePreviewItems = {};
  // 为每个部分创建独立的滚动控制器
  final Map<String, ScrollController> _sectionScrollControllers = {};
  static const int _pageSize = 10;
  
  // 分区加载状态
  final Map<String, bool> _sectionLoading = {
    'latest': true,
    'continue': true,
    'favorites': true,
    'genres': true,
    'views': true,
  };

  bool _isInitializing = true;
  String? _error;
  bool _hadSectionLoadError = false;

  @override
  void initState() {
    super.initState();
    Logger.i("初始化视频列表页面: ${widget.server.name}", _tag);
    _initializeApi();

    // 初始化闪烁动画控制器
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_routeAwareSubscribed) {
      final route = ModalRoute.of(context);
      if (route is PageRoute<dynamic>) {
        appRouteObserver.subscribe(this, route);
        _routeAwareSubscribed = true;
      }
    }
  }

  @override
  void didPopNext() {
    if (_isInitializing || _error != null) return;
    Logger.i('从子页面返回首页，仅刷新继续观看', _tag);
    _loadContinueWatching();
  }

  @override
  void dispose() {
    if (_routeAwareSubscribed) {
      appRouteObserver.unsubscribe(this);
      _routeAwareSubscribed = false;
    }
    Logger.d("释放视频列表页面资源", _tag);
    _scrollController.dispose();
    _shimmerController.dispose();
    // 释放所有部分的滚动控制器
    for (var controller in _sectionScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeApi() async {
    try {
      Logger.d("初始化 API 服务", _tag);
      _api = await ApiServiceManager().initializeEmbyApi(widget.server);
      _loadAllSections();
    } catch (e) {
      Logger.e("API 初始化失败", _tag, e);
      setState(() {
        _error = '初始化失败: $e';
        _isInitializing = false;
      });
    }
  }

  Future<void> _loadAllSections() async {
    Logger.i("开始并行加载所有分区数据", _tag);
    
    // 重置所有分区的加载状态
    setState(() {
      _hadSectionLoadError = false;
      for (var key in _sectionLoading.keys) {
        _sectionLoading[key] = true;
      }
      _isInitializing = false;
    });

    try {
      // 并行加载所有分区
      await Future.wait([
        _loadViews(),
        _loadLatestItems(),
        _loadContinueWatching(),
        _loadFavorites(),
        _loadGenres(),
      ]);

      Logger.i("所有分区数据加载完成", _tag);
    } catch (e) {
      Logger.e("部分分区加载失败", _tag, e);
      if (mounted) {
        setState(() {
          _hadSectionLoadError = true;
        });
      }
      // 错误处理移到各个加载方法中，这里不再统一处理
    }
  }

  Future<void> _loadViews() async {
    try {
      Logger.d("获取用户媒体库视图", _tag);
      final response = await _api.getUserViews(widget.server);
      final views = (response).where((view) {
        final type = view['CollectionType']?.toString().toLowerCase();
        return type != null;
      }).toList();
      
      if (!mounted) return;
      
      Logger.d("找到 ${views.length} 个媒体库视图", _tag);
      setState(() {
        _videoSections['views'] = views;
        _sectionLoading['views'] = false;
      });
      
      // 并行加载每个视图的内容
      Logger.d("开始并行加载各视图内容", _tag);
      await Future.wait(
        views.map((view) => _loadViewContent(view)).toList(),
      );
    } catch (e) {
      Logger.e("加载媒体库视图失败", _tag, e);
      if (!mounted) return;
      setState(() {
        _hadSectionLoadError = true;
        _videoSections['views'] = [];
        _sectionLoading['views'] = false;
      });
    }
  }

  Future<void> _loadViewContent(Map<String, dynamic> view) async {
    try {
      final viewId = view['Id'];
      Logger.d("加载视图内容: ${view['Name']}", _tag);
      
      // 初始化分页状态
      _isLoadingMore[viewId] = false;
      _hasMoreData[viewId] = true;
      _sectionStartIndexes[viewId] = 0;
      
      final response = await _api.getVideos(
        parentId: viewId,
        startIndex: 0,
        limit: _pageSize,
        sortBy: 'DateCreated',
        sortOrder: 'Descending',
      );
      
      if (mounted) {
        Logger.d("视图 ${view['Name']} 加载完成，获取到 ${(response['Items'] as List).length} 个项目", _tag);
        setState(() {
          _videoSections[viewId] = response['Items'] as List;
          _hasMoreData[viewId] = (response['Items'] as List).length >= _pageSize;
          _sectionStartIndexes[viewId] = _pageSize;
        });
      }
    } catch (e) {
      Logger.e("加载视图内容失败: ${view['Name']}", _tag);
      if (mounted) {
        setState(() {
          _videoSections[view['Id']] = [];
          _hasMoreData[view['Id']] = false;
        });
      }
    }
  }

  Future<void> _loadLatestItems() async {
    try {
      Logger.d("加载最新添加项目", _tag);
      _isLoadingMore['latest'] = false;
      _hasMoreData['latest'] = true;
      _sectionStartIndexes['latest'] = 0;
      
      final response = await _api.getLatestItems(
        startIndex: 0,
        limit: _pageSize,
      );
      
      if (!mounted) return;

      final items = response['Items'] as List;
      final totalCount = response['TotalRecordCount'] as int;
      
      Logger.d("最新添加项目加载完成，获取到 ${items.length} 个项目", _tag);
      setState(() {
        _videoSections['latest'] = items;
        _hasMoreData['latest'] = items.length < totalCount;
        _sectionStartIndexes['latest'] = items.length;
        _sectionLoading['latest'] = false;
      });
    } catch (e) {
      Logger.e("加载最新添加项目失败", _tag, e);
      if (!mounted) return;
      setState(() {
        _hadSectionLoadError = true;
        _videoSections['latest'] = [];
        _hasMoreData['latest'] = false;
        _sectionLoading['latest'] = false;
      });
    }
  }

  Future<void> _loadContinueWatching() async {
    if (mounted) {
      setState(() {
        _sectionLoading['continue'] = true;
      });
    }
    try {
      Logger.d("加载继续观看项目", _tag);
      _isLoadingMore['continue'] = false;
      _hasMoreData['continue'] = true;
      _sectionStartIndexes['continue'] = 0;
      
      final response = await _api.getResumeItems(
        startIndex: 0,
        limit: _pageSize,
        includeItemTypes: 'Movie,Episode,Series',
      );

      if (!mounted) return;

      final items = response['Items'] as List;
      final totalCount = response['TotalRecordCount'] as int? ?? items.length;
      
      Logger.d("继续观看项目加载完成，获取到 ${items.length} 个项目", _tag);
      setState(() {
        _videoSections['continue'] = items;
        _hasMoreData['continue'] = (_sectionStartIndexes['continue'] ?? 0) + items.length < totalCount;
        _sectionStartIndexes['continue'] = _pageSize;
        _sectionLoading['continue'] = false;
      });
    } catch (e) {
      Logger.e("加载继续观看项目失败", _tag, e);
      if (!mounted) return;
      setState(() {
        _hadSectionLoadError = true;
        _videoSections['continue'] = [];
        _hasMoreData['continue'] = false;
        _sectionLoading['continue'] = false;
      });
    }
  }

  Future<void> _loadFavorites() async {
    try {
      Logger.d("加载收藏项目", _tag);
      _isLoadingMore['favorites'] = false;
      _hasMoreData['favorites'] = true;
      _sectionStartIndexes['favorites'] = 0;
      
      final response = await _api.getVideos(
        startIndex: 0,
        limit: _pageSize,
        sortBy: 'SortName',
        sortOrder: 'Ascending',
        filters: 'Filters=IsFavorite',
        fields: 'BasicSyncInfo',
        includeItemTypes: 'Movie,Series'
      );
      
      if (!mounted) return;
      
      Logger.d("收藏项目加载完成，获取到 ${(response['Items'] as List).length} 个项目", _tag);
      setState(() {
        _videoSections['favorites'] = response['Items'] as List;
        _hasMoreData['favorites'] = (response['Items'] as List).length >= _pageSize;
        _sectionStartIndexes['favorites'] = _pageSize;
        _sectionLoading['favorites'] = false;
      });
    } catch (e) {
      Logger.e("加载收藏项目失败", _tag, e);
      if (!mounted) return;
      setState(() {
        _hadSectionLoadError = true;
        _videoSections['favorites'] = [];
        _hasMoreData['favorites'] = false;
        _sectionLoading['favorites'] = false;
      });
    }
  }

  Future<void> _loadGenres() async {
    try {
      Logger.d("加载分类项目", _tag);
      final response = await _api.getGenres(limit: 40);
      if (!mounted) return;

      final items = (response['Items'] as List<dynamic>? ?? const <dynamic>[])
          .where((genre) => genre is Map<String, dynamic> && (genre['Name']?.toString().isNotEmpty ?? false))
          .toList();

      setState(() {
        _videoSections['genres'] = items;
        _sectionLoading['genres'] = false;
      });
      await _loadGenrePreviewItems(items);
    } catch (e) {
      Logger.e("加载分类项目失败", _tag, e);
      if (!mounted) return;
      setState(() {
        _hadSectionLoadError = true;
        _videoSections['genres'] = [];
        _sectionLoading['genres'] = false;
      });
    }
  }

  Future<void> _loadGenrePreviewItems(List<dynamic> genres) async {
    final cachedPreviewMap = await _loadGenrePreviewCache();
    final currentGenreIds = genres
        .whereType<Map<String, dynamic>>()
        .map((genre) => genre['Id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final previewMap = <String, Map<String, dynamic>>{
      for (final entry in cachedPreviewMap.entries)
        if (currentGenreIds.contains(entry.key)) entry.key: entry.value,
    };
    if (mounted) {
      setState(() {
        _genrePreviewItems
          ..clear()
          ..addAll(previewMap);
      });
    }

    final updatedCacheMap = <String, Map<String, dynamic>>{
      ...cachedPreviewMap,
    };
    bool hasCacheUpdate = false;

    // 风险收敛：限制总请求量，避免分类缩略图引发突发并发请求。
    final sampledGenres = genres.take(12);
    for (final genre in sampledGenres) {
      if (genre is! Map<String, dynamic>) continue;
      final genreId = genre['Id']?.toString();
      if (genreId == null || genreId.isEmpty) continue;
      if (previewMap.containsKey(genreId)) continue;
      try {
        final response = await _api.getVideos(
          startIndex: 0,
          limit: 12,
          includeItemTypes: 'Movie',
          sortBy: 'DateCreated',
          sortOrder: 'Descending',
          genreIds: genreId,
        );
        final items = response['Items'] as List<dynamic>? ?? const <dynamic>[];
        final candidates = items
            .where((item) => item is Map<String, dynamic> && item['Id'] != null)
            .cast<Map<String, dynamic>>()
            .toList();
        if (candidates.isEmpty) continue;
        final previewItem = candidates[_random.nextInt(candidates.length)];
        previewMap[genreId] = previewItem;
        updatedCacheMap[genreId] = previewItem;
        hasCacheUpdate = true;
      } catch (e) {
        Logger.w('加载分类缩略图失败: genreId=$genreId, error=$e', _tag);
      }
      // 轻微退避，减少短时请求密度。
      await Future.delayed(const Duration(milliseconds: 80));
    }
    if (!mounted) return;
    setState(() {
      _genrePreviewItems
        ..clear()
        ..addAll(previewMap);
    });

    if (hasCacheUpdate) {
      await _saveGenrePreviewCache(updatedCacheMap);
    }
  }

  String get _genrePreviewCacheKey {
    final serverFingerprint = '${widget.server.url}|${widget.server.userId}';
    return '$_genrePreviewCachePrefix:${serverFingerprint.hashCode}';
  }

  Future<Map<String, Map<String, dynamic>>> _loadGenrePreviewCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_genrePreviewCacheKey);
      if (raw == null || raw.isEmpty) {
        return <String, Map<String, dynamic>>{};
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return <String, Map<String, dynamic>>{};
      }
      final result = <String, Map<String, dynamic>>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          result[entry.key] = value;
        } else if (value is Map) {
          result[entry.key] = value.map(
            (k, v) => MapEntry(k.toString(), v),
          );
        }
      }
      return result;
    } catch (e) {
      Logger.w('读取分类缩略图缓存失败: $e', _tag);
      return <String, Map<String, dynamic>>{};
    }
  }

  Future<void> _saveGenrePreviewCache(
    Map<String, Map<String, dynamic>> cacheMap,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(cacheMap);
      await prefs.setString(_genrePreviewCacheKey, encoded);
    } catch (e) {
      Logger.w('保存分类缩略图缓存失败: $e', _tag);
    }
  }

  Future<void> _loadMoreForSection(String sectionId) async {
    if (_isLoadingMore[sectionId] == true || _hasMoreData[sectionId] != true) {
      Logger.d(
        '跳过加载更多: sectionId=$sectionId, '
        'isLoading=${_isLoadingMore[sectionId]}, '
        'hasMore=${_hasMoreData[sectionId]}',
        _tag
      );
      return;
    }

    Logger.d(
      "开始加载更多内容: sectionId=$sectionId, "
      "startIndex=${_sectionStartIndexes[sectionId]}, "
      "currentItems=${_videoSections[sectionId]?.length}",
      _tag
    );

    setState(() => _isLoadingMore[sectionId] = true);

    try {
      dynamic response;
      List<dynamic> newItems = [];
      int totalCount = 0;
      final startIndex = _sectionStartIndexes[sectionId] ?? 0;
      
      if (sectionId == 'latest') {
        response = await _api.getLatestItems(
          startIndex: startIndex,
          limit: _pageSize,
        );
        newItems = response['Items'] as List;
        totalCount = response['TotalRecordCount'] as int;
      } else if (sectionId == 'continue') {
        response = await _api.getResumeItems(
          startIndex: startIndex,
          limit: _pageSize,
          includeItemTypes: 'Movie,Episode,Series',
        );
        newItems = response['Items'] as List;
        totalCount = response['TotalRecordCount'] as int;
      } else if (sectionId == 'favorites') {
        response = await _api.getVideos(
          startIndex: startIndex,
          limit: _pageSize,
          sortBy: 'SortName',
          sortOrder: 'Ascending',
          filters: 'Filters=IsFavorite',
          fields: 'BasicSyncInfo',
          includeItemTypes: 'Movie,Series'
        );
        newItems = response['Items'] as List;
        totalCount = response['TotalRecordCount'] as int;
      } else {
        // 视图内容加载
        response = await _api.getVideos(
          parentId: sectionId,
          startIndex: startIndex,
          limit: _pageSize,
          sortBy: 'DateCreated',
          sortOrder: 'Descending',
        );
        newItems = response['Items'] as List;
        totalCount = response['TotalRecordCount'] as int;
      }

      if (mounted) {
        setState(() {
          // 添加新项目到列表
          if (_videoSections[sectionId] != null) {
            _videoSections[sectionId] = [..._videoSections[sectionId]!, ...newItems];
            
            // 更新起始索引
            _sectionStartIndexes[sectionId] = startIndex + newItems.length;
            
            // 更准确地检查是否还有更多数据
            _hasMoreData[sectionId] = _videoSections[sectionId]!.length < totalCount;
          }
          
          // 重置加载状态
          _isLoadingMore[sectionId] = false;

          Logger.d(
            '加载更多完成: sectionId=$sectionId, '
            'newItems=${newItems.length}, '
            'totalItems=${_videoSections[sectionId]?.length}, '
            'totalCount=$totalCount, '
            'hasMore=${_hasMoreData[sectionId]}, '
            'nextStartIndex=${_sectionStartIndexes[sectionId]}',
            _tag
          );
        });
      }
    } catch (e) {
      Logger.e("加载更多内容失败: $sectionId", _tag, e);
      if (mounted) {
        setState(() => _isLoadingMore[sectionId] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载更多失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          AdaptiveAppBar(
            title: widget.server.name,
            scrollController: _scrollController,
            floating: true,
            snap: true,
            pinned: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VideoSearchPage(
                        server: widget.server,
                        api: _api,
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _loadAllSections(),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isInitializing) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: textTheme.bodyLarge?.copyWith(color: colorScheme.error),
          textAlign: TextAlign.center,
        ),
      );
    }

    final hasAnyData = _videoSections.values.any((items) => items.isNotEmpty);
    final isAnySectionLoading = _sectionLoading.values.any((loading) => loading);
    if (!hasAnyData && !isAnySectionLoading && _hadSectionLoadError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 64,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                '服务器连接失败',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请检查网络、服务器地址或账号状态后重试。',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    onPressed: _loadAllSections,
                    child: const Text('重试'),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回服务器列表'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllSections,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分类区域
          if (_sectionLoading['genres'] == true)
            _buildSkeletonSectionWidget('分类')
          else if (_videoSections['genres']?.isNotEmpty ?? false)
            _buildGenreSectionWidget(_videoSections['genres']!),

          // 继续观看区域
          if (_sectionLoading['continue'] == true)
            _buildSkeletonSectionWidget('继续观看')
          else if (_videoSections['continue']?.isNotEmpty ?? false)
            _buildSectionWidget('继续观看', _videoSections['continue']!),
          
          // 最新添加区域
          if (_sectionLoading['latest'] == true)
            _buildSkeletonSectionWidget('最新添加')
          else if (_videoSections['latest']?.isNotEmpty ?? false)
            _buildSectionWidget('最新添加', _videoSections['latest']!),
          
          // 收藏区域
          if (_sectionLoading['favorites'] == true)
            _buildSkeletonSectionWidget('我的收藏')
          else if (_videoSections['favorites']?.isNotEmpty ?? false)
            _buildSectionWidget('我的收藏', _videoSections['favorites']!),
          
          // 媒体库视图区域
          ..._buildViewSectionsWidgets(),
        ],
      ),
    );
  }

  Widget _buildSectionWidget(String title, List<dynamic> items, {String? viewId, bool isMovieView = false}) {
    final sectionId = viewId ?? title.toLowerCase();
    final bool isLoading = _isLoadingMore[sectionId] ?? false;
    final bool hasMore = _hasMoreData[sectionId] ?? false;
    final scrollController = _getScrollController(sectionId);

    if (_sectionLoading[title.toLowerCase()] == true) {
      return _buildSkeletonSectionWidget(title);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (viewId != null)
                TextButton(
                  onPressed: () => _navigateToMorePage(viewId, title, isMovieView),
                  child: const Text('查看更多'),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 240,
          child: NotificationListener<ScrollNotification>(
            onNotification: (scrollInfo) {
              if (scrollInfo is ScrollUpdateNotification) {
                final maxScroll = scrollInfo.metrics.maxScrollExtent;
                final currentScroll = scrollInfo.metrics.pixels;
                const threshold = 100.0;
                
                if (!isLoading && 
                    hasMore && 
                    maxScroll > 0 &&
                    (maxScroll - currentScroll) <= threshold) {
                  _loadMoreForSection(sectionId);
                }
              }
              return false;
            },
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                },
                scrollbars: false,
              ),
              child: ListView.builder(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: items.length + (hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == items.length) {
                    return _buildLoadingIndicator();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _buildVideoCard(items[index]),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenreSectionWidget(List<dynamic> genres) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            '分类',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        SizedBox(
          height: _genreSectionHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final genre = genres[index] as Map<String, dynamic>;
              final genreName = genre['Name']?.toString() ?? '未知分类';
              final genreId = genre['Id']?.toString();
              final previewItem = genreId == null ? null : _genrePreviewItems[genreId];
              return _buildGenreThumbnailCard(
                genreName: genreName,
                genreId: genreId,
                previewItem: previewItem,
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemCount: genres.length,
          ),
        ),
      ],
    );
  }

  Widget _buildGenreThumbnailCard({
    required String genreName,
    required String? genreId,
    required Map<String, dynamic>? previewItem,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = _buildGenrePreviewImageUrl(previewItem);
    final disabled = genreId == null || genreId.isEmpty;
    const imageHeight = _genreSectionHeight - _genreMetaAreaHeight - _genreCardGap;
    return SizedBox(
      width: _genreCardWidth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: disabled ? null : () => _openGenrePage(genreId, genreName),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: imageHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl != null)
                        Image.network(
                          imageUrl,
                          headers: {
                            'User-Agent': ServerManager.effectiveUserAgent,
                            'X-Emby-Token': widget.server.accessToken,
                          },
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildGenrePlaceholder(colorScheme),
                        )
                      else
                        _buildGenrePlaceholder(colorScheme),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withAlpha(170),
                            ],
                            stops: const [0.45, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: _genreCardGap),
              SizedBox(
                height: _genreMetaAreaHeight,
                child: Text(
                  genreName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.3,
                        letterSpacing: 0.3,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                  strutStyle: const StrutStyle(
                    forceStrutHeight: true,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenrePlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.local_movies_outlined,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  String? _buildGenrePreviewImageUrl(Map<String, dynamic>? item) {
    if (item == null) return null;
    final itemId = item['Id']?.toString();
    if (itemId == null || itemId.isEmpty) return null;
    final imageTags = item['ImageTags'] as Map<String, dynamic>?;
    final primaryTag = imageTags?['Primary']?.toString();
    if (primaryTag != null && primaryTag.isNotEmpty) {
      return _api.getImageUrl(
        itemId: itemId,
        imageType: 'Primary',
        width: 280,
        height: 400,
        quality: 75,
        tag: primaryTag,
      );
    }
    final thumbTag = imageTags?['Thumb']?.toString();
    if (thumbTag != null && thumbTag.isNotEmpty) {
      return _api.getImageUrl(
        itemId: itemId,
        imageType: 'Thumb',
        width: 280,
        height: 400,
        quality: 75,
        tag: thumbTag,
      );
    }
    return null;
  }

  void _openGenrePage(String genreId, String genreName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoListMorePage(
          server: widget.server,
          title: '分类: $genreName',
          genreId: genreId,
          isMovieView: false,
        ),
      ),
    );
  }

  void _navigateToMorePage(String viewId, String title, bool isMovieView) {
    final view = _videoSections['views']!.firstWhere(
      (v) => v['Id'] == viewId,
      orElse: () => {},
    );
    final type = view['Type']?.toString().toLowerCase();
    final collectionType = view['CollectionType']?.toString().toLowerCase();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoListMorePage(
          server: widget.server,
          title: title,
          viewId: viewId,
          parentId: viewId,
          isMovieView: isMovieView || type == 'boxset' || collectionType == 'movies',
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '加载中...',
            style: (textTheme.bodySmall ?? textTheme.bodyMedium!).copyWith(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildViewSectionsWidgets() {
    if (_sectionLoading['views'] == true) {
      return List.generate(2, (index) => _buildSkeletonSectionWidget('加载中...'));
    }

    return (_videoSections['views'] ?? []).map<Widget>((view) {
      final viewId = view['Id'];
      if (viewId == null) return const SizedBox.shrink();
      
      final viewName = view['Name'] as String? ?? '未知视图';
      final items = _videoSections[viewId] ?? [];
      final isMovieView = view['CollectionType']?.toString().toLowerCase() == 'movies';
      
      if (_sectionLoading[viewId] == true) {
        return _buildSkeletonSectionWidget(viewName);
      }
      
      return _buildSectionWidget(
        viewName,
        items,
        viewId: viewId,
        isMovieView: isMovieView,
      );
    }).toList();
  }

  ScrollController _getScrollController(String sectionId) {
    if (!_sectionScrollControllers.containsKey(sectionId)) {
      _sectionScrollControllers[sectionId] = ScrollController();
    }
    return _sectionScrollControllers[sectionId]!;
  }

  Widget _buildSkeletonSectionWidget(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = colorScheme.surfaceContainerHighest;
    final mid = Color.lerp(base, colorScheme.primary, 0.06)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Container(
            height: 24,
            width: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  base,
                  mid,
                  base,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        SizedBox(
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 5,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildSkeletonCard(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVideoCard(dynamic video) {
    return VideoCard(
      video: video,
      api: _api,
      server: widget.server,
      onTap: (video) {
        Logger.i("打开视频详情: ${video['Name']}, 类型: ${video['Type']}", _tag);
        
        // 根据类型导航到不同页面
        final type = video['Type']?.toString().toLowerCase();
        final collectionType = video['CollectionType']?.toString().toLowerCase();
        
        if (type == 'boxset' || type == 'collection' || type == 'folder' || collectionType == 'boxsets') {
          Logger.d("打开合集列表页", _tag);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoListMorePage(
                server: widget.server,
                title: video['Name'],
                parentId: video['Id'],
                isMovieView: collectionType == 'movies' || video['IsMovieCollection'] == true,
              ),
            ),
          );
        } else if (type == 'series' || collectionType == 'tvshows') {
          Logger.d("打开电视剧详情页", _tag);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TvShowDetailPage(
                server: widget.server,
                tvShow: video,
              ),
            ),
          );
        } else if (type == 'episode') {
          Logger.d("打开剧集播放页", _tag);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoDetailPage(
                server: widget.server,
                video: video,
              ),
            ),
          );
        } else if (type == 'movie') {
          Logger.d("打开电影播放页", _tag);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoDetailPage(
                server: widget.server,
                video: video,
              ),
            ),
          );
        } else {
          // 对于其他类型，默认导航到列表页
          Logger.d("打开列表页", _tag);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoListMorePage(
                server: widget.server,
                title: video['Name'],
                parentId: video['Id'],
                isMovieView: false,
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildSkeletonCard() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final colorScheme = Theme.of(context).colorScheme;
        final base = colorScheme.surfaceContainerHighest;
        final mid = Color.lerp(base, colorScheme.primary, 0.08)!;
        return Container(
          width: 130,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面占位
              Container(
                height: 195,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      base,
                      mid,
                      base,
                    ],
                    stops: [
                      0.0,
                      _shimmerController.value,
                      1.0,
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.movie_outlined,
                    size: 32,
                    color: colorScheme.onSurfaceVariant.withAlpha(120),
                  ),
                ),
              ),
              // 标题占位
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            base,
                            mid,
                            base,
                          ],
                          stops: [
                            0.0,
                            _shimmerController.value,
                            1.0,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 12,
                      width: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            base,
                            mid,
                            base,
                          ],
                          stops: [
                            0.0,
                            _shimmerController.value,
                            1.0,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}