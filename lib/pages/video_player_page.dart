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
  Timer? _hideControlsTimer;
  bool _isInitializing = true;
  String? _error;
  bool _showControls = false;
  double _currentVolume = 1.0;
  double _lastVolume = 1.0;  // 添加这个变量来记住静音前的音量
  bool _isFullScreen = false;  // 添加缩放模式状态
  double _playbackSpeed = 1.0;  // 添加播放速度状态

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
        _progressTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
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

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startHideControlsTimer();
      }
    });
  }

  void _seekRelative(Duration offset) {
    if (_controller?.value.isInitialized ?? false) {
      final newPosition = _controller!.value.position + offset;
      final duration = _controller!.value.duration;
      
      if (newPosition < Duration.zero) {
        _controller?.seekTo(Duration.zero);
      } else if (newPosition > duration) {
        _controller?.seekTo(duration);
      } else {
        _controller?.seekTo(newPosition);
      }
      
      // 更新进度
      widget.embyApi.updatePlaybackProgress(
        itemId: widget.itemId,
        positionTicks: (newPosition.inMicroseconds * 10).toInt(),
        isPaused: !(_controller?.value.isPlaying ?? false),
      );
      
      _startHideControlsTimer();
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
      body: SafeArea(
        child: Stack(
          children: [
            // 视频播放器
            GestureDetector(
              onTap: _toggleControls,
              onDoubleTapDown: (details) {
                final screenWidth = MediaQuery.of(context).size.width;
                if (details.globalPosition.dx < screenWidth / 2) {
                  _seekRelative(const Duration(seconds: -10));
                } else {
                  _seekRelative(const Duration(seconds: 10));
                }
              },
              child: Center(
                child: _isFullScreen
                    ? SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _controller!.value.size.width,
                            height: _controller!.value.size.height,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                      )
                    : AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
              ),
            ),

            // 控制层
            if (_showControls) ...[
              // 顶部控制栏
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 音量控制 - 左侧垂直布局
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          icon: Icon(
                            _currentVolume == 0
                                ? Icons.volume_off
                                : _currentVolume < 0.5
                                    ? Icons.volume_down
                                    : Icons.volume_up,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              if (_currentVolume > 0) {
                                _lastVolume = _currentVolume;
                                _currentVolume = 0;
                              } else {
                                _currentVolume = _lastVolume;
                              }
                              _controller?.setVolume(_currentVolume);
                            });
                            _startHideControlsTimer();
                          },
                        ),
                        const SizedBox(height: 4),
                        RotatedBox(
                          quarterTurns: 3,
                          child: SizedBox(
                            width: 80,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.red,
                                inactiveTrackColor: Colors.white.withOpacity(0.3),
                                thumbColor: Colors.red,
                                trackHeight: 2.0,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6.0,
                                ),
                                overlayColor: Colors.red.withAlpha(32),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12.0,
                                ),
                              ),
                              child: Slider(
                                value: _currentVolume,
                                onChanged: (value) {
                                  setState(() {
                                    _currentVolume = value;
                                    _controller?.setVolume(value);
                                  });
                                  _startHideControlsTimer();
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 快进快退指示
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.of(context).size.height / 2 - 50,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10, color: Colors.white, size: 40),
                      onPressed: () => _seekRelative(const Duration(seconds: -10)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_10, color: Colors.white, size: 40),
                      onPressed: () => _seekRelative(const Duration(seconds: 10)),
                    ),
                  ],
                ),
              ),

              // 底部控制栏
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 进度条
                      ValueListenableBuilder(
                        valueListenable: _controller!,
                        builder: (context, VideoPlayerValue value, child) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: Colors.red,
                                  inactiveTrackColor: Colors.white.withOpacity(0.3),
                                  thumbColor: Colors.red,
                                  trackHeight: 2.0,
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
                                    widget.embyApi.updatePlaybackProgress(
                                      itemId: widget.itemId,
                                      positionTicks: (newPosition.toInt() * 10000),
                                      isPaused: !(_controller?.value.isPlaying ?? false),
                                    );
                                    _startHideControlsTimer();
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(value.position),
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          _formatDuration(value.duration),
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                        const SizedBox(width: 16),
                                        // 倍速播放按钮
                                        GestureDetector(
                                          onTap: () {
                                            showDialog(
                                              context: context,
                                              builder: (context) => Dialog(
                                                backgroundColor: Colors.black87,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Padding(
                                                        padding: EdgeInsets.only(bottom: 16),
                                                        child: Text(
                                                          '播放速度',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                      for (var speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                                                        InkWell(
                                                          onTap: () {
                                                            setState(() {
                                                              _playbackSpeed = speed;
                                                              _controller?.setPlaybackSpeed(speed);
                                                            });
                                                            Navigator.pop(context);
                                                            _startHideControlsTimer();
                                                          },
                                                          child: Container(
                                                            padding: const EdgeInsets.symmetric(
                                                              vertical: 12,
                                                              horizontal: 24,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: _playbackSpeed == speed
                                                                  ? Colors.red.withOpacity(0.3)
                                                                  : Colors.transparent,
                                                            ),
                                                            child: Text(
                                                              '${speed}x',
                                                              style: TextStyle(
                                                                color: _playbackSpeed == speed
                                                                    ? Colors.red
                                                                    : Colors.white,
                                                                fontSize: 15,
                                                              ),
                                                              textAlign: TextAlign.center,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black38,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.speed,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${_playbackSpeed}x',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // 缩放按钮
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _isFullScreen = !_isFullScreen;
                                            });
                                            _startHideControlsTimer();
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black38,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Icon(
                                              _isFullScreen ? Icons.fit_screen : Icons.fullscreen,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ],
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
                ),
              ),
            ],

            // 播放/暂停按钮
            if (_showControls)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_controller!.value.isPlaying) {
                        _controller?.pause();
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
                      _startHideControlsTimer();
                    });
                  },
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
} 