import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../widgets/video_grid.dart';
import '../utils/logger.dart';
import './video_detail_page.dart';
import './tv_show_detail_page.dart';
import '../widgets/adaptive_app_bar.dart';

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
  final ScrollController _gridScrollController = ScrollController();
  
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
    _gridScrollController.dispose();
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
      
      final searchTerm = _searchController.text;
      final response = await widget.api.searchItems(
        searchTerm: searchTerm,
        nameStartsWithOrGreater: searchTerm.toLowerCase(),
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
      extendBodyBehindAppBar: true,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          AdaptiveAppBar(
            title: '搜索',
            scrollController: _scrollController,
            floating: true,
            snap: true,
            pinned: false,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.shadow.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: '搜索视频、电视剧...',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.search_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: IconButton(
                              icon: Icon(
                                Icons.clear_rounded,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchResults = [];
                                  _hasMoreData = false;
                                });
                              },
                            ),
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() {}); // 刷新界面以显示/隐藏清除按钮
                  },
                  onSubmitted: (_) => _performSearch(isNewSearch: true),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: _searchResults.isEmpty
                ? SliverFillRemaining(
                    child: Center(
                      child: Text('输入关键词开始搜索'),
                    ),
                  )
                : VideoGrid(
                    videos: _searchResults,
                    api: widget.api,
                    server: widget.server,
                    onVideoTap: _onVideoTap,
                    hasMore: _hasMoreData,
                    isLoading: _isLoading,
                    scrollController: _gridScrollController,
                    padding: const EdgeInsets.all(16),
                    childAspectRatio: 0.6,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    cardWidth: 130,
                    imageWidth: 200,
                    imageHeight: 300,
                    useSliverGrid: true,
                  ),
          ),
        ],
      ),
    );
  }
} 