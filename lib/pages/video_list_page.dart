import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../services/api_service_manager.dart';
import './video_detail_page.dart';
import './tv_show_detail_page.dart';
import './video_search_page.dart';
import '../utils/error_dialog.dart';
import '../utils/logger.dart';
import './video_list_more_page.dart';
import '../widgets/video_card.dart';

class VideoListPage extends StatefulWidget {
  final ServerInfo server;

  const VideoListPage({super.key, required this.server});

  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> {
  static const String _tag = "VideoList";
  late final EmbyApiService _api;
  final ScrollController _scrollController = ScrollController();
  
  // 分区数据
  final Map<String, List<dynamic>> _videoSections = {
    'latest': [], // 最新添加
    'continue': [], // 继续观看
    'favorites': [], // 收藏
    'views': [], // 媒体库视图
  };
  
  // 分区加载状态
  final Map<String, bool> _isLoadingMore = {};
  final Map<String, bool> _hasMoreData = {};
  final Map<String, int> _sectionStartIndexes = {};
  // 为每个部分创建独立的滚动控制器
  final Map<String, ScrollController> _sectionScrollControllers = {};
  static const int _pageSize = 10;
  
  // 分区加载状态
  final Map<String, bool> _sectionLoading = {
    'latest': true,
    'continue': true,
    'favorites': true,
    'views': true,
  };

  bool _isInitializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Logger.i("初始化视频列表页面: ${widget.server.name}", _tag);
    _initializeApi();
  }

  @override
  void dispose() {
    Logger.d("释放视频列表页面资源", _tag);
    _scrollController.dispose();
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
      ]);

      Logger.i("所有分区数据加载完成", _tag);
    } catch (e) {
      Logger.e("部分分区加载失败", _tag, e);
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
        _videoSections['latest'] = [];
        _hasMoreData['latest'] = false;
        _sectionLoading['latest'] = false;
      });
    }
  }

  Future<void> _loadContinueWatching() async {
    try {
      Logger.d("加载继续观看项目", _tag);
      _isLoadingMore['continue'] = false;
      _hasMoreData['continue'] = true;
      _sectionStartIndexes['continue'] = 0;
      
      final response = await _api.getResumeItems(
        startIndex: 0,
        limit: _pageSize,
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
        _videoSections['favorites'] = [];
        _hasMoreData['favorites'] = false;
        _sectionLoading['favorites'] = false;
      });
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return RefreshIndicator(
      onRefresh: _loadAllSections,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        controller: _scrollController,
        slivers: [
          _buildAppBar(),
          if (!_sectionLoading['continue']! && _videoSections['continue']!.isNotEmpty)
            _buildSection('继续观看', _videoSections['continue']!),
          if (!_sectionLoading['latest']!)
            _buildSection('最新添加', _videoSections['latest']!),
          if (!_sectionLoading['favorites']! && _videoSections['favorites']!.isNotEmpty)
            _buildSection('我的收藏', _videoSections['favorites']!),
          if (!_sectionLoading['views']!)
            ..._buildViewSections(),
          const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 56,
      floating: true,
      pinned: true,
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      elevation: 4,
      title: Text(
        widget.server.name,
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: Colors.white),
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
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: () => _loadAllSections(),
        ),
      ],
    );
  }

  Widget _buildSection(
    String title,
    List<dynamic> items, {
    String? viewId,
    bool isMovieView = false,
  }) {
    if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    final sectionId = viewId ?? title.toLowerCase();
    final bool isLoading = _isLoadingMore[sectionId] ?? false;
    final bool hasMore = _hasMoreData[sectionId] ?? false;
    final scrollController = _getScrollController(sectionId);

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (viewId != null)
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VideoListMorePage(
                            server: widget.server,
                            title: title,
                            viewId: viewId,
                            isMovieView: isMovieView,
                          ),
                        ),
                      );
                    },
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
                  // 获取滚动位置信息
                  final maxScroll = scrollInfo.metrics.maxScrollExtent;
                  final currentScroll = scrollInfo.metrics.pixels;
                  
                  // 使用固定像素作为阈值，更适合横向滚动
                  const threshold = 100.0;
                  
                  // 当滚动到距离末尾 threshold 距离时触发加载
                  if (!isLoading && 
                      hasMore && 
                      maxScroll > 0 &&  // 确保有可滚动内容
                      (maxScroll - currentScroll) <= threshold) {
                    Logger.d(
                      '触发加载更多: sectionId=$sectionId, '
                      'maxScroll=$maxScroll, '
                      'currentScroll=$currentScroll, '
                      'threshold=$threshold, '
                      'remainingScroll=${maxScroll - currentScroll}',
                      _tag
                    );
                    _loadMoreForSection(sectionId);
                  }
                }
                return false;
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    // 使用当前部分的滚动控制器
                    scrollController.position.moveTo(
                      scrollController.position.pixels - details.delta.dx,
                      curve: Curves.linear,
                    );
                  },
                  child: ListView.builder(
                    key: PageStorageKey<String>(sectionId),
                    controller: scrollController, // 使用当前部分的滚动控制器
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    physics: const ClampingScrollPhysics(),
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
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '加载中...',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
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
        
        if (type == 'series' || collectionType == 'tvshows') {
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
        } else {
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
        }
      },
    );
  }

  List<Widget> _buildViewSections() {
    return _videoSections['views']!.map((view) {
      final viewId = view['Id'];
      final viewName = view['Name'];
      final items = _videoSections[viewId] ?? [];
      final isMovieView = view['CollectionType']?.toString().toLowerCase() == 'movies';
      
      return _buildSection(
        viewName,
        items,
        viewId: viewId,
        isMovieView: isMovieView,
      );
    }).toList();
  }

  // 获取或创建部分的滚动控制器
  ScrollController _getScrollController(String sectionId) {
    if (!_sectionScrollControllers.containsKey(sectionId)) {
      _sectionScrollControllers[sectionId] = ScrollController();
    }
    return _sectionScrollControllers[sectionId]!;
  }
}