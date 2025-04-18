import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

class VideoListPage extends StatefulWidget {
  final ServerInfo server;

  const VideoListPage({super.key, required this.server});

  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> with SingleTickerProviderStateMixin {
  static const String _tag = "VideoList";
  late final EmbyApiService _api;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _shimmerController;
  
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

    // 初始化闪烁动画控制器
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
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
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return RefreshIndicator(
      onRefresh: _loadAllSections,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
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
    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
          SizedBox(height: 8),
          Text(
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
                  Colors.grey[300]!,
                  Colors.grey[200]!,
                  Colors.grey[300]!,
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
        return Container(
          width: 130,
          decoration: BoxDecoration(
            color: Colors.grey[200],
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
                      Colors.grey[300]!,
                      Colors.grey[200]!,
                      Colors.grey[300]!,
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
                    color: Colors.grey[400],
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
                            Colors.grey[300]!,
                            Colors.grey[200]!,
                            Colors.grey[300]!,
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
                            Colors.grey[300]!,
                            Colors.grey[200]!,
                            Colors.grey[300]!,
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