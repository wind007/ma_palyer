import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import './video_player_page.dart';

class VideoDetailPage extends StatefulWidget {
  final ServerInfo server;
  final Map<String, dynamic> video;

  const VideoDetailPage({
    super.key,
    required this.server,
    required this.video,
  });

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  final EmbyApiService _api = EmbyApiService(
    baseUrl: '',
    username: '',
    password: '',
  );
  Map<String, dynamic>? _videoDetails;
  int? _playbackPosition;
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
    _loadVideoDetails();
  }

  Future<void> _loadVideoDetails() async {
    try {
      // 重新进行身份验证以获取新的访问令牌
      final authResult = await _api.authenticate();
      _api.accessToken = authResult['AccessToken'];

      final videoId = widget.video['Id'];
      final details = await _api.getVideoDetails(videoId);
      final position = await _api.getPlaybackPosition(videoId);

      setState(() {
        _videoDetails = details;
        _playbackPosition = position;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _playVideo({bool fromStart = false}) {
    if (_videoDetails == null) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerPage(
          itemId: _videoDetails!['Id'],
          title: _videoDetails!['Name'],
          embyApi: _api,
          fromStart: fromStart,
        ),
      ),
    ).then((_) {
      // 返回时重新加载视频详情和播放进度
      _loadVideoDetails();
    });
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text('错误: $_error'));
    }

    if (_videoDetails == null) {
      return const Center(child: Text('无法加载视频详情'));
    }

    return RefreshIndicator(
      onRefresh: _loadVideoDetails,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 视频封面
            if (_videoDetails!['ImageTags']?['Primary'] != null)
              Stack(
                children: [
                  Image.network(
                    '${widget.server.url}/Items/${_videoDetails!['Id']}/Images/Primary',
                    headers: {'X-Emby-Token': widget.server.accessToken},
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 300,
                  ),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _playVideo(fromStart: _playbackPosition == null || _playbackPosition == 0),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Text(
                    _videoDetails!['Name'] ?? '',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  // 年份和时长
                  Text(
                    '${_videoDetails!['ProductionYear'] ?? ''} · ${(_videoDetails!['RunTimeTicks'] ?? 0) ~/ 10000000 ~/ 60} 分钟',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  // 简介
                  Text(
                    _videoDetails!['Overview'] ?? '暂无简介',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  // 演员列表
                  if (_videoDetails!['People'] != null) ...[                  
                    Text(
                      '演职人员',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (var person in _videoDetails!['People'])
                          Chip(label: Text('${person['Name']} (${person['Type']})')),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_videoDetails?['Name'] ?? '视频详情'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadVideoDetails(),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _videoDetails == null
          ? null
          : BottomAppBar(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    if (_playbackPosition != null && _playbackPosition! > 0) ...[                      
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.play_circle),
                          label: Text('继续播放 (${_formatDuration(_playbackPosition! ~/ 10000000)})'),
                          onPressed: () => _playVideo(),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('从头播放'),
                        onPressed: () => _playVideo(fromStart: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // 格式化时长
  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }
}