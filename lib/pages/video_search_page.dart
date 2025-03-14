import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../widgets/video_card.dart';
import '../widgets/video_grid.dart';
import '../utils/logger.dart';
import './video_detail_page.dart';
import './tv_show_detail_page.dart';

class VideoSearchPage extends StatefulWidget {
  final ServerInfo server;
  final EmbyApiService api;

  const VideoSearchPage({
    super.key,
    required this.server,
    required this.api,
  });

  @override
  State<VideoSearchPage> createState() => _VideoSearchPageState();
}

class _VideoSearchPageState extends State<VideoSearchPage> {
  static const String _tag = "VideoSearch";
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<dynamic> _searchResults = [];
  bool _isLoading = false;
  bool _hasMoreData = true;
  int _startIndex = 0;
  static const int _pageSize = 20;
  String _lastSearchTerm = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMoreData) {
      _loadMore();
    }
  }

  Future<void> _performSearch({bool isNewSearch = false}) async {
    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _hasMoreData = false;
      });
      return;
    }

    if (isNewSearch) {
      setState(() {
        _startIndex = 0;
        _searchResults = [];
        _lastSearchTerm = _searchController.text;
      });
    }

    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      Logger.d("执行搜索: term=${_searchController.text}, startIndex=$_startIndex", _tag);
      
      final response = await widget.api.searchItems(
        searchTerm: _searchController.text,
        startIndex: _startIndex,
        limit: _pageSize,
        includeItemTypes: 'Movie,Series,Episode',
      );

      final items = response['Items'] as List;
      final totalCount = response['TotalRecordCount'] as int;

      Logger.d("搜索完成: 获取到 ${items.length} 个结果, 总共 $totalCount 个结果", _tag);

      if (mounted) {
        setState(() {
          if (isNewSearch) {
            _searchResults = items;
          } else {
            _searchResults = [..._searchResults, ...items];
          }
          _startIndex += items.length;
          _hasMoreData = _searchResults.length < totalCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.e("搜索失败", _tag, e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索失败: $e')),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_searchController.text != _lastSearchTerm) return;
    await _performSearch();
  }

  void _onVideoTap(Map<String, dynamic> video) {
    final type = video['Type']?.toString().toLowerCase();
    if (type == 'series') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TvShowDetailPage(
            server: widget.server,
            tvShow: video,
          ),
        ),
      );
    } else {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '搜索视频、电视剧...',
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchResults = [];
                  _hasMoreData = false;
                });
              },
            ),
          ),
          onSubmitted: (_) => _performSearch(isNewSearch: true),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _searchResults.isEmpty
                ? const Center(
                    child: Text('输入关键词开始搜索'),
                  )
                : VideoGrid(
                    videos: _searchResults,
                    api: widget.api,
                    server: widget.server,
                    onVideoTap: _onVideoTap,
                    hasMore: _hasMoreData,
                    isLoading: _isLoading,
                    scrollController: _scrollController,
                    padding: const EdgeInsets.all(8),
                    crossAxisCount: 5,
                    childAspectRatio: 0.55,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    cardWidth: 120,
                    imageWidth: 160,
                    imageHeight: 240,
                  ),
          ),
        ],
      ),
    );
  }
} 