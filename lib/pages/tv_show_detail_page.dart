import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../services/api_service_manager.dart';
import '../utils/logger.dart';
import './video_detail_page.dart';

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

  @override
  void initState() {
    super.initState();
    Logger.i("初始化电视剧详情页面: ${widget.tvShow['Name']}", _tag);
    _initializeApi();
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
      Logger.d("获取电视剧详情: $tvShowId", _tag);
      final details = await _api!.getVideoDetails(tvShowId);
      Logger.d("获取季列表: $tvShowId", _tag);
      final seasonsResponse = await _api!.getSeasons(
        seriesId: tvShowId,
        userId: _api!.userId!,
        fields: 'PrimaryImageAspectRatio',
      );
      final seasons = seasonsResponse['Items'] as List;

      Logger.i("电视剧详情加载完成: ${details['Name']}", _tag);
      if (mounted) {
        setState(() {
          _tvShowDetails = details;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '剧集列表',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ..._seasons!.map((season) {
          final seasonNumber = season['IndexNumber'] as int;
          final episodes = _tvShowDetails?['Seasons']?[seasonNumber] ?? [];
          
          return ExpansionTile(
            title: Text('第 $seasonNumber 季'),
            subtitle: Text('${episodes.length} 集'),
            children: episodes.map<Widget>((episode) {
              final episodeNumber = episode['IndexNumber'] as int;
              final imageUrl = episode['ImageTags']?['Primary'] != null
                  ? _api!.getImageUrl(
                      itemId: episode['Id'],
                      imageType: 'Primary',
                    )
                  : null;

              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      imageUrl != null
                          ? Image.network(
                              imageUrl,
                              width: 120,
                              height: 68,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 120,
                                  height: 68,
                                  color: Colors.grey[300],
                                  child: Center(
                                    child: Text(
                                      '第 $episodeNumber 集',
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : Container(
                              width: 120,
                              height: 68,
                              color: Colors.grey[300],
                              child: const Icon(Icons.movie, size: 32),
                            ),
                      // 添加已播放和收藏标记
                      if (episode['UserData']?['Played'] == true || episode['UserData']?['IsFavorite'] == true)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (episode['UserData']?['IsFavorite'] == true)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(128),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.favorite,
                                    color: Colors.red,
                                    size: 16,
                                  ),
                                ),
                              if (episode['UserData']?['IsFavorite'] == true && episode['UserData']?['Played'] == true)
                                const SizedBox(width: 4),
                              if (episode['UserData']?['Played'] == true)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(128),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 16,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                title: Text('第 $episodeNumber 集：${episode['Name']}'),
                subtitle: episode['Overview'] != null
                    ? Text(
                        episode['Overview'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VideoDetailPage(
                        server: widget.server,
                        video: episode,
                      ),
                    ),
                  );
                },
              );
            }).toList(),
          );
        }).toList(),
      ],
    );
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

    final imageUrl = _tvShowDetails!['ImageTags']?['Primary'] != null
        ? _api?.getImageUrl(
            itemId: _tvShowDetails!['Id'],
            imageType: 'Primary',
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tvShowDetails?['Name'] ?? '电视剧详情'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadTvShowDetails(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTvShowDetails,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 视频背景图
              Stack(
                children: [
                  // 背景图片
                  imageUrl != null
                      ? Image.network(
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
                      : Container(
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
                            color: Colors.black.withAlpha(128),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IconButton(
                            icon: Icon(
                              _tvShowDetails?['UserData']?['IsFavorite'] == true
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: _tvShowDetails?['UserData']?['IsFavorite'] == true
                                  ? Colors.red
                                  : Colors.white,
                            ),
                            onPressed: () async {
                              final BuildContext currentContext = context;
                              try {
                                final isFavorite = _tvShowDetails?['UserData']?['IsFavorite'] == true;
                                await _api!.toggleFavorite(_tvShowDetails!['Id'], isFavorite);
                                if (!currentContext.mounted) return;
                                setState(() {
                                  _tvShowDetails?['UserData'] ??= {};
                                  _tvShowDetails!['UserData']['IsFavorite'] = !isFavorite;
                                });
                              } catch (e) {
                                if (!currentContext.mounted) return;
                                ScaffoldMessenger.of(currentContext).showSnackBar(
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
                            color: Colors.black.withAlpha(128),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IconButton(
                            icon: Icon(
                              _tvShowDetails?['UserData']?['Played'] == true
                                  ? Icons.check_circle
                                  : Icons.check_circle_outline,
                              color: _tvShowDetails?['UserData']?['Played'] == true
                                  ? Colors.green
                                  : Colors.white,
                            ),
                            onPressed: () async {
                              final BuildContext currentContext = context;
                              try {
                                final isPlayed = _tvShowDetails?['UserData']?['Played'] == true;
                                await _api!.togglePlayed(_tvShowDetails!['Id'], isPlayed);
                                if (!currentContext.mounted) return;
                                setState(() {
                                  _tvShowDetails?['UserData'] ??= {};
                                  _tvShowDetails!['UserData']['Played'] = !isPlayed;
                                });
                              } catch (e) {
                                if (!currentContext.mounted) return;
                                ScaffoldMessenger.of(currentContext).showSnackBar(
                                  SnackBar(content: Text('操作失败: $e')),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 视频信息覆盖层
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tvShowDetails?['Name'] ?? '',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                offset: const Offset(0, 1),
                                blurRadius: 3,
                                color: Colors.black.withAlpha(128),
                              ),
                            ],
                          ),
                        ),
                        if (_tvShowDetails?['Overview'] != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _tvShowDetails!['Overview'],
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                  color: Colors.black.withAlpha(128),
                                ),
                              ],
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              
              // 剧集列表
              _buildSeasonList(),
            ],
          ),
        ),
      ),
    );
  }
} 