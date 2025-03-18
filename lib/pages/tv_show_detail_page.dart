import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../services/api_service_manager.dart';
import '../utils/logger.dart';
import './video_detail_page.dart';
import 'package:flutter/gestures.dart';
import '../widgets/video_card.dart';
import '../widgets/adaptive_app_bar.dart';

class TvShowDetailPage extends StatefulWidget {
  final ServerInfo server;
  final Map<String, dynamic> tvShow;

  const TvShowDetailPage({
    super.key,
    required this.server,
    required this.tvShow,
  });

  @override
  State<TvShowDetailPage> createState() => _TvShowDetailPageState();
}

class _TvShowDetailPageState extends State<TvShowDetailPage> {
  static const String _tag = "TvShowDetail";
  EmbyApiService? _api;
  Map<String, dynamic>? _tvShowDetails;
  List<dynamic>? _seasons;
  bool _isLoading = true;
  String? _error;
  int _selectedSeasonNumber = 1;
  final ScrollController _episodeScrollController = ScrollController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Logger.i("初始化电视剧详情页面: ${widget.tvShow['Name']}", _tag);
    _initializeApi();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 判断是否为桌面平台
  }

  @override
  void dispose() {
    _episodeScrollController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeApi() async {
    try {
      Logger.d("初始化 API 服务", _tag);
      _api = await ApiServiceManager().initializeEmbyApi(widget.server);
      Logger.d("API 服务初始化完成", _tag);
      if (mounted) {
        _loadTvShowDetails();
      }
    } catch (e) {
      Logger.e("API 初始化失败", _tag, e);
      if (mounted) {
      setState(() {
        _error = '初始化失败: $e';
        _isLoading = false;
      });
    }
  }
  }

  Future<void> _loadTvShowDetails() async {
    if (_api == null) {
      Logger.w("无法加载电视剧详情：API未初始化", _tag);
      return;
    }
    
    Logger.i("开始加载电视剧详情: ${widget.tvShow['Name']}", _tag);
    try {
      final tvShowId = widget.tvShow['Id'];
      if (tvShowId == null) {
        throw Exception('无效的电视剧ID');
      }

      Logger.d("获取电视剧详情: $tvShowId", _tag);
      final details = await _api!.getVideoDetails(tvShowId);

      Logger.d("获取季列表: $tvShowId", _tag);
      final seasonsResponse = await _api!.getSeasons(
        seriesId: tvShowId,
        userId: _api!.userId!,
        fields: 'PrimaryImageAspectRatio,Overview,Path,MediaStreams,MediaSources,IndexNumber,ParentIndexNumber,Type,Status,Genres,Tags',
      );

      final seasons = seasonsResponse['Items'] as List?;
      if (seasons == null) {
        throw Exception('季列表数据格式错误');
      }

      // 获取每一季的剧集列表
      final Map<int, List<dynamic>> seasonEpisodes = {};
      for (var season in seasons) {
        final seasonId = season['Id'];
        if (seasonId == null) {
          Logger.w("跳过无效的季: ${season['Name'] ?? '未知'}", _tag);
          continue;
        }

        final indexNumber = season['IndexNumber'];
        if (indexNumber == null) {
          Logger.w("跳过缺少季数的季: ${season['Name'] ?? '未知'}", _tag);
          continue;
        }

        final seasonNumber = indexNumber is int ? indexNumber : int.tryParse(indexNumber.toString()) ?? 0;
        if (seasonNumber <= 0) {
          Logger.w("跳过无效季数的季: ${season['Name'] ?? '未知'}", _tag);
          continue;
        }

        try {
          final episodesResponse = await _api!.getEpisodes(
            seriesId: tvShowId,
            seasonId: seasonId,
            userId: _api!.userId!,
            fields: 'PrimaryImageAspectRatio,Overview,Path,MediaStreams,MediaSources,IndexNumber,ParentIndexNumber,Type,Status,UserData',
          );

          if (episodesResponse['Items'] is List) {
            seasonEpisodes[seasonNumber] = episodesResponse['Items'] as List;
          } else {
            Logger.w("季 $seasonNumber 的剧集列表为空或格式错误", _tag);
            seasonEpisodes[seasonNumber] = [];
          }
        } catch (e) {
          Logger.e("加载季 $seasonNumber 的剧集失败", _tag, e);
          seasonEpisodes[seasonNumber] = [];
        }
      }

      Logger.i("电视剧详情加载完成: ${details['Name']}", _tag);
      if (mounted) {
      setState(() {
          _tvShowDetails = {
            ...details,
            'Seasons': seasonEpisodes,
          };
          _seasons = seasons;
        _isLoading = false;
      });
      }
    } catch (e) {
      Logger.e("加载电视剧详情失败", _tag, e);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildSeasonList() {
    if (_seasons == null || _seasons!.isEmpty) {
      return const Center(
        child: Text('暂无剧集信息'),
      );
    }

    // 按季数排序
    final sortedSeasons = List<Map<String, dynamic>>.from(_seasons!)
      ..sort((a, b) {
        final aNumber = a['IndexNumber'] is int ? a['IndexNumber'] : int.tryParse(a['IndexNumber'].toString()) ?? 0;
        final bNumber = b['IndexNumber'] is int ? b['IndexNumber'] : int.tryParse(b['IndexNumber'].toString()) ?? 0;
        return aNumber.compareTo(bNumber);
      });

    if (_selectedSeasonNumber <= 0 && sortedSeasons.isNotEmpty) {
      final firstSeason = sortedSeasons.first;
      _selectedSeasonNumber = firstSeason['IndexNumber'] is int 
          ? firstSeason['IndexNumber'] 
          : int.tryParse(firstSeason['IndexNumber'].toString()) ?? 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '剧集列表',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 季选择器
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: sortedSeasons.length,
            itemBuilder: (context, index) {
              final season = sortedSeasons[index];
              final seasonNumber = season['IndexNumber'] is int 
                  ? season['IndexNumber'] 
                  : int.tryParse(season['IndexNumber'].toString()) ?? 0;
              
              final episodes = _tvShowDetails?['Seasons']?[seasonNumber] ?? [];
              final isSelected = seasonNumber == _selectedSeasonNumber;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedSeasonNumber = seasonNumber;
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                        Text(
                          '第 $seasonNumber 季',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isSelected 
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: isSelected ? FontWeight.bold : null,
                          ),
                        ),
                                const SizedBox(width: 4),
                                Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                            color: isSelected 
                                ? Theme.of(context).colorScheme.onPrimary.withAlpha(51)
                                : Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(26),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${episodes.length}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isSelected 
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        // 剧集列表
        _buildEpisodeList(),
      ],
    );
  }

  Widget _buildEpisodeCard(bool focused, int index, Map<String, dynamic> episode) {
    final episodeNumber = '第 ${episode['IndexNumber'] ?? '?'}集';
    final episodeTitle = episode['Name'] ?? '';

    return VideoCard(
      video: {
        ...episode,
        'Name': '$episodeNumber${episodeTitle.isNotEmpty ? '\n$episodeTitle' : ''}',
      },
      api: _api!,
      server: widget.server,
      onTap: (video) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VideoDetailPage(
                        server: widget.server,
              video: {
                ...video,
                'SeriesId': widget.tvShow['Id'],
                'SeasonNumber': _selectedSeasonNumber,
                'EpisodeNumber': episode['IndexNumber'],
              },
                      ),
                    ),
                  );
                },
              );
  }

  Widget _buildEpisodeList() {
    return SizedBox(
      height: 240,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
          },
        ),
        child: ListView.builder(
          key: const PageStorageKey('episode_list'),
          controller: _episodeScrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _tvShowDetails?['Seasons']?[_selectedSeasonNumber]?.length ?? 0,
          itemBuilder: (context, index) {
            final episode = _tvShowDetails?['Seasons']?[_selectedSeasonNumber]?[index] ?? {};
            final epIndexNumber = episode['IndexNumber'];
            if (epIndexNumber == null) return const SizedBox.shrink();
            
            final episodeNumber = epIndexNumber is int 
                ? epIndexNumber 
                : int.tryParse(epIndexNumber.toString()) ?? 0;
            if (episodeNumber <= 0) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FocusScope(
                child: Focus(
                  onFocusChange: (focused) {
                    if (focused) {
                      _episodeScrollController.animateTo(
                        index * 142.0, // 130 宽度 + 12 右边距
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  child: Builder(
                    builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return _buildEpisodeCard(focused, index, episode);
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  int _calculateTotalEpisodes() {
    int total = 0;
    if (_tvShowDetails?['Seasons'] != null) {
      final seasons = _tvShowDetails!['Seasons'] as Map<dynamic, dynamic>;
      seasons.forEach((_, episodes) {
        if (episodes is List) {
          total += episodes.length;
        }
      });
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('加载中...'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('错误'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadTvShowDetails,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_tvShowDetails == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('无数据'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: const Center(
          child: Text('暂无电视剧详情'),
        ),
      );
    }

    String? imageUrl;
    // 按优先级尝试获取不同类型的图片
    if (_tvShowDetails!['ImageTags']?['Primary'] != null && widget.server.url.isNotEmpty) {
      imageUrl = _api?.getImageUrl(
        itemId: _tvShowDetails!['Id'],
            imageType: 'Primary',
        width: 800,
        height: 1200,
        quality: 90,
        tag: _tvShowDetails!['ImageTags']['Primary'],
      );
    } else if (_tvShowDetails!['ImageTags']?['Thumb'] != null && widget.server.url.isNotEmpty) {
      imageUrl = _api?.getImageUrl(
        itemId: _tvShowDetails!['Id'],
        imageType: 'Thumb',
        width: 800,
        height: 1200,
        quality: 90,
        tag: _tvShowDetails!['ImageTags']['Thumb'],
      );
    } else if (_tvShowDetails!['BackdropImageTags'] is List && 
               (_tvShowDetails!['BackdropImageTags'] as List).isNotEmpty &&
               widget.server.url.isNotEmpty) {
      imageUrl = _api?.getImageUrl(
        itemId: _tvShowDetails!['Id'],
        imageType: 'Backdrop',
        width: 1920,
        height: 1080,
        quality: 90,
        tag: _tvShowDetails!['BackdropImageTags'][0],
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          AdaptiveAppBar(
            title: _tvShowDetails?['Name'] ?? '电视剧详情',
            scrollController: _scrollController,
            floating: true,
            snap: true,
            pinned: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
                onPressed: () => _loadTvShowDetails(),
          ),
        ],
      ),
          SliverToBoxAdapter(
            child: RefreshIndicator(
              onRefresh: _loadTvShowDetails,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 视频背景图
                    Stack(
                      children: [
                        // 背景图片
                      if (imageUrl != null && imageUrl.startsWith('http'))
                        Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 400,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: double.infinity,
                                    height: 400,
                                    color: Colors.grey[300],
                                    child: Center(
                                      child: Text(
                                  _tvShowDetails?['Name'] ?? '未知标题',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              )
                      else
                        Container(
                                width: double.infinity,
                                height: 400,
                                color: Colors.grey[300],
                                child: Center(
                                  child: Text(
                              _tvShowDetails?['Name'] ?? '未知标题',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                        // 渐变遮罩
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                Colors.black.withAlpha(179),
                                ],
                                stops: const [0.6, 1.0],
                              ),
                            ),
                          ),
                        ),
                        // 收藏和播放状态按钮
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: Row(
                            children: [
                              // 收藏按钮
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: IconButton(
                                  icon: Icon(
                                  _tvShowDetails!['UserData']?['IsFavorite'] == true
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                  color: _tvShowDetails!['UserData']?['IsFavorite'] == true
                                        ? Colors.red
                                        : Colors.white,
                                  ),
                                  onPressed: () async {
                                    try {
                                    final isFavorite = _tvShowDetails!['UserData']?['IsFavorite'] == true;
                                    await _api!.toggleFavorite(_tvShowDetails!['Id'], isFavorite);
                                      setState(() {
                                      _tvShowDetails!['UserData'] ??= {};
                                      _tvShowDetails!['UserData']['IsFavorite'] = !isFavorite;
                                      });
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('操作失败: $e')),
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 播放状态按钮
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: IconButton(
                                  icon: Icon(
                                  _tvShowDetails!['UserData']?['Played'] == true
                                        ? Icons.check_circle
                                        : Icons.check_circle_outline,
                                  color: _tvShowDetails!['UserData']?['Played'] == true
                                        ? Colors.green
                                        : Colors.white,
                                  ),
                                  onPressed: () async {
                                    try {
                                    final isPlayed = _tvShowDetails!['UserData']?['Played'] == true;
                                    await _api!.togglePlayed(_tvShowDetails!['Id'], isPlayed);
                                      setState(() {
                                      _tvShowDetails!['UserData'] ??= {};
                                      _tvShowDetails!['UserData']['Played'] = !isPlayed;
                                      });
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('操作失败: $e')),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  
                  // 视频信息
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                        // 标题
                              Text(
                          _tvShowDetails?['Name'] ?? '',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        
                        // 评分和类型信息
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (_tvShowDetails!['CommunityRating'] != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star, color: Colors.white, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      _tvShowDetails!['CommunityRating'].toStringAsFixed(1),
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (_tvShowDetails!['Genres'] != null && (_tvShowDetails!['Genres'] as List).isNotEmpty)
                              Expanded(
                                child: Text(
                                  (_tvShowDetails!['Genres'] as List).join(' · '),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(179),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        
                        // 首播日期和状态信息
                        if (_tvShowDetails!['PremiereDate'] != null || _tvShowDetails!['Status'] != null) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              if (_tvShowDetails!['PremiereDate'] != null)
                                Expanded(
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_today, size: 16),
                                      const SizedBox(width: 8),
                                      Text(
                                        '首播: ${DateTime.parse(_tvShowDetails!['PremiereDate']).year}年',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              if (_tvShowDetails!['Status'] != null)
                                Expanded(
                                  child: Row(
                                    children: [
                                      const Icon(Icons.info_outline, size: 16),
                                      const SizedBox(width: 8),
                                      Text(
                                        '状态: ${_tvShowDetails!['Status']}',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                        
                        // 统计信息
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem(
                              icon: Icons.movie,
                              label: '总集数',
                              value: _calculateTotalEpisodes().toString(),
                            ),
                            _buildStatItem(
                              icon: Icons.access_time,
                              label: '单集时长',
                              value: _tvShowDetails!['RunTimeTicks'] != null
                                  ? '${(_tvShowDetails!['RunTimeTicks'] / 10000000 / 60).round()}分钟'
                                  : '未知',
                            ),
                            _buildStatItem(
                              icon: Icons.remove_red_eye,
                              label: '播放次数',
                              value: _tvShowDetails!['UserData']?['PlayCount']?.toString() ?? '0',
                            ),
                          ],
                        ),
                      ],
                    ),
                    ),
                    
                    // 剧集列表
                      _buildSeasonList(),
                  
                  // 其他详细信息
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 简介
                        if (_tvShowDetails?['Overview'] != null) ...[
                          Text(
                            '简介',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _tvShowDetails!['Overview'],
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        
                        // 标签信息
                        if (_tvShowDetails!['Tags'] != null && (_tvShowDetails!['Tags'] as List).isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            '标签',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var tag in _tvShowDetails!['Tags'])
                                Chip(
                                  label: Text(tag),
                                  backgroundColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.08),
                                ),
                            ],
                          ),
                        ],
                        
                        // 制作公司信息
                        if (_tvShowDetails!['Studios'] != null && (_tvShowDetails!['Studios'] as List).isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            '制作公司',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var studio in _tvShowDetails!['Studios'])
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    studio['Name'],
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                            ],
                          ),
                        ],
                        
                        // 演职人员列表
                        if (_tvShowDetails!['People'] != null && (_tvShowDetails!['People'] as List).isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            '演职人员',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 140,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: (_tvShowDetails!['People'] as List).length,
                              itemBuilder: (context, index) {
                                final person = _tvShowDetails!['People'][index];
                                String? imageUrl;
                                if (person['PrimaryImageTag'] != null) {
                                  imageUrl = _api?.getImageUrl(
                                    itemId: person['Id'],
                                    imageType: 'Primary',
                                    tag: person['PrimaryImageTag'],
                                  );
                                }
                                return Container(
                                  width: 100,
                                  margin: const EdgeInsets.only(right: 12),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 40,
                                        backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                                        child: imageUrl == null ? const Icon(Icons.person, size: 40) : null,
                                      ),
                                      const SizedBox(height: 8),
                                      Flexible(
                                        child: Text(
                                          person['Name'],
                                          style: Theme.of(context).textTheme.bodyMedium,
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        person['Type'] ?? person['Role'] ?? '',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(179),
                                        ),
                                        maxLines: 1,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
            ),
    );
  }
} 