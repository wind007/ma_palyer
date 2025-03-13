import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../services/api_service_manager.dart';
import './video_detail_page.dart';
import '../utils/error_dialog.dart';

class VideoListMorePage extends StatefulWidget {
  final ServerInfo server;
  final String title;
  final String viewId;
  final String? parentId;
  final bool isMovieView;

  const VideoListMorePage({
    super.key,
    required this.server,
    required this.title,
    required this.viewId,
    this.parentId,
    required this.isMovieView,
  });

  @override
  State<VideoListMorePage> createState() => _VideoListMorePageState();
}

class _VideoListMorePageState extends State<VideoListMorePage> {
  late final EmbyApiService _api;
  final ScrollController _scrollController = ScrollController();
  final List<dynamic> _videos = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _startIndex = 0;
  final int _limit = 20;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeApi();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initializeApi() async {
    try {
      _api = await ApiServiceManager().initializeEmbyApi(widget.server);
      _loadMore();
    } catch (e) {
      setState(() {
        _error = '初始化失败: $e';
        _isLoading = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;

    setState(() => _isLoading = true);

    try {
      final response = await _api.getVideos(
        parentId: widget.parentId ?? widget.viewId,
        startIndex: _startIndex,
        limit: _limit,
        sortBy: 'SortName',
        sortOrder: 'Ascending',
        imageTypes: 'Primary',
        filters: widget.isMovieView ? 'IncludeItemTypes=Movie' : 'IncludeItemTypes=Series',
      );

      final items = response['Items'] as List;
      
      if (items.isEmpty) {
        setState(() => _hasMore = false);
        return;
      }

      setState(() {
        _videos.addAll(items);
        _startIndex += items.length;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      
      final retry = await ErrorDialog.show(
        context: context,
        title: '加载失败',
        message: e.toString(),
      );

      if (retry && mounted) {
        _loadMore();
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.7,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _videos.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _videos.length) {
                  return const Center(child: CircularProgressIndicator());
                }

                final video = _videos[index];
                final imageUrl = _api.getImageUrl(
                  itemId: video['Id'],
                  imageType: 'Primary',
                );

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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        video['Name'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
} 