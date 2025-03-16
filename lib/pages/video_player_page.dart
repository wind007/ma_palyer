// ignore_for_file: unused_field

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../services/emby_api.dart';
import '../utils/logger.dart';

class VideoPlayerPage extends StatefulWidget {
  final String itemId;
  final String title;
  final EmbyApiService embyApi;
  final bool fromStart;
  final int? mediaSourceIndex;
  final int? initialAudioStreamIndex;
  final int? initialSubtitleStreamIndex;
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;

  const VideoPlayerPage({
    super.key,
    required this.itemId,
    required this.title,
    required this.embyApi,
    this.fromStart = false,
    this.mediaSourceIndex,
    this.initialAudioStreamIndex,
    this.initialSubtitleStreamIndex,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  static const String _tag = "VideoPlayer";
  
  // 常量定义
  static const _maxRetries = 3;         // 最大重试次数
  static const _volumeStep = 0.05;      // 音量调节步长
  static const _progressInterval = 30;   // 进度更新间隔（秒）
  static const _controlsTimeout = 3;     // 控制栏显示时间（秒）
  static const _indicatorTopPosition = 6.0; // 提示块位置系数（1/6）
  static const _seekButtonSize = 40.0;   // 快进快退按钮大小
  static const _volumeControlWidth = 80.0; // 音量控制条宽度

  // 样式常量
  static const _controlBarGradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Colors.black54, Colors.transparent],
  );

