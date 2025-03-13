import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import './video_detail_page.dart';

class VideoListMorePage extends StatefulWidget {
  final ServerInfo server;
  final String title;
  final String viewId;

  const VideoListMorePage({
    super.key,
    required this.server,
    required this.title,
    required this.viewId,
  });

  @override
  State<VideoListMorePage> createState() => _VideoListMorePageState();
}

class _VideoListMorePageState extends State<VideoListMorePage> {
  final EmbyApiService _api = EmbyApiService(baseUrl: '', username: '', password: '');
  final ScrollController _scrollController = ScrollController();
  final List<dynamic> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 0;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _api
      ..baseUrl = widget.server.url
      ..username = widget.server.username
      ..password = widget.server.password
      ..accessToken = widget.server.accessToken;
    
    _scrollController.addListener(_onScroll);
    _loadMore();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;

    setState(() => _isLoading = true);

    try {
            // 重新进行身份验证
      final authResult = await _api.authenticate();
      _api.accessToken = authResult['accessToken'];
      
      final response = await _api.getVideos(
        parentId: widget.viewId,
        startIndex: _currentPage * _pageSize,
        limit: _pageSize,
        sortBy: 'SortName',
        sortOrder: 'Ascending',
        fields: 'PrimaryImageAspectRatio,BasicSyncInfo,Path,MediaSources,MediaStreams,UserData',
        imageTypes: 'Primary'
      );

      final newItems = response['Items'] as List;
      
      if (mounted) {
        setState(() {
          _items.addAll(newItems);
          _currentPage++;
          _hasMore = newItems.length == _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('加载更多失败: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.7,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return const Center(child: CircularProgressIndicator());
          }

          final item = _items[index];
          return _buildVideoCard(item);
        },
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
          Text(
            video['Name'] ?? '未知标题',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
} 