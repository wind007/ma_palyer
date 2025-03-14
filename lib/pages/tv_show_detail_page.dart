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
    return ListView.builder(
      itemCount: _seasons.length,
      itemBuilder: (context, index) {
        final season = _seasons[index];
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
                child: imageUrl != null
                    ? Image.network(
                        imageUrl,
                        width: 120,
                        height: 68,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 120,
                        height: 68,
                        color: Colors.grey[300],
                        child: const Icon(Icons.movie, size: 32),
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
      },
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
      body: _error != null
          ? Center(child: Text(_error!))
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 300,
                  pinned: true,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(widget.tvShow['Name']),
                    background: imageUrl != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.movie, size: 64),
                          ),
                  ),
                ),
                if (widget.tvShow['Overview'] != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(widget.tvShow['Overview']),
                    ),
                  ),
                if (_isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  SliverFillRemaining(
                    child: _buildSeasonList(),
                  ),
              ],
            ),
    );
  }
} 