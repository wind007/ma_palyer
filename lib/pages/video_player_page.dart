import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/emby_api.dart';

class VideoPlayerPage extends StatefulWidget {
  final String itemId;
  final String title;
  final EmbyApiService embyApi;

  const VideoPlayerPage({
    Key? key,
    required this.itemId,
    required this.title,
    required this.embyApi,
  }) : super(key: key);

  @override
  _VideoPlayerPageState createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _controller;
  Timer? _progressTimer;
  
  // 字幕相关
  List<String> _subtitles = [];
  int _currentSubtitleIndex = -1;
  
  // 清晰度相关
  List<Map<String, dynamic>> _qualities = [];
  int _currentQualityIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      // 获取播放信息
      final playbackInfo = await widget.embyApi.getPlaybackInfo(widget.itemId);
      
      // 获取清晰度列表
      if (playbackInfo['MediaSources'] != null) {
        final mediaSources = playbackInfo['MediaSources'] as List;
        _qualities = mediaSources.map((source) {
          final bitrate = source['Bitrate'] ?? 0;
          final width = source['Width'] ?? 0;
          final height = source['Height'] ?? 0;
          return {
            'url': source['Path'] ?? '',
            'name': '${height}p (${(bitrate / 1000000).toStringAsFixed(1)}Mbps)',
            'bitrate': bitrate,
          };
        }).toList();
        
        // 按比特率排序
        _qualities.sort((a, b) => (b['bitrate'] as int).compareTo(a['bitrate'] as int));
      }
      
      // 获取字幕列表
      if (playbackInfo['MediaSources'] != null && 
          playbackInfo['MediaSources'].isNotEmpty &&
          playbackInfo['MediaSources'][0]['MediaStreams'] != null) {
        final streams = playbackInfo['MediaSources'][0]['MediaStreams'] as List;
        _subtitles = streams.where((stream) => 
          stream['Type'] == 'Subtitle' && 
          stream['DeliveryUrl'] != null
        ).map((stream) => 
          '${widget.embyApi.baseUrl}${stream['DeliveryUrl']}?api_key=${widget.embyApi.accessToken}'
        ).toList();
      }
      
      // 获取播放地址和进度
      final url = await widget.embyApi.getPlaybackUrl(widget.itemId);
      final position = await widget.embyApi.getPlaybackPosition(widget.itemId);
      
      // 初始化播放器
      _controller = VideoPlayerController.network(
        '$url?api_key=${widget.embyApi.accessToken}',
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        httpHeaders: {
          'X-Emby-Token': widget.embyApi.accessToken!,
        },
      );

      // 使用链式调用处理初始化
      await _controller.initialize().then((_) {
        if (position > 0) {
          _controller.seekTo(Duration(microseconds: position ~/ 10));
        }
        _controller.play();
        if (mounted) {
          setState(() {});
        }
        
        // 启动进度更新定时器
        _startProgressTimer();
      }).catchError((error) {
        print('播放器初始化失败: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('播放器初始化失败: $error')),
          );
        }
      });

      // 添加播放状态监听
      _controller.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
      
    } catch (e) {
      print('初始化播放器失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化播放器失败: $e')),
        );
      }
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_controller.value.isPlaying) {
        widget.embyApi.updatePlaybackProgress(
          widget.itemId,
          (_controller.value.position.inMicroseconds * 10).toInt(),
          isPaused: false,
        );
      }
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _controller.dispose();
    widget.embyApi.stopPlayback(widget.itemId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 视频播放器
          Center(
            child: _controller.value.isInitialized
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: GestureDetector(
                      onTap: () {
                        if (_controller.value.isPlaying) {
                          _controller.pause();
                        } else {
                          _controller.play();
                        }
                      },
                      child: VideoPlayer(_controller),
                    ),
                  )
                : const CircularProgressIndicator(),
          ),
          
          // 顶部控制栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_subtitles.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.subtitles),
                        color: Colors.white,
                        onPressed: _showSubtitleSelector,
                      ),
                    if (_qualities.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.high_quality),
                        color: Colors.white,
                        onPressed: _showQualitySelector,
                      ),
                  ],
                ),
              ),
            ),
          ),
          
          // 底部控制栏
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: ValueListenableBuilder(
                valueListenable: _controller,
                builder: (context, VideoPlayerValue value, child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 进度条
                      Container(
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 背景轨道
                            Container(
                              height: 2,
                              color: Colors.grey[300],
                            ),
                            // 进度条
                            if (value.duration.inMilliseconds > 0)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  height: 2,
                                  width: MediaQuery.of(context).size.width * 
                                    (value.position.inMilliseconds / value.duration.inMilliseconds),
                                  color: Colors.red,
                                ),
                              ),
                            // 可拖动的滑块
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.transparent,
                                inactiveTrackColor: Colors.transparent,
                                trackHeight: 2.0,
                                thumbColor: Colors.red,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6.0,
                                ),
                                overlayColor: Colors.red.withAlpha(32),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12.0,
                                ),
                              ),
                              child: Slider(
                                value: value.position.inMilliseconds.toDouble(),
                                min: 0,
                                max: value.duration.inMilliseconds.toDouble(),
                                onChanged: (newPosition) {
                                  _controller.seekTo(Duration(milliseconds: newPosition.toInt()));
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // 时间显示和控制按钮
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 时间显示
                            Text(
                              '${value.position.inMinutes}:${(value.position.inSeconds % 60).toString().padLeft(2, '0')} / '
                              '${value.duration.inMinutes}:${(value.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                            
                            // 播放/暂停按钮
                            IconButton(
                              icon: Icon(
                                value.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                if (value.isPlaying) {
                                  _controller.pause();
                                } else {
                                  _controller.play();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSubtitleSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: _subtitles.length + 1,
        itemBuilder: (context, index) => ListTile(
          title: Text(index == 0 ? '关闭字幕' : '字幕 $index'),
          selected: _currentSubtitleIndex == index - 1,
          onTap: () {
            setState(() {
              _currentSubtitleIndex = index - 1;
              // TODO: 实现字幕切换
            });
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _showQualitySelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: _qualities.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(_qualities[index]['name']),
          selected: _currentQualityIndex == index,
          onTap: () {
            setState(() {
              _currentQualityIndex = index;
              // TODO: 实现清晰度切换
            });
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}