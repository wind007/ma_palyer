import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../services/api_service_manager.dart';
import '../utils/error_dialog.dart';
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
  late final EmbyApiService _api;
  final Map<int, List<dynamic>> _seasonEpisodes = {};
  final List<dynamic> _seasons = [];
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
      _loadSeasons();
    } catch (e) {
      Logger.e("API 初始化失败", _tag, e);
      setState(() {
        _error = '初始化失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSeasons() async {
    try {
      Logger.i("加载电视剧季信息", _tag);
      final response = await _api.getSeasons(
        seriesId: widget.tvShow['Id'],
        userId: _api.userId!,
        fields: 'PrimaryImageAspectRatio',
      );

      if (!mounted) return;

      setState(() {
        _seasons.addAll(response['Items'] as List);
        _isLoading = false;
      });

      // 加载每一季的剧集
      for (var season in _seasons) {
        _loadEpisodes(season);
      }
    } catch (e) {
      Logger.e("加载季信息失败", _tag, e);
      if (!mounted) return;
      
      final retry = await ErrorDialog.show(
        context: context,
        title: '加载失败',
        message: e.toString(),
      );

      if (retry && mounted) {
        _loadSeasons();
      } else {
        setState(() {
          _isLoading = false;
          _error = '加载失败: $e';
        });
      }
    }
  }

  Future<void> _loadEpisodes(Map<String, dynamic> season) async {
    try {
      Logger.i("加载第 ${season['IndexNumber']} 季的剧集", _tag);
      final response = await _api.getEpisodes(
        seriesId: widget.tvShow['Id'],
        seasonId: season['Id'],
        userId: _api.userId!,
        fields: 'Overview,PrimaryImageAspectRatio',
      );

      if (!mounted) return;

      setState(() {
        _seasonEpisodes[season['IndexNumber']] = response['Items'] as List;
      });
    } catch (e) {
      Logger.e("加载剧集失败", _tag, e);
    }
  }

  Widget _buildSeasonList() {
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
        ..._seasons.map((season) {
          final seasonNumber = season['IndexNumber'] as int;
          final episodes = _seasonEpisodes[seasonNumber] ?? [];
          
          return ExpansionTile(
            title: Text('第 $seasonNumber 季'),
            subtitle: Text('${episodes.length} 集'),
            children: episodes.map<Widget>((episode) {
              final episodeNumber = episode['IndexNumber'] as int;
              final imageUrl = episode['ImageTags']?['Primary'] != null
                  ? _api.getImageUrl(
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
                                    color: Colors.black54,
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
                                    color: Colors.black54,
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
    final imageUrl = widget.tvShow['ImageTags']?['Primary'] != null
        ? _api.getImageUrl(
            itemId: widget.tvShow['Id'],
            imageType: 'Primary',
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tvShow['Name'] ?? '电视剧详情'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadSeasons(),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _loadSeasons,
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
                                        widget.tvShow['Name'] ?? '未知标题',
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
                                    widget.tvShow['Name'] ?? '未知标题',
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
                                  Colors.black.withOpacity(0.7),
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
                                    widget.tvShow['UserData']?['IsFavorite'] == true
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: widget.tvShow['UserData']?['IsFavorite'] == true
                                        ? Colors.red
                                        : Colors.white,
                                  ),
                                  onPressed: () async {
                                    try {
                                      final isFavorite = widget.tvShow['UserData']?['IsFavorite'] == true;
                                      await _api.toggleFavorite(widget.tvShow['Id'], isFavorite);
                                      setState(() {
                                        widget.tvShow['UserData'] ??= {};
                                        widget.tvShow['UserData']['IsFavorite'] = !isFavorite;
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
                                    widget.tvShow['UserData']?['Played'] == true
                                        ? Icons.check_circle
                                        : Icons.check_circle_outline,
                                    color: widget.tvShow['UserData']?['Played'] == true
                                        ? Colors.green
                                        : Colors.white,
                                  ),
                                  onPressed: () async {
                                    try {
                                      final isPlayed = widget.tvShow['UserData']?['Played'] == true;
                                      await _api.togglePlayed(widget.tvShow['Id'], isPlayed);
                                      setState(() {
                                        widget.tvShow['UserData'] ??= {};
                                        widget.tvShow['UserData']['Played'] = !isPlayed;
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
                        // 视频信息覆盖层
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.tvShow['Name'] ?? '',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      offset: const Offset(0, 1),
                                      blurRadius: 3,
                                      color: Colors.black.withOpacity(0.5),
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.tvShow['Overview'] != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  widget.tvShow['Overview'],
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        offset: const Offset(0, 1),
                                        blurRadius: 2,
                                        color: Colors.black.withOpacity(0.5),
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
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator())
                    else
                      _buildSeasonList(),
                  ],
                ),
              ),
            ),
    );
  }
} 