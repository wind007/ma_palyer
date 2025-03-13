// ignore_for_file: unused_field

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // 播放器控制器
  VideoPlayerController? _controller;
  
  // 定时器
  Timer? _progressTimer;      // 进度更新定时器
  Timer? _hideControlsTimer;  // 控制栏隐藏定时器
  Timer? _seekIndicatorTimer; // 快进快退指示器定时器
  
  // 状态标记
  bool _isInitializing = true;  // 初始化状态
  bool _isDragging = false;     // 是否正在拖动进度条
  String? _error;               // 错误信息
  bool _showControls = false;   // 是否显示控制栏
  int _retryCount = 0;          // 重试次数
  Duration _dragPosition = Duration.zero;   // 当前拖动位置
  
  // 播放控制
  double _currentVolume = 1.0;   // 当前音量
  double _lastVolume = 1.0;      // 静音前的音量
  bool _isFullScreen = false;    // 全屏状态
  double _playbackSpeed = 1.0;   // 播放速度
  double _brightness = 0.0;      // 当前亮度

  // 手势控制
  double? _dragStartX;           // 水平拖动起始位置
  double? _dragStartY;           // 垂直拖动起始位置
  double? _dragStartProgress;    // 拖动开始时的播放进度
  bool _isDraggingProgress = false;  // 是否正在拖动进度条
  bool _isDraggingVolume = false;    // 是否正在调节音量
  bool _isDraggingBrightness = false; // 是否正在调节亮度
  bool _showVolumeIndicator = false;  // 是否显示音量指示器
  bool _showBrightnessIndicator = false; // 是否显示亮度指示器
  bool _showSeekIndicator = false;    // 是否显示快进快退指示器
  bool _showPreviewTime = false;      // 是否显示预览时间
  int _seekSeconds = 0;         // 快进快退秒数
  Duration _previewPosition = Duration.zero; // 预览位置

  // 常量
  static const _maxRetries = 3;         // 最大重试次数
  static const _volumeStep = 0.05;      // 音量调节步长
  static const _progressInterval = 30;   // 进度更新间隔（秒）
  static const _controlsTimeout = 3;     // 控制栏显示时间（秒）

  // 样式常量
  static const _controlBarGradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      Colors.black54,
      Colors.transparent,
    ],
  );

  @override
  void initState() {
    super.initState();
    // 设置横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 设置全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initializePlayer();
    _initializeBrightness();
  }

  Future<void> _initializeBrightness() async {
    try {
      final window = WidgetsBinding.instance.window;
      _brightness = window.platformBrightness == Brightness.dark ? 0.3 : 0.7;
    } catch (e) {
      print('获取系统亮度失败: $e');
    }
  }

  Future<void> _initializePlayer() async {
    try {
      // 获取视频播放URL和信息
      final url = await widget.embyApi.getPlaybackUrl(widget.itemId);
      if (url.isEmpty) {
        throw Exception('无法获取播放地址');
      }

      final playbackInfo = await widget.embyApi.getPlaybackInfo(widget.itemId);
      if (playbackInfo['MediaSources'] == null || playbackInfo['MediaSources'].isEmpty) {
        throw Exception('无法获取媒体信息');
      }

      final position = await widget.embyApi.getPlaybackPosition(widget.itemId);
      
      // 初始化播放器
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      // 添加错误监听
      _controller?.addListener(_onPlayerStateChanged);

      await _controller?.initialize();
      
      if (!mounted) return;

      // 设置初始位置和开始播放
      if (!widget.fromStart && position > 0) {
        await _controller?.seekTo(Duration(microseconds: (position ~/ 10)));
      }
      await _controller?.play();
      
      setState(() {
        _isInitializing = false;
      });

      // 启动定时更新
      _startProgressTimer();

    } catch (e) {
      print('初始化播放器失败: $e');
      if (_retryCount < _maxRetries) {
        _retryCount++;
        await Future.delayed(const Duration(seconds: 1));
        await _initializePlayer();
      } else if (mounted) {
        setState(() {
          _error = '初始化失败，请检查网络连接';
          _isInitializing = false;
        });
      }
    }
  }

  void _onPlayerStateChanged() {
    if (_controller == null || !mounted) return;

    final playerValue = _controller!.value;
    
    // 错误处理
    if (playerValue.hasError) {
      setState(() {
        _error = '播放错误: ${playerValue.errorDescription}';
      });
      return;
    }

    // 播放完成处理
    if (playerValue.position >= playerValue.duration) {
      _updateProgress(isPaused: true);
      // 可以在这里添加播放完成的其他处理
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(seconds: _progressInterval),
      (timer) {
        if (_controller?.value.isPlaying == true && !_isDragging) {
          _updateProgress();
        }
      },
    );
  }

  void _updateProgress({bool isPaused = false}) {
    if (_controller?.value.isInitialized ?? false) {
      widget.embyApi.updatePlaybackProgress(
        itemId: widget.itemId,
        positionTicks: (_controller!.value.position.inMicroseconds * 10).toInt(),
        isPaused: isPaused,
      );
    }
  }

  void _startHideControlsTimer() {
    if (_isDragging) return;
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(
      const Duration(seconds: _controlsTimeout),
      () {
        if (mounted) {
          setState(() => _showControls = false);
        }
      },
    );
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startHideControlsTimer();
      }
    });
  }

  void _adjustVolume(double delta) {
    setState(() {
      _currentVolume = (_currentVolume + delta).clamp(0.0, 1.0);
      _controller?.setVolume(_currentVolume);
    });
  }

  void _seekRelative(Duration offset) {
    if (_controller?.value.isInitialized ?? false) {
      final newPosition = _controller!.value.position + offset;
      final duration = _controller!.value.duration;
      
      Duration targetPosition;
      if (newPosition < Duration.zero) {
        targetPosition = Duration.zero;
      } else if (newPosition > duration) {
        targetPosition = duration;
      } else {
        targetPosition = newPosition;
      }

      _controller?.seekTo(targetPosition);
      _updateProgress(isPaused: !(_controller?.value.isPlaying ?? false));
      _startHideControlsTimer();
    }
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      _showControls = true;
      _startHideControlsTimer();
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
    _seekIndicatorTimer?.cancel();
    _controller?.removeListener(_onPlayerStateChanged);
    if (_controller?.value.isInitialized == true) {
      _updateProgress(isPaused: true);
    }
    _controller?.dispose();
    widget.embyApi.stopPlayback(widget.itemId);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildErrorView();
    }

    if (_isInitializing || _controller == null) {
      return _buildLoadingView();
    }

    return Scaffold(
      body: Stack(
        children: [
          _buildVideoPlayer(),
          if (_showControls) ...[
            _buildTopBar(),
            _buildVolumeControl(),
            _buildSeekButtons(),
            _buildBottomBar(),
          ],
          if (_showControls) _buildPlayPauseButton(),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Scaffold(
      body: Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                '播放错误',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    '返回',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Scaffold(
      body: Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Colors.red,
              ),
              SizedBox(height: 16),
              Text(
                '正在加载视频...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return RawKeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.space) {
            _togglePlayPause();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _seekRelative(const Duration(seconds: -10));
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _seekRelative(const Duration(seconds: 10));
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _adjustVolume(_volumeStep);
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _adjustVolume(-_volumeStep);
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
          }
        }
      },
      child: GestureDetector(
        onTap: _toggleControls,
        onDoubleTapDown: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < screenWidth / 3) {
            _showSeekAnimation(-10);
            _seekRelative(const Duration(seconds: -10));
          } else if (details.globalPosition.dx > screenWidth * 2 / 3) {
            _showSeekAnimation(10);
            _seekRelative(const Duration(seconds: 10));
          }
        },
        onHorizontalDragStart: (details) {
          if (_controller?.value.isInitialized != true) return;
          _dragStartX = details.globalPosition.dx;
          _dragStartProgress = _controller!.value.position.inMilliseconds.toDouble();
          _isDraggingProgress = true;
          _previewPosition = _controller!.value.position;
          setState(() {
            _showControls = true;
            _isDragging = true;
          });
          _hideControlsTimer?.cancel();
        },
        onHorizontalDragUpdate: (details) {
          if (!_isDraggingProgress || _dragStartX == null || _dragStartProgress == null) return;
          
          final width = MediaQuery.of(context).size.width;
          final dx = details.globalPosition.dx - _dragStartX!;
          final percentage = dx / width;
          
          final duration = _controller!.value.duration;
          final newPosition = _dragStartProgress! + (duration.inMilliseconds * percentage);
          
          setState(() {
            _previewPosition = Duration(milliseconds: newPosition.toInt().clamp(0, duration.inMilliseconds));
          });
        },
        onHorizontalDragEnd: (details) {
          if (_isDraggingProgress) {
            _controller?.seekTo(_previewPosition);
            setState(() {
              _isDragging = false;
            });
            _isDraggingProgress = false;
            _dragStartX = null;
            _dragStartProgress = null;
            _startHideControlsTimer();
          }
        },
        onVerticalDragStart: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          _dragStartY = details.globalPosition.dy;
          
          // 左半边屏幕控制亮度，右半边屏幕控制音量
          if (details.globalPosition.dx < screenWidth / 2) {
            _isDraggingBrightness = true;
            setState(() {
              _showBrightnessIndicator = true;
            });
          } else {
            _isDraggingVolume = true;
            setState(() {
              _showVolumeIndicator = true;
            });
          }
        },
        onVerticalDragUpdate: (details) {
          if (_dragStartY == null) return;
          
          // 计算垂直滑动距离相对于屏幕高度的比例
          final height = MediaQuery.of(context).size.height;
          final dy = _dragStartY! - details.globalPosition.dy;
          final percentage = dy / height;
          
          if (_isDraggingVolume) {
            // 调节音量
            setState(() {
              _currentVolume = (_currentVolume + percentage).clamp(0.0, 1.0);
              _controller?.setVolume(_currentVolume);
            });
          } else if (_isDraggingBrightness) {
            // 调节亮度
            setState(() {
              _brightness = (_brightness + percentage).clamp(0.0, 1.0);
              SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
                statusBarBrightness: _brightness > 0.5 ? Brightness.dark : Brightness.light,
              ));
            });
          }
          
          _dragStartY = details.globalPosition.dy;
        },
        onVerticalDragEnd: (_) {
          _dragStartY = null;
          _isDraggingVolume = false;
          _isDraggingBrightness = false;
          
          // 延迟隐藏指示器
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              setState(() {
                _showVolumeIndicator = false;
                _showBrightnessIndicator = false;
              });
            }
          });
        },
        child: Stack(
          children: [
            Center(
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
            if (_showSeekIndicator)
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.of(context).size.height / 6,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _seekSeconds < 0 ? Icons.fast_rewind : Icons.fast_forward,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_seekSeconds.abs()}秒',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_showPreviewTime)
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.of(context).size.height / 6,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(_previewPosition),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_showVolumeIndicator)
              Positioned(
                right: MediaQuery.of(context).size.width / 4,
                top: MediaQuery.of(context).size.height / 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _currentVolume == 0
                            ? Icons.volume_off
                            : _currentVolume < 0.5
                                ? Icons.volume_down
                                : Icons.volume_up,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(_currentVolume * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_showBrightnessIndicator)
              Positioned(
                left: MediaQuery.of(context).size.width / 4,
                top: MediaQuery.of(context).size.height / 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _brightness < 0.3
                            ? Icons.brightness_low
                            : _brightness < 0.7
                                ? Icons.brightness_medium
                                : Icons.brightness_high,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(_brightness * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSeekAnimation(int seconds) {
    setState(() {
      _seekSeconds = seconds;
      _showSeekIndicator = true;
    });
    _seekIndicatorTimer?.cancel();
    _seekIndicatorTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showSeekIndicator = false;
        });
      }
    });
  }

  Widget _buildTopBar() {
    return Positioned(
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
    );
  }

  Widget _buildVolumeControl() {
    return Positioned(
      right: 16,
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
    );
  }

  Widget _buildSeekButtons() {
    return Positioned(
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
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: _controlBarGradient,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProgressBar(),
            const SizedBox(height: 8),
            _buildControlBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return ValueListenableBuilder(
      valueListenable: _controller!,
      builder: (context, VideoPlayerValue value, child) {
        final duration = value.duration;
        final position = _isDragging ? _previewPosition : value.position;

        return Stack(
          clipBehavior: Clip.none,
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
                value: position.inMilliseconds.toDouble(),
                min: 0.0,
                max: duration.inMilliseconds.toDouble(),
                onChangeStart: (value) {
                  setState(() {
                    _isDragging = true;
                    _previewPosition = Duration(milliseconds: value.toInt());
                  });
                  _hideControlsTimer?.cancel();
                },
                onChanged: (value) {
                  setState(() {
                    _previewPosition = Duration(milliseconds: value.toInt());
                  });
                },
                onChangeEnd: (value) {
                  final newPosition = Duration(milliseconds: value.toInt());
                  _controller?.seekTo(newPosition);
                  setState(() {
                    _isDragging = false;
                  });
                  _updateProgress(isPaused: !(_controller?.value.isPlaying ?? false));
                  _startHideControlsTimer();
                },
              ),
            ),
            if (_isDragging)
              Positioned(
                left: (position.inMilliseconds / duration.inMilliseconds) * 
                  (MediaQuery.of(context).size.width - 64) - 30, // 调整位置以居中显示
                bottom: 20, // 调整到滑块上方
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(position),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildControlBar() {
    return ValueListenableBuilder(
      valueListenable: _controller!,
      builder: (context, VideoPlayerValue value, child) {
        return Row(
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
                _buildPlaybackSpeedButton(),
                const SizedBox(width: 8),
                _buildFullScreenButton(),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlaybackSpeedButton() {
    return GestureDetector(
      onTap: _showPlaybackSpeedDialog,
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
    );
  }

  Widget _buildFullScreenButton() {
    return GestureDetector(
      onTap: _toggleFullScreen,
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
    );
  }

  Widget _buildPlayPauseButton() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _togglePlayPause,
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
    );
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller?.pause();
        _updateProgress(isPaused: true);
      } else {
        _controller?.play();
        _updateProgress(isPaused: false);
      }
      _startHideControlsTimer();
    });
  }

  void _showPlaybackSpeedDialog() {
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