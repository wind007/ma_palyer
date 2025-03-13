import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../services/api_service_manager.dart';
import './video_detail_page.dart';
import '../utils/error_dialog.dart';
import '../utils/logger.dart';

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
  static const String _tag = "VideoListMore";
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
    Logger.i("初始化视频列表更多页面: ${widget.title}", _tag);
    _initializeApi();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    Logger.d("释放视频列表更多页面资源", _tag);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeApi() async {
    try {
      Logger.d("初始化 API 服务", _tag);
      _api = await ApiServiceManager().initializeEmbyApi(widget.server);
      _loadMore();
    } catch (e) {
      Logger.e("API 初始化失败", _tag, e);
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
      Logger.d("触发滚动加载更多", _tag);
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) {
      Logger.v("跳过加载：${_isLoading ? '正在加载中' : '没有更多数据'}", _tag);
      return;
    }

    Logger.i("加载更多视频，起始索引: $_startIndex", _tag);
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
      final totalRecordCount = response['TotalRecordCount'] as int;
      
      Logger.d("获取到 ${items.length} 个视频，总数: $totalRecordCount", _tag);
      setState(() {
        _videos.addAll(items);
        _startIndex += items.length;
        _isLoading = false;
        // 如果已加载的数量达到或超过总数，则没有更多数据
        _hasMore = _videos.length < totalRecordCount;
      });
      Logger.i("视频加载完成，当前已加载: ${_videos.length}，是否还有更多: $_hasMore", _tag);
    } catch (e) {
      Logger.e("加载视频失败", _tag, e);
      if (!mounted) {
        Logger.w("页面已卸载，取消错误处理", _tag);
        return;
      }
      
      final retry = await ErrorDialog.show(
        context: context,
        title: '加载失败',
        message: e.toString(),
      );

      if (retry && mounted) {
        Logger.i("重试加载视频", _tag);
        _loadMore();
      } else {
        Logger.d("取消重试，停止加载", _tag);
        setState(() {
          _isLoading = false;
          _hasMore = false;
        });
      }
    }
  }

  void _onVideoTap(Map<String, dynamic> video) {
    Logger.i("打开视频详情: ${video['Name']}", _tag);
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
              itemCount: _videos.length + (_hasMore && !_isLoading ? 1 : 0),
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
                    _onVideoTap(video);
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