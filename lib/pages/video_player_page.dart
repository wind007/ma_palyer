import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/emby_api.dart';

class VideoPlayerPage extends StatefulWidget {
  final String itemId;
  final String title;
  final EmbyApiService embyApi;
  final bool fromStart;

  const VideoPlayerPage({
    super.key,
    required this.itemId,
    required this.title,
    required this.embyApi,
     required this.fromStart,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  Timer? _progressTimer;
  bool _isInitializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      // 获取视频播放URL和上次播放位置
      final url = await widget.embyApi.getPlaybackUrl(widget.itemId);
      final playbackInfo = await widget.embyApi.getPlaybackInfo(widget.itemId);
      final position = await widget.embyApi.getPlaybackPosition(widget.itemId);
      final mediaSourceId = playbackInfo['MediaSources'][0]['Id'];
      
      print('播放URL: $url');

      _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      )..initialize().then((_) async {
        if (!widget.fromStart && position > 0) {
          await _controller?.seekTo(Duration(microseconds: (position ~/ 10)));
        }
        _controller?.play();
        setState(() {
          _isInitializing = false;
        });

        // 启动定时更新
        _progressTimer?.cancel();
        _progressTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
          if (_controller?.value.isPlaying == true) {
            widget.embyApi.updatePlaybackProgress(
              itemId: widget.itemId,
              positionTicks: (_controller!.value.position.inMicroseconds * 10).toInt(),
              isPaused: false,
            );
          }
        });
      });

    } catch (e) {
      print('初始化播放器失败: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    if (_controller?.value.isInitialized == true) {
      widget.embyApi.updatePlaybackProgress(
        itemId: widget.itemId,
        positionTicks: (_controller!.value.position.inMicroseconds * 10).toInt(),
        isPaused: true,
      );
    }
    _controller?.dispose();
    widget.embyApi.stopPlayback(widget.itemId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(child: Text('错误: $_error')),
      );
    }

    if (_isInitializing || _controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder(
            valueListenable: _controller!,
            builder: (context, VideoPlayerValue value, child) {
              return Column(
                children: [
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
                              _controller?.seekTo(Duration(milliseconds: newPosition.toInt()));
                              // 拖动进度条后立即更新进度
                              widget.embyApi.updatePlaybackProgress(
                                itemId: widget.itemId,
                                positionTicks: (newPosition.toInt() * 10000),
                                isPaused: !(_controller?.value.isPlaying ?? false),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${value.position.inMinutes}:${(value.position.inSeconds % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          '${value.duration.inMinutes}:${(value.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: ValueListenableBuilder(
        valueListenable: _controller!,
        builder: (context, VideoPlayerValue value, child) {
          return FloatingActionButton(
            onPressed: () {
              setState(() {
                if (value.isPlaying) {
                  _controller?.pause();
                  // 暂停时立即更新进度
                  widget.embyApi.updatePlaybackProgress(
                    itemId: widget.itemId,
                    positionTicks: (_controller!.value.position.inMicroseconds * 10).toInt(),
                    isPaused: true,
                  );
                } else {
                  _controller?.play();
                  widget.embyApi.updatePlaybackProgress(
                    itemId: widget.itemId,
                    positionTicks: (_controller!.value.position.inMicroseconds * 10).toInt(),
                    isPaused: false,
                  );
                }
              });
            },
            child: Icon(
              value.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
          );
        },
      ),
    );
  }
} 