import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import './video_detail_page.dart';

class VideoListPage extends StatefulWidget {
  final ServerInfo server;

  const VideoListPage({super.key, required this.server});

  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> {
  final EmbyApiService _api = EmbyApiService(baseUrl: '', username: '', password: '');
  final ScrollController _scrollController = ScrollController();
  
  // 不同分类的视频数据
  Map<String, List<dynamic>> _videoSections = {
    'latest': [], // 最新添加
    'continue': [], // 继续观看
    'favorites': [], // 收藏
    'movies': [], // 电影
    'tvshows': [], // 电视剧
  };
  
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api
      ..baseUrl = widget.server.url
      ..username = widget.server.username
      ..password = widget.server.password
      ..accessToken = widget.server.accessToken;
    _loadAllSections();
  }

  Future<void> _loadAllSections() async {
    setState(() => _isLoading = true);

    try {
      // 重新进行身份验证
      final authResult = await _api.authenticate();
      _api.accessToken = authResult['accessToken'];

      // 并行加载所有分区数据
      await Future.wait([
        _loadLatestItems(),
        _loadContinueWatching(),
        _loadFavorites(),
        _loadMovies(),
        _loadTVShows(),
      ]);

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
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
    final response = await _api.getVideos(
      startIndex: 0,
      limit: 20,
      sortBy: 'DateCreated',
      sortOrder: 'Descending',
      filters: 'IsFavorite=true',
    );
    setState(() => _videoSections['favorites'] = response['Items']);
  }

  Future<void> _loadMovies() async {
    final response = await _api.getVideos(
      startIndex: 0,
      limit: 20,
      sortBy: 'DateCreated',
      sortOrder: 'Descending',
      filters: 'IncludeItemTypes=Movie',
    );
    setState(() => _videoSections['movies'] = response['Items']);
  }

  Future<void> _loadTVShows() async {
    final response = await _api.getVideos(
      startIndex: 0,
      limit: 20,
      sortBy: 'DateCreated',
      sortOrder: 'Descending',
      filters: 'IncludeItemTypes=Series',
    );
    setState(() => _videoSections['tvshows'] = response['Items']);
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
        controller: _scrollController,
        slivers: [
          _buildAppBar(),
          if (_videoSections['continue']!.isNotEmpty)
            _buildSection('继续观看', _videoSections['continue']!),
          _buildSection('最新添加', _videoSections['latest']!),
          if (_videoSections['favorites']!.isNotEmpty)
            _buildSection('我的收藏', _videoSections['favorites']!),
          _buildSection('电影', _videoSections['movies']!),
          _buildSection('电视剧', _videoSections['tvshows']!),
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
    );
  }

  Widget _buildSection(String title, List<dynamic> items) {
    if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}