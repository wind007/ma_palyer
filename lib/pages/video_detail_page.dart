import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../utils/logger.dart';
import '../widgets/emby_image.dart';
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
  static const String _tag = "VideoDetail";
  
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
    Logger.i("初始化视频详情页面: ${widget.video['Name']}", _tag);
    _api
      ..baseUrl = widget.server.url
      ..username = widget.server.username
      ..password = widget.server.password
      ..accessToken = widget.server.accessToken
      ..userId = widget.server.userId;
    Logger.d("API服务初始化完成，userId: ${widget.server.userId}", _tag);
    _loadVideoDetails();
  }

  @override
  void dispose() {
    Logger.d("释放视频详情页面资源", _tag);
    super.dispose();
  }

  Future<void> _loadVideoDetails() async {
    Logger.i("开始加载视频详情: ${widget.video['Name']}", _tag);
    try {
      final videoId = widget.video['Id'];
      Logger.d("获取视频详情: $videoId", _tag);
      final details = await _api.getVideoDetails(videoId);
      Logger.d("获取播放进度: $videoId", _tag);
      final position = await _api.getPlaybackPosition(videoId);

      Logger.i("视频详情加载完成: ${details['Name']}", _tag);
      setState(() {
        _videoDetails = details;
        _playbackPosition = position;
        _isLoading = false;
      });
    } catch (e) {
      Logger.e("加载视频详情失败", _tag, e);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _playVideo({
    bool fromStart = false,
    int? mediaSourceIndex,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    if (_videoDetails == null) {
      Logger.w("无法播放视频：视频详情未加载", _tag);
      return;
    }
    
    Logger.i(
      "开始播放视频: ${_videoDetails!['Name']}, "
      "${fromStart ? '从头开始' : '继续播放'}, "
      "版本: $mediaSourceIndex, "
      "音频: $audioStreamIndex, "
      "字幕: $subtitleStreamIndex",
      _tag,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerPage(
          itemId: _videoDetails!['Id'],
          title: _videoDetails!['Name'],
          embyApi: _api,
          fromStart: fromStart,
          mediaSourceIndex: mediaSourceIndex,
          initialAudioStreamIndex: audioStreamIndex,
          initialSubtitleStreamIndex: subtitleStreamIndex,
        ),
      ),
    ).then((_) {
      // 返回时重新加载视频详情和播放进度
      Logger.d("播放结束，重新加载视频详情", _tag);
      _loadVideoDetails();
    });
  }

  // 添加音频和字幕流选择对话框
  void _showStreamSelectionDialog(Map<String, dynamic> mediaSource) {
    showDialog(
      context: context,
      builder: (context) {
        final audioStreams = mediaSource['MediaStreams']
            ?.where((s) => s['Type'] == 'Audio')
            ?.toList() as List?;
        final subtitleStreams = mediaSource['MediaStreams']
            ?.where((s) => s['Type'] == 'Subtitle')
            ?.toList() as List?;

        return Dialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择音频和字幕',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (audioStreams != null && audioStreams.isNotEmpty) ...[
                  Text(
                    '音频',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var stream in audioStreams)
                        ChoiceChip(
                          label: Text(
                            '${stream['Language'] ?? '未知'} '
                            '(${stream['Codec']?.toString().toUpperCase() ?? '未知'})',
                          ),
                          selected: stream['Index'] == mediaSource['DefaultAudioStreamIndex'],
                          onSelected: (selected) {
                            Navigator.pop(context, {
                              'audioIndex': selected ? stream['Index'] : null,
                            });
                          },
                        ),
                    ],
                  ),
                ],
                if (subtitleStreams != null && subtitleStreams.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '字幕',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('关闭字幕'),
                        selected: mediaSource['DefaultSubtitleStreamIndex'] == null,
                        onSelected: (selected) {
                          Navigator.pop(context, {
                            'subtitleIndex': null,
                          });
                        },
                      ),
                      for (var stream in subtitleStreams)
                        ChoiceChip(
                          label: Text(
                            '${stream['Language'] ?? '未知'} '
                            '(${stream['Codec']?.toString().toUpperCase() ?? '未知'})',
                          ),
                          selected: stream['Index'] == mediaSource['DefaultSubtitleStreamIndex'],
                          onSelected: (selected) {
                            Navigator.pop(context, {
                              'subtitleIndex': selected ? stream['Index'] : null,
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ).then((value) {
      if (value != null) {
        _playVideo(
          mediaSourceIndex: mediaSource['Index'],
          audioStreamIndex: value['audioIndex'],
          subtitleStreamIndex: value['subtitleIndex'],
        );
      }
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
            // 视频背景图
            if (_videoDetails!['ImageTags'] != null) ...[
              Stack(
                children: [
                  EmbyImage(
                    imageUrl: _videoDetails!['ImageTags']?['Backdrop'] != null
                        ? '${widget.server.url}/Items/${_videoDetails!['Id']}/Images/Backdrop'
                        : _videoDetails!['ImageTags']?['Primary'] != null
                            ? '${widget.server.url}/Items/${_videoDetails!['Id']}/Images/Primary'
                            : '${widget.server.url}/Items/${_videoDetails!['Id']}/Images/Primary/0',
                    headers: {'X-Emby-Token': widget.server.accessToken ?? ''},
                    width: double.infinity,
                    height: 400,
                    title: _videoDetails!['Name'],
                  ),
                  // 添加渐变遮罩
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
                              _videoDetails!['UserData']?['IsFavorite'] == true
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: _videoDetails!['UserData']?['IsFavorite'] == true
                                  ? Colors.red
                                  : Colors.white,
                            ),
                            onPressed: () async {
                              try {
                                final isFavorite = _videoDetails!['UserData']?['IsFavorite'] == true;
                                await _api.toggleFavorite(_videoDetails!['Id'], isFavorite);
                                setState(() {
                                  _videoDetails!['UserData'] ??= {};
                                  _videoDetails!['UserData']['IsFavorite'] = !isFavorite;
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
                              _videoDetails!['UserData']?['Played'] == true
                                  ? Icons.check_circle
                                  : Icons.check_circle_outline,
                              color: _videoDetails!['UserData']?['Played'] == true
                                  ? Colors.green
                                  : Colors.white,
                            ),
                            onPressed: () async {
                              try {
                                final isPlayed = _videoDetails!['UserData']?['Played'] == true;
                                await _api.togglePlayed(_videoDetails!['Id'], isPlayed);
                                setState(() {
                                  _videoDetails!['UserData'] ??= {};
                                  _videoDetails!['UserData']['Played'] = !isPlayed;
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
                          _videoDetails!['Name'] ?? '',
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
                        if (_videoDetails!['Overview'] != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _videoDetails!['Overview'],
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
                  // 添加中央播放按钮
                  Positioned.fill(
                    child: Center(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            if (_playbackPosition != null && _playbackPosition! > 0) {
                              _playVideo();
                            } else {
                              _playVideo(fromStart: true);
                            }
                          },
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _playbackPosition != null && _playbackPosition! > 0
                                  ? Icons.play_circle_filled
                                  : Icons.play_arrow,
                              color: Colors.white,
                              size: 50,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  // 评分和类型信息
                  Row(
                    children: [
                      if (_videoDetails!['CommunityRating'] != null) ...[
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
                                _videoDetails!['CommunityRating'].toStringAsFixed(1),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (_videoDetails!['Genres'] != null && (_videoDetails!['Genres'] as List).isNotEmpty)
                        Expanded(
                          child: Text(
                            (_videoDetails!['Genres'] as List).join(' · '),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // 技术信息
                  if (_videoDetails!['MediaSources'] != null && (_videoDetails!['MediaSources'] as List).isNotEmpty) ...[
                    Text(
                      '可用版本',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: (_videoDetails!['MediaSources'] as List).length,
                      itemBuilder: (context, index) {
                        final source = _videoDetails!['MediaSources'][index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () => _showStreamSelectionDialog(source),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.video_file,
                                        size: 20,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          source['Name'] ?? '默认版本',
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (source['DefaultAudioStreamIndex'] != null) ...[
                                        const Icon(Icons.audiotrack, size: 16),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${source['MediaStreams']?.where((s) => s['Type'] == 'Audio')?.length ?? 0} 音轨',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                      if (source['DefaultSubtitleStreamIndex'] != null) ...[
                                        const SizedBox(width: 8),
                                        const Icon(Icons.subtitles, size: 16),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${source['MediaStreams']?.where((s) => s['Type'] == 'Subtitle')?.length ?? 0} 字幕',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (source['Container'] != null)
                                        _buildInfoChip(
                                          icon: Icons.folder,
                                          label: source['Container'].toString().toUpperCase(),
                                        ),
                                      if (source['VideoCodec'] != null)
                                        _buildInfoChip(
                                          icon: Icons.video_file,
                                          label: source['VideoCodec'].toString().toUpperCase(),
                                        ),
                                      if (source['Width'] != null)
                                        _buildInfoChip(
                                          icon: Icons.high_quality,
                                          label: '${source['Width']}x${source['Height']}',
                                        ),
                                      if (source['Size'] != null)
                                        _buildInfoChip(
                                          icon: Icons.data_usage,
                                          label: '${(source['Size'] / 1024 / 1024 / 1024).toStringAsFixed(2)} GB',
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // 制作信息
                  if (_videoDetails!['Studios'] != null && (_videoDetails!['Studios'] as List).isNotEmpty) ...[
                    Text(
                      '制作信息',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var studio in _videoDetails!['Studios'])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.business_outlined, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      studio['Name'],
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // 简介
                  if (_videoDetails!['Overview'] != null && _videoDetails!['Overview'].toString().isNotEmpty) ...[
                    Text(
                      '简介',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _videoDetails!['Overview'],
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // 演职人员列表
                  if (_videoDetails!['People'] != null && (_videoDetails!['People'] as List).isNotEmpty) ...[
                    Text(
                      '演职人员',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: (_videoDetails!['People'] as List).length,
                        itemBuilder: (context, index) {
                          final person = _videoDetails!['People'][index];
                          return Container(
                            width: 80,
                            margin: const EdgeInsets.only(right: 12),
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundImage: person['PrimaryImageTag'] != null
                                      ? NetworkImage(
                                          '${widget.server.url}/Items/${person['Id']}/Images/Primary?tag=${person['PrimaryImageTag']}&X-Emby-Token=${widget.server.accessToken}',
                                        )
                                      : null,
                                  child: person['PrimaryImageTag'] == null
                                      ? const Icon(Icons.person, size: 30)
                                      : null,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  person['Name'],
                                  style: Theme.of(context).textTheme.bodySmall,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  person['Type'],
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
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
      return '$hours:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}