  static const _topBarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.black87, Colors.transparent],
  );

  static const _indicatorDecoration = BoxDecoration(
    color: Colors.black54,
    borderRadius: BorderRadius.all(Radius.circular(6)),
  );

  static const _buttonDecoration = BoxDecoration(
    color: Colors.black38,
    borderRadius: BorderRadius.all(Radius.circular(4)),
  );

  static const _indicatorPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );

  static const _buttonPadding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 4,
  );

  static const _indicatorTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 16,
  );

  static const _timeTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 14,
  );

  static final _sliderThemeData = SliderThemeData(
    activeTrackColor: Colors.red,
    inactiveTrackColor: Colors.white.withAlpha(77),
    thumbColor: Colors.red,
    trackHeight: 2.0,
    thumbShape: const RoundSliderThumbShape(
      enabledThumbRadius: 6.0,
    ),
    overlayColor: Colors.red.withAlpha(32),
    overlayShape: const RoundSliderOverlayShape(
      overlayRadius: 12.0,
    ),
  );

  static const _errorMessages = {
    'no_url': '无法获取播放地址',
    'no_media': '无法获取媒体信息',
    'init_failed': '初始化失败，请检查网络连接',
  };

  // 播放器控制器
  VideoPlayerController? _controller;
  
  // 定时器
  Timer? _progressTimer;      // 进度更新定时器
  Timer? _hideControlsTimer;  // 控制栏隐藏定时器
  Timer? _seekIndicatorTimer; // 快进快退指示器定时器
  
  // 状态标记
  bool _isInitializing = true;  // 初始化状态
  bool _isDragging = false;     // 是否正在拖动
  String? _error;               // 错误信息
  bool _showControls = false;   // 是否显示控制栏
  int _retryCount = 0;          // 重试次数
    
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
  bool _isDraggingVolume = false;    // 是否正在调节音量
  bool _isDraggingBrightness = false; // 是否正在调节亮度
  bool _showVolumeIndicator = false;  // 是否显示音量指示器
  bool _showBrightnessIndicator = false; // 是否显示亮度指示器
  bool _showSeekIndicator = false;    // 是否显示快进快退指示器
  int _seekSeconds = 0;         // 快进快退秒数
  Duration _previewPosition = Duration.zero; // 预览位置

  // 添加新的状态变量
  Map<String, dynamic>? _playbackInfo;
  int? _currentAudioStreamIndex;
  int? _currentSubtitleStreamIndex;
  List<dynamic>? _audioStreams;
  List<dynamic>? _subtitleStreams;
  Map<String, dynamic>? _nextEpisode;

  @override
  void initState() {
    super.initState();
    Logger.i("初始化视频播放页面 - 视频ID: ${widget.itemId}, 标题: ${widget.title}", _tag);
    
    // 设置横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    Logger.d("设置横屏模式", _tag);
    
    // 设置全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Logger.d("设置全屏模式", _tag);
    
    _initializePlayer();
    _initializeBrightness();
  }

  Future<void> _initializeBrightness() async {
    Logger.d("初始化屏幕亮度", _tag);
    try {
      // ignore: deprecated_member_use
      final window = WidgetsBinding.instance.window;
      _brightness = window.platformBrightness == Brightness.dark ? 0.3 : 0.7;
      Logger.d("设置初始亮度: $_brightness", _tag);
    } catch (e, stackTrace) {
      Logger.e("获取系统亮度失败", _tag, e, stackTrace);
    }
  }

  Future<void> _initializePlayer() async {
    Logger.i("开始初始化播放器", _tag);
    try {
      // 获取视频播放URL和信息
      Logger.d("获取播放地址", _tag);
      
      // 获取媒体信息
      Logger.d("获取媒体信息", _tag);
      _playbackInfo = await widget.embyApi.getPlaybackInfo(widget.itemId);
      if (_playbackInfo == null || _playbackInfo!['MediaSources'] == null || _playbackInfo!['MediaSources'].isEmpty) {
        Logger.e("获取媒体信息失败：MediaSources为空", _tag);
        throw Exception('无法获取媒体信息');
      }
      
      // 获取音频和字幕流
      final mediaSource = _playbackInfo!['MediaSources'][widget.mediaSourceIndex ?? 0];
      _audioStreams = mediaSource['MediaStreams']?.where((s) => s['Type'] == 'Audio')?.toList();
      _subtitleStreams = mediaSource['MediaStreams']?.where((s) => s['Type'] == 'Subtitle')?.toList();
      
      _currentAudioStreamIndex = widget.initialAudioStreamIndex ?? mediaSource['DefaultAudioStreamIndex'];
      _currentSubtitleStreamIndex = widget.initialSubtitleStreamIndex ?? mediaSource['DefaultSubtitleStreamIndex'];
      
      Logger.d("音频流数量: ${_audioStreams?.length}, 字幕流数量: ${_subtitleStreams?.length}", _tag);
      Logger.d("当前音频流: $_currentAudioStreamIndex, 当前字幕流: $_currentSubtitleStreamIndex", _tag);

      final url = await widget.embyApi.getPlaybackUrl(
        widget.itemId,
        mediaSourceIndex: widget.mediaSourceIndex,
        audioStreamIndex: _currentAudioStreamIndex,
        subtitleStreamIndex: _currentSubtitleStreamIndex,
      );
      if (url.isEmpty) {
        Logger.e("获取播放地址失败：地址为空", _tag);
        throw Exception('无法获取播放地址');
      }
      Logger.d("成功获取播放地址: $url", _tag);

      Logger.d("获取播放位置", _tag);
      final position = await widget.embyApi.getPlaybackPosition(widget.itemId);
      Logger.d("当前播放位置: $position", _tag);
      
      // 初始化播放器
      Logger.d("初始化播放器控制器", _tag);
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      // 添加错误监听
      _controller?.addListener(_onPlayerStateChanged);
      Logger.d("添加播放器状态监听器", _tag);

      await _controller?.initialize();
      Logger.d("播放器控制器初始化完成", _tag);
      
      if (!mounted) {
        Logger.w("页面已卸载，取消后续初始化", _tag);
        return;
      }

      // 设置初始位置和开始播放
      if (!widget.fromStart && position > 0) {
        Logger.d("设置初始播放位置: ${position ~/ 10}微秒", _tag);
        await _controller?.seekTo(Duration(microseconds: (position ~/ 10)));
      }
      
      await _controller?.play();
      Logger.i("开始播放视频", _tag);
      
      setState(() {
        _isInitializing = false;
      });

      // 启动定时更新
      _startProgressTimer();
      Logger.d("启动进度更新定时器", _tag);

    } catch (e, stackTrace) {
      Logger.e("初始化播放器失败", _tag, e, stackTrace);
      if (_retryCount < _maxRetries) {
        _retryCount++;
        Logger.w("准备第$_retryCount次重试", _tag);
        await Future.delayed(const Duration(seconds: 1));
        await _initializePlayer();
      } else if (mounted) {
        Logger.e("超过最大重试次数，显示错误信息", _tag);
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
      Logger.e("播放器错误: ${playerValue.errorDescription}", _tag);
      setState(() {
        _error = '播放错误: ${playerValue.errorDescription}';
      });
      return;
    }

    // 播放完成处理
    if (playerValue.position >= playerValue.duration) {
      Logger.i("视频播放完成，当前位置: ${playerValue.position.inSeconds}秒，总时长: ${playerValue.duration.inSeconds}秒", _tag);
      _updateProgress(isPaused: true);
      
      // 等待获取下一集信息后再决定是否播放
      _handleVideoCompletion().then((_) {
        if (!mounted) return;
        
        if (_nextEpisode != null) {
          Logger.i("准备播放下一集: ${_nextEpisode!['Name']}, ID: ${_nextEpisode!['Id']}", _tag);
          _playNextEpisode();
        } else {
          Logger.i("没有下一集信息，返回上一页", _tag);
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      });
    }
  }

  Future<void> _handleVideoCompletion() async {
    Logger.i("处理视频播放完成", _tag);
    if (widget.seriesId == null || widget.seasonNumber == null || widget.episodeNumber == null) {
      Logger.w("无法加载下一集：缺少必要信息 - seriesId: ${widget.seriesId}, seasonNumber: ${widget.seasonNumber}, episodeNumber: ${widget.episodeNumber}", _tag);
      return;
    }

    try {
      Logger.d("开始获取下一集信息 - seriesId: ${widget.seriesId}, seasonNumber: ${widget.seasonNumber}, episodeNumber: ${widget.episodeNumber}", _tag);
      final response = await widget.embyApi.getEpisodes(
        seriesId: widget.seriesId!,
        userId: widget.embyApi.userId!,
        seasonNumber: widget.seasonNumber,
        fields: 'Path,MediaSources,UserData',
      );

      if (response['Items'] != null) {
        final episodes = response['Items'] as List;
        Logger.d("获取到 ${episodes.length} 集", _tag);
        
        // 查找当前集的下一集
        for (int i = 0; i < episodes.length; i++) {
          final episode = episodes[i];
          final indexNumber = episode['IndexNumber'];
          if (indexNumber != null && indexNumber > widget.episodeNumber!) {
            setState(() {
              _nextEpisode = episode;
            });
            Logger.i("找到下一集: ${_nextEpisode!['Name']}, 集数: $indexNumber", _tag);
            break;
          }
        }
        
        if (_nextEpisode == null) {
          Logger.w("未找到下一集", _tag);
        }
      } else {
        Logger.w("获取剧集列表失败：返回数据为空", _tag);
      }
    } catch (e, stackTrace) {
      Logger.e("获取下一集信息失败", _tag, e, stackTrace);
    }
  }

  void _clearTimers() {
    Logger.d("清理所有定时器", _tag);
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
    _seekIndicatorTimer?.cancel();
  }

  void _startProgressTimer() {
    Logger.d("启动进度更新定时器", _tag);
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

  void _startHideControlsTimer() {
    Logger.v("启动控制栏隐藏定时器", _tag);
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(
      const Duration(seconds: _controlsTimeout),
      () {
        if (mounted && _showControls && !_isDragging) {
          Logger.v("自动隐藏控制栏", _tag);
          setState(() => _showControls = false);
        }
      },
    );
  }


  void _showSeekAnimation(int seconds) {
    Logger.v("显示快进/快退动画: $seconds秒", _tag);
    setState(() {
      _seekSeconds = seconds;
      _showSeekIndicator = true;
    });
    
    _seekIndicatorTimer?.cancel();
    _seekIndicatorTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _showSeekIndicator = false;
          _seekSeconds = 0;
        });
      }
    });
  }

  Future<void> _updateProgress({bool isPaused = false}) async {
    Logger.v("更新播放进度 - isPaused: $isPaused", _tag);
    try {
      if (_controller == null || !mounted) return;
      final position = _controller!.value.position;
      await widget.embyApi.updatePlaybackProgress(
        itemId: widget.itemId,
        positionTicks: position.inMicroseconds * 10,
        isPaused: isPaused,
      );
      Logger.v("播放进度更新成功 - 位置: ${position.inSeconds}秒", _tag);
    } catch (e, stackTrace) {
      Logger.e("更新播放进度失败", _tag, e, stackTrace);
    }
  }

  void _toggleControls() {
    Logger.d("切换控制栏显示状态", _tag);
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startHideControlsTimer();
      } else {
        _hideControlsTimer?.cancel();
      }
    });
    Logger.d("控制栏显示状态: ${_showControls ? '显示' : '隐藏'}", _tag);
  }

  void _adjustVolume(double delta) {
    Logger.d("调整音量: $delta", _tag);
    if (_controller == null) {
      Logger.w("播放器控制器未初始化", _tag);
      return;
    }
    
    setState(() {
      _currentVolume = (_currentVolume + delta).clamp(0.0, 1.0);
      _controller!.setVolume(_currentVolume);
      _showVolumeIndicator = true;
    });
    Logger.d("当前音量: $_currentVolume", _tag);
  }

  void _seekRelative(Duration offset) {
    Logger.d("相对跳转: ${offset.inSeconds}秒", _tag);
    if (_controller == null) {
      Logger.w("播放器控制器未初始化", _tag);
      return;
    }
    
    final current = _controller!.value.position;
    final duration = _controller!.value.duration;
    final targetPosition = current + offset;
    
    if (targetPosition < Duration.zero) {
      _controller!.seekTo(Duration.zero);
      Logger.d("跳转到开始位置", _tag);
    } else if (targetPosition > duration) {
      _controller!.seekTo(duration);
      Logger.d("跳转到结束位置", _tag);
    } else {
      _controller!.seekTo(targetPosition);
      Logger.d("跳转到: ${targetPosition.inSeconds}秒", _tag);
    }
  }

  void _toggleFullScreen() {
    Logger.d("切换全屏状态", _tag);
    setState(() {
      _isFullScreen = !_isFullScreen;
      if (_isFullScreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        Logger.d("进入全屏模式", _tag);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        Logger.d("退出全屏模式", _tag);
      }
    });
  }

  @override
  void dispose() {
    Logger.i("销毁视频播放页面", _tag);
    _clearTimers();
    _controller?.removeListener(_onPlayerStateChanged);
    if (_controller?.value.isInitialized == true) {
      Logger.d("更新最终播放进度", _tag);
      _updateProgress(isPaused: true);
    }
    Logger.d("释放播放器控制器", _tag);
    _controller?.dispose();
    Logger.d("停止播放", _tag);
    widget.embyApi.stopPlayback(widget.itemId);
    Logger.d("恢复屏幕方向为竖屏", _tag);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    Logger.d("恢复系统UI显示模式", _tag);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
    Logger.i("视频播放页面销毁完成", _tag);
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
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.space) {
            _togglePlayPause();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _seekRelative(const Duration(seconds: -10));
            _showSeekAnimation(-10);
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _seekRelative(const Duration(seconds: 10));
            _showSeekAnimation(10);
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
            _seekRelative(const Duration(seconds: -10));
            _showSeekAnimation(-10);
          } else if (details.globalPosition.dx > screenWidth * 2 / 3) {
            _seekRelative(const Duration(seconds: 10));
            _showSeekAnimation(10);
          }
        },
        onHorizontalDragStart: onHorizontalDragStart,
        onHorizontalDragUpdate: onHorizontalDragUpdate,
        onHorizontalDragEnd: onHorizontalDragEnd,
        onVerticalDragStart: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          _dragStartY = details.globalPosition.dy;
          
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
          
          final height = MediaQuery.of(context).size.height;
          final dy = _dragStartY! - details.globalPosition.dy;
          final percentage = dy / height;
          
          if (_isDraggingVolume) {
            setState(() {
              _currentVolume = (_currentVolume + percentage).clamp(0.0, 1.0);
              _controller?.setVolume(_currentVolume);
            });
          } else if (_isDraggingBrightness) {
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
                top: MediaQuery.of(context).size.height / _indicatorTopPosition,
                child: Center(
                  child: _buildIndicator(
                    icon: _seekSeconds < 0 ? Icons.fast_rewind : Icons.fast_forward,
                    text: '${_seekSeconds.abs()}秒',
                  ),
                ),
              ),
            if (_showVolumeIndicator)
              Positioned(
                right: MediaQuery.of(context).size.width / 4,
                top: MediaQuery.of(context).size.height / _indicatorTopPosition,
                child: _buildIndicator(
                  icon: _currentVolume == 0
                      ? Icons.volume_off
                      : _currentVolume < 0.5
                          ? Icons.volume_down
                          : Icons.volume_up,
                  text: '${(_currentVolume * 100).round()}%',
                ),
              ),
            if (_showBrightnessIndicator)
              Positioned(
                left: MediaQuery.of(context).size.width / 4,
                top: MediaQuery.of(context).size.height / _indicatorTopPosition,
                child: _buildIndicator(
                  icon: _brightness < 0.3
                      ? Icons.brightness_low
                      : _brightness < 0.7
                          ? Icons.brightness_medium
                          : Icons.brightness_high,
                  text: '${(_brightness * 100).round()}%',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(
          gradient: _topBarGradient,
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
            color: Colors.black.withAlpha(102),
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
                    data: _sliderThemeData,
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
      top: MediaQuery.of(context).size.height / 2 - _seekButtonSize / 2,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.replay_10, color: Colors.white, size: _seekButtonSize),
            onPressed: () {
              _seekRelative(const Duration(seconds: -10));
              _showSeekAnimation(-10);
            },
          ),
          IconButton(
            icon: const Icon(Icons.forward_10, color: Colors.white, size: _seekButtonSize),
            onPressed: () {
              _seekRelative(const Duration(seconds: 10));
              _showSeekAnimation(10);
            },
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
        decoration: const BoxDecoration(
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
              data: _sliderThemeData,
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
                  (MediaQuery.of(context).size.width - 32) - 30,
                bottom: 25,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(77),
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
            // 左侧时间显示
            Container(
              padding: _buttonPadding,
              decoration: _buttonDecoration,
              child: Text(
                '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                style: _timeTextStyle,
              ),
            ),
            // 右侧控件组
            Row(
              children: [
                // 音频轨道按钮
                if (_audioStreams != null && _audioStreams!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: _buttonPadding,
                    decoration: _buttonDecoration,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      icon: const Icon(
                        Icons.audiotrack,
                        color: Colors.white,
                        size: 16,
                      ),
                      onPressed: _showAudioStreamDialog,
                    ),
                  ),
                // 字幕按钮
                if (_subtitleStreams != null && _subtitleStreams!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: _buttonPadding,
                    decoration: _buttonDecoration,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      icon: const Icon(
                        Icons.subtitles,
                        color: Colors.white,
                        size: 16,
                      ),
                      onPressed: _showSubtitleStreamDialog,
                    ),
                  ),
                // 播放速度按钮
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: _buttonPadding,
                  decoration: _buttonDecoration,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    onPressed: _showPlaybackSpeedDialog,
                    icon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.speed,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_playbackSpeed}x',
                          style: _timeTextStyle,
                        ),
                      ],
                    ),
                  ),
                ),
                // 全屏按钮
                Container(
                  padding: _buttonPadding,
                  decoration: _buttonDecoration,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    icon: Icon(
                      _isFullScreen ? Icons.fit_screen : Icons.fullscreen,
                      color: Colors.white,
                      size: 16,
                    ),
                    onPressed: _toggleFullScreen,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }


  // ignore: unused_element
  Widget _buildFullScreenButton() {
    return GestureDetector(
      onTap: _toggleFullScreen,
      child: Container(
        padding: _buttonPadding,
        decoration: _buttonDecoration,
        child: Icon(
          _isFullScreen ? Icons.fit_screen : Icons.fullscreen,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.of(context).size.height / 2 - _seekButtonSize / 2,
      child: GestureDetector(
        onTap: _togglePlayPause,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(77),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withAlpha(128),
                width: 2,
              ),
            ),
            child: Icon(
              _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: _seekButtonSize,
            ),
          ),
        ),
      ),
    );
  }

  void _togglePlayPause() {
    Logger.d("切换播放/暂停状态", _tag);
    if (_controller == null) {
      Logger.w("播放器控制器未初始化", _tag);
      return;
    }
    
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _updateProgress(isPaused: true);
      Logger.i("视频已暂停", _tag);
    } else {
      _controller!.play();
      _startProgressTimer();
      Logger.i("视频开始播放", _tag);
    }
    
    setState(() {});
  }

  void _showPlaybackSpeedDialog() {
    Logger.d("显示播放速度选择对话框", _tag);
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
                    Logger.d("设置播放速度: ${speed}x", _tag);
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
                          ? Colors.red.withAlpha(77)
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

  // 辅助方法
  Widget _buildIndicator({
    required IconData icon,
    required String text,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      padding: padding ?? _indicatorPadding,
      decoration: _indicatorDecoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 4),
          Text(text, style: _indicatorTextStyle),
        ],
      ),
    );
  }

  void _updateDraggingState(bool isDragging) {
    Logger.v("更新拖动状态: ${isDragging ? '开始拖动' : '结束拖动'}", _tag);
    setState(() {
      _showControls = true;
      _isDragging = isDragging;
      if (!isDragging) {
        _startHideControlsTimer();
      }
    });
  }

  void onHorizontalDragStart(DragStartDetails details) {
    Logger.d("开始水平拖动", _tag);
    if (_controller?.value.isInitialized != true) {
      Logger.w("播放器未初始化，忽略拖动操作", _tag);
      return;
    }
    _dragStartX = details.globalPosition.dx;
    _dragStartProgress = _controller!.value.position.inMilliseconds.toDouble();
    _previewPosition = _controller!.value.position;
    _updateDraggingState(true);
    _hideControlsTimer?.cancel();
    Logger.d("初始拖动位置: $_dragStartX, 当前进度: ${_formatDuration(_previewPosition)}", _tag);
  }

  void onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || _dragStartX == null || _dragStartProgress == null) {
      Logger.v("拖动状态无效，忽略更新", _tag);
      return;
    }
    
    final width = MediaQuery.of(context).size.width;
    final dx = details.globalPosition.dx - _dragStartX!;
    final percentage = dx / width;
    
    final duration = _controller!.value.duration;
    final newPosition = _dragStartProgress! + (duration.inMilliseconds * percentage);
    
    setState(() {
      _previewPosition = Duration(milliseconds: newPosition.toInt().clamp(0, duration.inMilliseconds));
      _showControls = true;
    });
    Logger.v("拖动更新 - 偏移: $dx, 百分比: ${(percentage * 100).toStringAsFixed(1)}%, 新位置: ${_formatDuration(_previewPosition)}", _tag);
  }

  void onHorizontalDragEnd(DragEndDetails details) {
    Logger.d("结束水平拖动", _tag);
    if (_isDragging) {
      Logger.d("跳转到新位置: ${_formatDuration(_previewPosition)}", _tag);
      _controller?.seekTo(_previewPosition);
      _updateDraggingState(false);
      _dragStartX = null;
      _dragStartProgress = null;
    }
  }

  void _showAudioStreamDialog() {
    Logger.d("显示音频流选择对话框", _tag);
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
                  '选择音频',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              for (var stream in _audioStreams!)
                InkWell(
                  onTap: () async {
                    Navigator.pop(context);
                    await _switchAudioStream(stream['Index']);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      color: _currentAudioStreamIndex == stream['Index']
                          ? Colors.red.withAlpha(77)
                          : Colors.transparent,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.audiotrack,
                          color: _currentAudioStreamIndex == stream['Index']
                              ? Colors.red
                              : Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${stream['Language'] ?? '未知'} '
                          '(${stream['Codec']?.toString().toUpperCase() ?? '未知'})',
                          style: TextStyle(
                            color: _currentAudioStreamIndex == stream['Index']
                                ? Colors.red
                                : Colors.white,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSubtitleStreamDialog() {
    Logger.d("显示字幕流选择对话框", _tag);
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
                  '选择字幕',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              InkWell(
                onTap: () async {
                  Navigator.pop(context);
                  await _switchSubtitleStream(null);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 24,
                  ),
                  decoration: BoxDecoration(
                    color: _currentSubtitleStreamIndex == null
                        ? Colors.red.withAlpha(77)
                        : Colors.transparent,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.subtitles_off,
                        color: _currentSubtitleStreamIndex == null
                            ? Colors.red
                            : Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '关闭字幕',
                        style: TextStyle(
                          color: _currentSubtitleStreamIndex == null
                              ? Colors.red
                              : Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (var stream in _subtitleStreams!)
                InkWell(
                  onTap: () async {
                    Navigator.pop(context);
                    await _switchSubtitleStream(stream['Index']);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      color: _currentSubtitleStreamIndex == stream['Index']
                          ? Colors.red.withAlpha(77)
                          : Colors.transparent,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.subtitles,
                          color: _currentSubtitleStreamIndex == stream['Index']
                              ? Colors.red
                              : Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${stream['Language'] ?? '未知'} '
                          '(${stream['Codec']?.toString().toUpperCase() ?? '未知'})',
                          style: TextStyle(
                            color: _currentSubtitleStreamIndex == stream['Index']
                                ? Colors.red
                                : Colors.white,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _switchAudioStream(int index) async {
    Logger.i("切换音频流: $index", _tag);
    try {
      // 保存当前播放位置
      final position = _controller!.value.position;
      
      // 获取新的播放URL
      final url = await widget.embyApi.getPlaybackUrl(
        widget.itemId,
        mediaSourceIndex: widget.mediaSourceIndex,
        audioStreamIndex: index,
        subtitleStreamIndex: _currentSubtitleStreamIndex,
      );

      // 创建新的控制器
      final newController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      // 初始化新控制器
      await newController.initialize();
      
      // 设置播放位置和状态
      await newController.seekTo(position);
      if (_controller!.value.isPlaying) {
        await newController.play();
      }
      
      // 更新状态
      setState(() {
        _controller?.dispose();
        _controller = newController;
        _currentAudioStreamIndex = index;
      });
      
      // 添加监听器
      _controller?.addListener(_onPlayerStateChanged);
      
      Logger.i("音频流切换成功", _tag);
    } catch (e) {
      Logger.e("切换音频流失败", _tag, e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换音频失败: $e')),
      );
    }
  }

  Future<void> _switchSubtitleStream(int? index) async {
    Logger.i("切换字幕流: $index", _tag);
    try {
      // 保存当前播放位置
      final position = _controller!.value.position;
      
      // 获取新的播放URL
      final url = await widget.embyApi.getPlaybackUrl(
        widget.itemId,
        mediaSourceIndex: widget.mediaSourceIndex,
        audioStreamIndex: _currentAudioStreamIndex,
        subtitleStreamIndex: index,
      );

      // 创建新的控制器
      final newController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      // 初始化新控制器
      await newController.initialize();
      
      // 设置播放位置和状态
      await newController.seekTo(position);
      if (_controller!.value.isPlaying) {
        await newController.play();
      }
      
      // 更新状态
      setState(() {
        _controller?.dispose();
        _controller = newController;
        _currentSubtitleStreamIndex = index;
      });
      
      // 添加监听器
      _controller?.addListener(_onPlayerStateChanged);
      
      Logger.i("字幕流切换成功", _tag);
    } catch (e) {
      Logger.e("切换字幕流失败", _tag, e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换字幕失败: $e')),
      );
    }
  }

  Future<void> _playNextEpisode() async {
    if (_nextEpisode == null) {
      Logger.i("没有下一集，返回上一页", _tag);
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    Logger.i("开始播放下一集: ${_nextEpisode!['Name']}", _tag);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerPage(
            itemId: _nextEpisode!['Id'],
            title: _nextEpisode!['Name'],
            embyApi: widget.embyApi,
            fromStart: true,
            seriesId: widget.seriesId,
            seasonNumber: widget.seasonNumber,
            episodeNumber: (_nextEpisode!['IndexNumber'] as num).toInt(),
          ),
        ),
      );
    }
  }
} 