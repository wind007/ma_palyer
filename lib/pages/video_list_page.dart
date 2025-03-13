import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../services/api_service_manager.dart';
import './video_detail_page.dart';
import '../utils/error_dialog.dart';
import './video_list_more_page.dart';

class VideoListPage extends StatefulWidget {
  final ServerInfo server;

  const VideoListPage({super.key, required this.server});

  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> {
  late final EmbyApiService _api;
  final ScrollController _scrollController = ScrollController();
  
  // 不同分类的视频数据
  Map<String, List<dynamic>> _videoSections = {
    'latest': [], // 最新添加
    'continue': [], // 继续观看
    'favorites': [], // 收藏
    'views': [], // 媒体库视图
  };
  
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeApi();
  }

  Future<void> _initializeApi() async {
    try {
      _api = await ApiServiceManager().initializeEmbyApi(widget.server);
      _loadAllSections();
    } catch (e) {
      setState(() {
        _error = '初始化失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAllSections() async {
    setState(() => _isLoading = true);

    try {
      // 先加载媒体库视图
      await _loadViews();

      // 并行加载其他分区数据
      await Future.wait([
        _loadLatestItems(),
        _loadContinueWatching(),
        _loadFavorites(),
      ]);

      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      
      final retry = await ErrorDialog.show(
        context: context,
        title: '加载失败',
        message: e.toString(),
      );

      if (retry && mounted) {
        _loadAllSections();
      }
    }
  }

  Future<void> _loadViews() async {
    try {
      final response = await _api.getUserViews(widget.server);
      final views = (response as List).where((view) {
        final type = view['CollectionType']?.toString().toLowerCase();
        return type != null;
      }).toList();
      
      setState(() => _videoSections['views'] = views);
      
      // 加载每个视图的内容
      for (var view in views) {
        await _loadViewContent(view);
      }
    } catch (e) {
      print('加载媒体库视图失败: $e');
      setState(() => _videoSections['views'] = []);
    }
  }

  Future<void> _loadViewContent(Map<String, dynamic> view) async {
    try {
      final viewId = view['Id'];
      final response = await _api.getVideos(
        parentId: viewId,
        startIndex: 0,
        limit: 20,
        sortBy: 'DateCreated',
        sortOrder: 'Descending',
      );
      
      if (mounted) {
        setState(() {
          _videoSections[viewId] = response['Items'] as List;
        });
      }
    } catch (e) {
      print('加载视图内容失败: $e');
      if (mounted) {
        setState(() {
          _videoSections[view['Id']] = [];
        });
      }
    }
  }

  Future<void> _loadLatestItems() async {
    final items = await _api.getLatestItems();
    setState(() => _videoSections['latest'] = items);
  }

  Future<void> _loadContinueWatching() async {
    try {
      final items = await _api.getResumeItems();
      print('Continue Watching Items: ${items.length}');
      setState(() => _videoSections['continue'] = items);
    } catch (e) {
      print('Continue Watching Error: $e');
      setState(() => _videoSections['continue'] = []);
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final response = await _api.getVideos(
        startIndex: 0,
        limit: 20,
        sortBy: 'SortName',
        sortOrder: 'Ascending',
        filters: 'Filters=IsFavorite',
        fields: 'BasicSyncInfo',
        includeItemTypes: 'Movie,Series'
      );
      
      if (mounted) {
        setState(() => _videoSections['favorites'] = response['Items'] as List);
      }
    } catch (e) {
      print('加载收藏失败: $e');
      if (mounted) {
        setState(() => _videoSections['favorites'] = []);
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
    if (_isLoading) {
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
          if (_videoSections['continue']!.isNotEmpty)
            _buildSection('继续观看', _videoSections['continue']!),
          _buildSection('最新添加', _videoSections['latest']!),
          if (_videoSections['favorites']!.isNotEmpty)
            _buildSection('我的收藏', _videoSections['favorites']!),
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
      backgroundColor: Theme.of(context).primaryColor,
      elevation: 4,
      title: Text(
        widget.server.name,
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
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
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _buildVideoCard(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoCard(dynamic video) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoDetailPage(
              server: widget.server,
              video: video,
            ),
          ),
        );
      },
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 2/3,
                      child: video['ImageTags']?['Primary'] != null
                          ? Image.network(
                              '${widget.server.url}/Items/${video['Id']}/Images/Primary',
                              headers: {'X-Emby-Token': widget.server.accessToken},
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.movie, size: 32),
                            ),
                    ),
                  ),
                  if (video['UserData']?['Played'] == true)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  if (video['UserData']?['PlaybackPositionTicks'] != null &&
                      video['UserData']?['PlaybackPositionTicks'] > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: video['UserData']?['PlaybackPositionTicks'] /
                            video['RunTimeTicks'],
                        backgroundColor: Colors.black45,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                video['Name'] ?? '未知标题',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}