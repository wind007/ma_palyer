// ignore_for_file: unused_field

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import '../services/emby_api.dart';
import '../utils/logger.dart';
import '../widgets/video_progress_slider.dart';

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
  final Map<String, dynamic>? playbackInfo;

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
    this.playbackInfo,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  static const String _tag = "VideoPlayer";
  
  // 常量定义
  static const _maxRetries = 3;         // 最大重试次数
  static const _volumeStep = 0.05;      // 音量调节步长
  static const _progressInterval = 60;   // 进度更新间隔（秒）
  static const _minProgressReportDeltaSeconds = 10; // 最小上报位移阈值
  static const _ticksPerSecond = Duration.microsecondsPerSecond * 10;
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
  Timer? _networkStatsTimer;  // 网速估算定时器
  
  // 状态标记
  bool _isInitializing = true;  // 初始化状态
  bool _isDragging = false;     // 是否正在拖动
  String? _error;               // 错误信息
  bool _showControls = false;   // 是否显示控制栏
  int _retryCount = 0;          // 重试次数
  Duration _buffered = Duration.zero; // 缓冲进度
    
  // 播放控制
  double _currentVolume = 1.0;   // 当前音量
  double _lastVolume = 1.0;      // 静音前的音量
  bool _isFullScreen = false;    // 全屏状态
  double _playbackSpeed = 1.0;   // 播放速度
  double _brightness = 0.0;      // 当前亮度
  final ScreenBrightness _screenBrightness = ScreenBrightness.instance;
  bool _canControlBrightness = true;

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
  bool _isControllerSwitching = false;
  int _switchSession = 0;
  late final String _playSessionId;
  bool _isSessionFinalized = false;
  bool _isFinalizingSession = false;
  bool _isNavigatingToEpisode = false;
  bool _isReportingProgress = false;
  int? _lastReportedPositionTicks;
  double _estimatedNetworkSpeedBps = 0;
  Duration? _lastBufferedForSpeed;
  Duration? _lastPositionForSpeed;

  // 添加新的状态变量
  Map<String, dynamic>? _playbackInfo;
  int _currentMediaSourceIndex = 0;
  int? _currentAudioStreamIndex;
  int? _currentSubtitleStreamIndex;
  String _currentVersionLabel = '';
  List<dynamic>? _audioStreams;
  List<dynamic>? _subtitleStreams;
  Map<String, dynamic>? _nextEpisode;

  // 播放列表相关状态
  List<dynamic>? _episodeList;
  bool _showPlaylist = false;
  ScrollController _playlistScrollController = ScrollController();
  bool _isMobile = false;
  bool _isTV = false;
  
  // TV 端焦点相关
  final FocusNode _playlistFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  int? _focusedEpisodeIndex;
  bool _isPlaylistFocused = false;

  @override
  void initState() {
    super.initState();
    _playSessionId = 'flutter-app-${DateTime.now().millisecondsSinceEpoch}';
    Logger.i("初始化视频播放页面 - 视频ID: ${widget.itemId}, 标题: ${widget.title}", _tag);
    
    // 强制横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]).then((_) {
      // 设置全屏
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      Logger.d("设置横屏和全屏模式", _tag);
    });
    
    _initializePlayer();
    _initializeBrightness();
    
    // 加载剧集列表
    if (widget.seriesId != null) {
      _loadEpisodeList();
    }
    
    // TV 端焦点监听
    _playlistFocusNode.addListener(_onPlaylistFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在这里初始化平台相关变量
    final width = MediaQuery.of(context).size.width;
    _isMobile = width < 600;
    _isTV = Theme.of(context).platform == TargetPlatform.android && width > 960;
    
    // 确保横屏
    _setLandscape();
  }

  Future<void> _initializeBrightness() async {
    Logger.d("初始化屏幕亮度", _tag);
    try {
      _brightness = await _screenBrightness.application;
      Logger.d("读取系统亮度成功: $_brightness", _tag);
    } catch (e, stackTrace) {
      _canControlBrightness = false;
      // 插件在不支持的平台会抛异常，这里降级为仅显示UI提示而不实际调亮度。
      Logger.w("当前平台不支持亮度控制，降级为UI模拟", _tag);
      Logger.e("获取系统亮度失败", _tag, e, stackTrace);
      // ignore: deprecated_member_use
      final window = WidgetsBinding.instance.window;
      _brightness = window.platformBrightness == Brightness.dark ? 0.3 : 0.7;
    }
  }

  void _applyBrightness(double value) {
    final newBrightness = value.clamp(0.0, 1.0);
    _brightness = newBrightness;
    if (!_canControlBrightness) return;
    _screenBrightness.setApplicationScreenBrightness(newBrightness).catchError((e, stackTrace) {
      _canControlBrightness = false;
      Logger.w("亮度设置失败，后续关闭实际亮度控制", _tag);
      Logger.e("设置屏幕亮度失败", _tag, e, stackTrace);
    });
  }

  Future<void> _initializePlayer() async {
    Logger.i("开始初始化播放器", _tag);
    try {
      // 获取视频播放URL和信息
      Logger.d("获取播放地址", _tag);
      
      // 获取媒体信息
      Logger.d("获取媒体信息", _tag);
      if (widget.playbackInfo != null) {
        _playbackInfo = widget.playbackInfo;
        Logger.d("使用传入的媒体信息", _tag);
      } else {
        _playbackInfo = await widget.embyApi.getPlaybackInfo(widget.itemId);
        Logger.d("从服务器获取媒体信息", _tag);
      }
      
      if (_playbackInfo == null || _playbackInfo!['MediaSources'] == null || _playbackInfo!['MediaSources'].isEmpty) {
        Logger.e("获取媒体信息失败：MediaSources为空", _tag);
        throw Exception('无法获取媒体信息');
      }
      
      // 获取音频和字幕流
      final mediaSources = _playbackInfo!['MediaSources'] as List;
      _currentMediaSourceIndex = (widget.mediaSourceIndex ?? 0).clamp(0, mediaSources.length - 1);
      final mediaSource = mediaSources[_currentMediaSourceIndex] as Map<String, dynamic>;
      _audioStreams = mediaSource['MediaStreams']?.where((s) => s['Type'] == 'Audio')?.toList();
      _subtitleStreams = mediaSource['MediaStreams']?.where((s) => s['Type'] == 'Subtitle')?.toList();
      _currentVersionLabel = _buildVersionLabel(mediaSource);
      
      _currentAudioStreamIndex = widget.initialAudioStreamIndex ?? mediaSource['DefaultAudioStreamIndex'];
      _currentSubtitleStreamIndex = _resolveInitialSubtitleIndex(
        preferredIndex: widget.initialSubtitleStreamIndex,
        mediaSource: mediaSource,
      );
      
      Logger.d("音频流数量: ${_audioStreams?.length}, 字幕流数量: ${_subtitleStreams?.length}", _tag);
      Logger.d("当前音频流: $_currentAudioStreamIndex, 当前字幕流: $_currentSubtitleStreamIndex", _tag);

      final url = await widget.embyApi.getPlaybackUrl(
        widget.itemId,
        mediaSourceIndex: _currentMediaSourceIndex,
        audioStreamIndex: _currentAudioStreamIndex,
        subtitleStreamIndex:
            (_currentSubtitleStreamIndex != null && _currentSubtitleStreamIndex! >= 0)
                ? _currentSubtitleStreamIndex
                : null,
        subtitleMethod: _resolveInitialSubtitleMethod(),
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
        await _disposeCurrentController();
        return;
      }

      // 设置初始位置和开始播放
      if (_currentSubtitleStreamIndex != null && _currentSubtitleStreamIndex! >= 0) {
        await _applySubtitleSelection(_currentSubtitleStreamIndex!);
      }
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
      _startNetworkStatsTimer();

      // 在初始化播放器后添加缓冲进度监听
      _addVideoListeners();

    } catch (e, stackTrace) {
      Logger.e("初始化播放器失败", _tag, e, stackTrace);
      if (!mounted) {
        await _disposeCurrentController();
        return;
      }
      if (_retryCount < _maxRetries) {
        await _disposeCurrentController();
        _retryCount++;
        Logger.w("准备第$_retryCount次重试", _tag);
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
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
    //     if (_controller!.value.isInitialized) {
    //   // 获取媒体信息，检查字幕轨道
    //   _controller!.getMediaInfo();
    //   if (_subtitleStreams != null && _subtitleStreams!.isNotEmpty) {
    //     // 有字幕轨道可用
        
    //     Logger.d('可用字幕轨道数: $_subtitleStreams', _tag); 
    //     _controller?.setAudioTracks([0]);
    //   }
    // }
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
    _networkStatsTimer?.cancel();
  }

  void _fireAndForgetCleanup(Future<void> task, String action) {
    task.catchError((error, stackTrace) {
      Logger.e('清理任务失败: $action', _tag, error, stackTrace);
    });
  }

  Future<void> _finalizePlaybackSession() async {
    if (_isSessionFinalized || _isFinalizingSession) {
      return;
    }
    _isFinalizingSession = true;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      await _disposeCurrentController();
      _isSessionFinalized = true;
      _isFinalizingSession = false;
      return;
    }

    final mediaSourceId = _currentMediaSourceId;
    final positionTicks = controller.value.position.inMicroseconds * 10;
    final isMuted = _currentVolume <= 0;
    final volumeLevel = (_currentVolume * 100).round().clamp(0, 100);

    try {
      if (mediaSourceId.isNotEmpty) {
        Logger.d("退出前顺序上报最终进度", _tag);
        await widget.embyApi.updatePlaybackProgress(
          itemId: widget.itemId,
          mediaSourceId: mediaSourceId,
          playSessionId: _playSessionId,
          positionTicks: positionTicks,
          isPaused: true,
          audioStreamIndex: _currentAudioStreamIndex,
          subtitleStreamIndex: _currentSubtitleStreamIndex,
          volumeLevel: volumeLevel,
          isMuted: isMuted,
        );
      } else {
        Logger.w("退出收尾缺少 MediaSourceId，跳过最终进度上报", _tag);
      }
    } catch (e, stackTrace) {
      Logger.e("退出前最终进度上报失败", _tag, e, stackTrace);
    }

    try {
      Logger.d("退出前顺序上报停止播放", _tag);
      await widget.embyApi.stopPlayback(
        widget.itemId,
        mediaSourceId: mediaSourceId,
        playSessionId: _playSessionId,
        positionTicks: positionTicks,
        audioStreamIndex: _currentAudioStreamIndex,
        subtitleStreamIndex: _currentSubtitleStreamIndex,
      );
    } catch (e, stackTrace) {
      Logger.e("退出前停止播放上报失败", _tag, e, stackTrace);
    } finally {
      await _disposeCurrentController();
      _isSessionFinalized = true;
      _isFinalizingSession = false;
    }
  }

  Future<void> _switchToEpisodeWithFinalize(
    String itemId,
    String title, {
    bool fromStart = false,
    int? episodeNumber,
  }) async {
    if (_isNavigatingToEpisode) {
      Logger.w("正在切换剧集，忽略重复导航请求", _tag);
      return;
    }
    if (mounted) {
      setState(() {
        _isNavigatingToEpisode = true;
      });
    } else {
      _isNavigatingToEpisode = true;
    }
    if (!mounted) return;
    try {
      await _finalizePlaybackSession();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerPage(
            itemId: itemId,
            title: title,
            embyApi: widget.embyApi,
            fromStart: fromStart,
            seriesId: widget.seriesId,
            seasonNumber: widget.seasonNumber,
            episodeNumber: episodeNumber,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isNavigatingToEpisode = false;
        });
      } else {
        _isNavigatingToEpisode = false;
      }
    }
  }

  Future<void> _disposeCurrentController() async {
    final controller = _controller;
    if (controller == null) return;

    controller.removeListener(_onPlayerStateChanged);
    controller.removeListener(_onVideoControllerValueChanged);
    await controller.dispose();
    _controller = null;
  }

  void _onVideoControllerValueChanged() {
    if (_controller == null || !mounted) return;

    // 更新缓冲进度
    _updateBufferedPosition();

    // 检查播放状态变化
    if (_controller!.value.isBuffering) {
      Logger.d("视频正在缓冲", _tag);
    }

    // 检查错误状态
    if (_controller!.value.hasError) {
      Logger.e("播放器错误: ${_controller!.value.errorDescription}", _tag);
    }
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

  void _startNetworkStatsTimer() {
    _networkStatsTimer?.cancel();
    _lastBufferedForSpeed = null;
    _lastPositionForSpeed = null;
    _networkStatsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateEstimatedNetworkSpeed();
    });
  }

  void _updateEstimatedNetworkSpeed() {
    if (!mounted || _controller == null) return;
    final bitrate = _currentVideoBitrate;
    if (bitrate <= 0) return;

    final currentBuffered = _buffered;
    final currentPosition = _controller!.value.position;
    final previousBuffered = _lastBufferedForSpeed;
    final previousPosition = _lastPositionForSpeed;
    _lastBufferedForSpeed = currentBuffered;
    _lastPositionForSpeed = currentPosition;
    if (previousBuffered == null || previousPosition == null) return;

    final deltaBufferedMs = (currentBuffered - previousBuffered).inMilliseconds.toDouble();
    final deltaPositionMs = (currentPosition - previousPosition).inMilliseconds.toDouble();
    final effectiveDeltaMs = deltaBufferedMs + deltaPositionMs;
    if (effectiveDeltaMs <= 0) {
      if (_estimatedNetworkSpeedBps != 0) {
        setState(() => _estimatedNetworkSpeedBps = 0);
      }
      return;
    }

    // 估算：每秒新增可用媒体时长 * 当前媒体码率
    final estimatedBps = bitrate * (effectiveDeltaMs / 1000.0);
    final stableBps = estimatedBps.clamp(0, bitrate * 8.0).toDouble();
    if ((_estimatedNetworkSpeedBps - stableBps).abs() > 1024) {
      setState(() => _estimatedNetworkSpeedBps = stableBps);
    }
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
      if (_isReportingProgress && !isPaused) {
        return;
      }
      final position = _controller!.value.position;
      final duration = _controller!.value.duration;
      final mediaSourceId = _currentMediaSourceId;
      if (mediaSourceId.isEmpty) {
        Logger.w("更新播放进度失败：缺少有效 MediaSourceId", _tag);
        return;
      }
      final positionTicks = position.inMicroseconds * 10;
      final deltaTicks = _lastReportedPositionTicks == null
          ? null
          : (positionTicks - _lastReportedPositionTicks!).abs();
      final minDeltaTicks = _minProgressReportDeltaSeconds * _ticksPerSecond;
      if (!isPaused && deltaTicks != null && deltaTicks < minDeltaTicks) {
        return;
      }

      _isReportingProgress = true;
      await widget.embyApi.updatePlaybackProgress(
        itemId: widget.itemId,
        mediaSourceId: mediaSourceId,
        playSessionId: _playSessionId,
        positionTicks: positionTicks,
        isPaused: isPaused,
        audioStreamIndex: _currentAudioStreamIndex,
        subtitleStreamIndex: _currentSubtitleStreamIndex,
        volumeLevel: (_currentVolume * 100).round().clamp(0, 100),
        isMuted: _currentVolume <= 0,
      );
      _lastReportedPositionTicks = positionTicks;
      _syncCurrentEpisodeProgress(position, duration);
      Logger.v("播放进度更新成功 - 位置: ${position.inSeconds}秒", _tag);
    } catch (e, stackTrace) {
      Logger.e("更新播放进度失败", _tag, e, stackTrace);
    } finally {
      _isReportingProgress = false;
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
    _switchSession++;
    _clearTimers();
    _controller?.removeListener(_onPlayerStateChanged);
    _controller?.removeListener(_onVideoControllerValueChanged);
    if (!_isSessionFinalized && !_isFinalizingSession) {
      _fireAndForgetCleanup(_finalizePlaybackSession(), '播放会话顺序收尾');
    } else {
      _fireAndForgetCleanup(_disposeCurrentController(), '播放会话已收尾，仅释放控制器');
    }
    
    // 恢复所有方向
    Logger.d("恢复所有屏幕方向", _tag);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    Logger.d("恢复系统UI显示模式", _tag);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _playlistFocusNode.removeListener(_onPlaylistFocusChange);
    _playlistScrollController.dispose();
    _keyboardFocusNode.dispose();
    _playlistFocusNode.dispose();
    super.dispose();
    Logger.i("视频播放页面销毁完成", _tag);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 如果播放器正在播放，显示确认对话框
        if (_controller?.value.isPlaying == true) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.black87,
              title: const Text(
                '确认退出',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                '是否要退出播放？',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    '取消',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    '退出',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          );
          return shouldPop ?? false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 主视频播放区域
            Positioned.fill(
              child: _buildMainPlayer(),
            ),
            
            // 播放列表按钮 - 仅移动端显示在右侧（桌面端使用顶部控制栏入口）
            if (_shouldShowPlaylist && !_isTV && _isMobile)
              _buildMobilePlaylistButton(),

            // 播放列表面板 - 覆盖在视频上方
            if (_showPlaylist)
              _buildPlaylistPanel(),
            if (_isNavigatingToEpisode)
              Positioned.fill(
                child: AbsorbPointer(
                  child: Container(
                    color: Colors.black.withAlpha(90),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(170),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            '正在切换内容...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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

  Widget _buildMobilePlaylistButton() {
    return Positioned(
      right: 0,
      top: MediaQuery.of(context).size.height / 2 - 25,
      child: GestureDetector(
        onTap: _togglePlaylist,
        child: Container(
          width: 25,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(100),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              bottomLeft: Radius.circular(4),
            ),
          ),
          child: Icon(
            _showPlaylist ? Icons.chevron_right : Icons.chevron_left,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistPanel() {
    final size = MediaQuery.of(context).size;
    final isMobile = _isMobile;
    final isTV = _isTV;
    final isSeries = widget.seriesId != null;
    
    return Stack(
      children: [
        // 添加一个全屏的透明层用于捕获外部点击
        Positioned.fill(
          child: GestureDetector(
            onTap: _togglePlaylist,
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),
        // 合集列表面板
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: isTV ? size.width * 0.3 : (isMobile ? size.width * 0.8 : 300),
          child: Focus(
            focusNode: _playlistFocusNode,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(isTV && _isPlaylistFocused ? 0.95 : 0.9),
                border: Border(
                  left: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  // 播放列表标题栏
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isSeries ? '剧集列表' : '合集列表',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isTV ? 20 : 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!isTV)
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: _togglePlaylist,
                          ),
                      ],
                    ),
                  ),
                  // 剧集列表
                  Expanded(
                    child: _episodeList == null
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            controller: _playlistScrollController,
                            itemExtent: _playlistItemExtent,
                            itemCount: _episodeList!.length,
                            itemBuilder: (context, index) {
                              final episode = _episodeList![index];
                              final isPlaying = episode['Id'] == widget.itemId;
                              final isFocused = isTV && index == _focusedEpisodeIndex;
                              final userData = episode['UserData'] as Map<String, dynamic>?;
                              final played = userData?['Played'] == true;
                              final playedPctRaw = userData?['PlayedPercentage'];
                              final playedPct = playedPctRaw is num ? playedPctRaw.toDouble() : 0.0;
                              final progressValue = (playedPct / 100).clamp(0.0, 1.0);
                              
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: (isTV || _isNavigatingToEpisode)
                                      ? null
                                      : () => _onEpisodeSelected(episode),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isFocused
                                          ? Colors.red.withOpacity(0.3)
                                          : (isPlaying ? Colors.red.withOpacity(0.2) : null),
                                    ),
                                    child: ListTile(
                                      title: Text(
                                        episode['Name'] ?? '未知',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isTV ? 18 : 14,
                                          fontWeight: (isPlaying || isFocused) 
                                              ? FontWeight.bold 
                                              : FontWeight.normal,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: isSeries ? Text(
                                        '第${episode['IndexNumber'] ?? '?'}集',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: isTV ? 16 : 12,
                                        ),
                                      ) : null,
                                      leading: isPlaying
                                          ? Icon(
                                              Icons.play_arrow,
                                              color: Colors.red,
                                              size: isTV ? 32 : 24,
                                            )
                                          : Text(
                                              '${index + 1}',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: isTV ? 18 : 14,
                                              ),
                                            ),
                                      trailing: played
                                          ? Icon(
                                              Icons.check_circle,
                                              color: Colors.greenAccent.shade200,
                                              size: isTV ? 24 : 20,
                                            )
                                          : progressValue > 0.01
                                              ? SizedBox(
                                                  width: isTV ? 56 : 44,
                                                  child: LinearProgressIndicator(
                                                    value: progressValue,
                                                    minHeight: isTV ? 6 : 4,
                                                    backgroundColor: Colors.white24,
                                                    valueColor: AlwaysStoppedAnimation<Color>(
                                                      Colors.greenAccent.shade200,
                                                    ),
                                                  ),
                                                )
                                              : null,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: isTV ? 24 : 16,
                                        vertical: isTV ? 16 : 8,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  if (isTV)
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: const Text(
                        '使用上下键选择，确定键播放',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _togglePlaylist() {
    if (_isNavigatingToEpisode) {
      Logger.v("切换剧集中，忽略播放列表开关操作", _tag);
      return;
    }
    setState(() {
      _showPlaylist = !_showPlaylist;
      if (_showPlaylist) {
        _focusedEpisodeIndex = _currentEpisodeIndex;
        _scrollToCurrentEpisode();
      }
    });
  }

  Future<void> _onEpisodeSelected(Map<String, dynamic> episode) async {
    if (episode['Id'] != widget.itemId) {
      await _switchToEpisodeWithFinalize(
        episode['Id'],
        episode['Name'],
        episodeNumber: episode['IndexNumber'],
      );
    }
  }

  Widget _buildMainPlayer() {
    if (_error != null) {
      return _buildErrorView();
    }

    if (_isInitializing || _controller == null) {
      return _buildLoadingView();
    }

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (_isTV) {
          _handleTVRemoteKey(event);
        } else {
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
              _applyBrightness(_brightness + percentage);
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
            if (_showControls) ...[
              _buildTopBar(),
              _buildVolumeControl(),
              _buildSeekButtons(),
              _buildBottomBar(),
              _buildPlayPauseButton(),
            ],
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_currentVersionLabel.isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: _isMobile ? 140 : 220,
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(120),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _currentVersionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(120),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      '网速 $_estimatedNetworkSpeedText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_shouldShowPlaylist)
                    IconButton(
                      icon: Icon(
                        _showPlaylist ? Icons.playlist_remove : Icons.playlist_play,
                        color: Colors.white,
                      ),
                      tooltip: _showPlaylist ? '关闭可切换内容' : '切换剧集/系列内容',
                      onPressed: _togglePlaylist,
                    ),
                ],
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
    return VideoProgressSlider(
      position: _controller?.value.position ?? Duration.zero,
      duration: _controller?.value.duration ?? Duration.zero,
      buffered: _buffered,
      isDragging: _isDragging,
      onChanged: (value) {
        if (_controller?.value.duration != null) {
          final newPosition = value * _controller!.value.duration.inMilliseconds;
          setState(() {
            _previewPosition = Duration(milliseconds: newPosition.round());
            _isDragging = true;
          });
        }
      },
      onChangeStart: (value) {
        _hideControlsTimer?.cancel();
        setState(() {
          _isDragging = true;
        });
      },
      onChangeEnd: (value) {
        if (_controller?.value.duration != null) {
          final newPosition = value * _controller!.value.duration.inMilliseconds;
          _controller?.seekTo(Duration(milliseconds: newPosition.round()));
        }
        _startHideControlsTimer();
        setState(() {
          _isDragging = false;
        });
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
                if (_availableMediaSources.length > 1)
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
                        Icons.movie_filter,
                        color: Colors.white,
                        size: 16,
                      ),
                      onPressed: _showMediaSourceDialog,
                    ),
                  ),
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
                      icon: Icon(
                        _currentSubtitleStreamIndex == -1 ? Icons.subtitles_off : Icons.subtitles,
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
                          _formatPlaybackSpeed(_playbackSpeed),
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
                    _applyPlaybackSpeed(speed);
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
                      _formatPlaybackSpeed(speed),
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
              const Divider(color: Colors.white24, height: 20),
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _showCustomPlaybackSpeedDialog();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 24,
                  ),
                  child: const Text(
                    '自定义倍速',
                    style: TextStyle(
                      color: Colors.white,
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

  void _showCustomPlaybackSpeedDialog() {
    final textController = TextEditingController(
      text: _playbackSpeed.toStringAsFixed(
        _playbackSpeed.truncateToDouble() == _playbackSpeed ? 0 : 2,
      ),
    );
    const minSpeed = 0.25;
    const maxSpeed = 8.0;
    String? errorText;
    Logger.d("显示自定义倍速输入对话框", _tag);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.black87,
          title: const Text(
            '自定义倍速',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: textController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: '倍速值',
                  hintText: '例如 1.15',
                  helperText: '支持范围 $minSpeed ~ $maxSpeed',
                  errorText: errorText,
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintStyle: const TextStyle(color: Colors.white38),
                  helperStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.redAccent),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final parsed = double.tryParse(textController.text.trim());
                if (parsed == null || parsed < minSpeed || parsed > maxSpeed) {
                  setDialogState(() {
                    errorText = '请输入 $minSpeed ~ $maxSpeed 之间的数字';
                  });
                  return;
                }
                final customSpeed = double.parse(parsed.toStringAsFixed(2));
                _applyPlaybackSpeed(customSpeed);
                Navigator.pop(context);
                _startHideControlsTimer();
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    ).whenComplete(textController.dispose);
  }

  void _applyPlaybackSpeed(double speed) {
    Logger.d("设置播放速度: ${_formatPlaybackSpeed(speed)}", _tag);
    setState(() {
      _playbackSpeed = speed;
    });
    _controller?.setPlaybackSpeed(speed);
  }

  String _formatPlaybackSpeed(double speed) {
    final value = speed.truncateToDouble() == speed
        ? speed.toStringAsFixed(0)
        : speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '${value}x';
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

  int get _currentVideoBitrate {
    final mediaSources = _availableMediaSources;
    if (mediaSources.isEmpty ||
        _currentMediaSourceIndex < 0 ||
        _currentMediaSourceIndex >= mediaSources.length) {
      return 0;
    }
    final source = mediaSources[_currentMediaSourceIndex];
    final raw = source['Bitrate'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  String get _estimatedNetworkSpeedText {
    if (_estimatedNetworkSpeedBps <= 0) return '--';
    final kb = _estimatedNetworkSpeedBps / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB/s';
    return '${(kb / 1024).toStringAsFixed(2)} MB/s';
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
              const Text(
                '选择音频',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (_audioStreams != null)
                ..._audioStreams!.map((stream) {
                  final isSelected = stream['Index'] == _currentAudioStreamIndex;
                  return ListTile(
                    title: Text(
                      stream['DisplayTitle'] ?? '未知音轨',
                      style: TextStyle(
                        color: isSelected ? Colors.red : Colors.white,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _switchAudioStream(stream['Index']);
                    },
                  );
                }).toList(),
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
              const Text(
                '选择字幕',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (_subtitleStreams != null && _subtitleStreams!.isNotEmpty)
                ..._subtitleStreams!.map((stream) {
                  final isSelected = stream['Index'] == _currentSubtitleStreamIndex;
                  return ListTile(
                    title: Text(
                      stream['DisplayTitle'] ?? '未知字幕',
                      style: TextStyle(
                        color: isSelected ? Colors.red : Colors.white,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _switchSubtitleStream(stream['Index']);
                    },
                  );
                }).toList(),
              ListTile(
                title: Text(
                  '关闭字幕',
                  style: TextStyle(
                    color: _currentSubtitleStreamIndex == -1 ? Colors.red : Colors.white,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _switchSubtitleStream(-1);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMediaSourceDialog() {
    final mediaSources = _availableMediaSources;
    if (mediaSources.length <= 1) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black87,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '选择版本',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...List.generate(mediaSources.length, (index) {
                final source = mediaSources[index];
                final isSelected = index == _currentMediaSourceIndex;
                final label = _buildVersionLabel(source);
                return ListTile(
                  title: Text(
                    label.isEmpty ? '版本 ${index + 1}' : label,
                    style: TextStyle(
                      color: isSelected ? Colors.red : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.red, size: 18)
                      : null,
                  onTap: () async {
                    Navigator.pop(context);
                    await _switchMediaSource(index);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _availableMediaSources {
    final sources = _playbackInfo?['MediaSources'];
    if (sources is! List) return const [];
    return sources.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> _switchMediaSource(int targetIndex) async {
    if (_isControllerSwitching) {
      Logger.w("正在切换播放源，忽略重复操作", _tag);
      return;
    }
    final mediaSources = _availableMediaSources;
    if (mediaSources.isEmpty) return;
    if (targetIndex < 0 || targetIndex >= mediaSources.length) return;
    if (targetIndex == _currentMediaSourceIndex) return;

    Logger.i("切换媒体版本: $_currentMediaSourceIndex -> $targetIndex", _tag);

    final targetSource = mediaSources[targetIndex];
    final audioStreams = targetSource['MediaStreams']?.where((s) => s['Type'] == 'Audio')?.toList();
    final subtitleStreams = targetSource['MediaStreams']?.where((s) => s['Type'] == 'Subtitle')?.toList();
    final nextAudioIndex = targetSource['DefaultAudioStreamIndex'];
    int nextSubtitleIndex;
    if (_currentSubtitleStreamIndex != null &&
        _currentSubtitleStreamIndex != -1 &&
        subtitleStreams != null &&
        subtitleStreams.any((s) => s['Index'] == _currentSubtitleStreamIndex)) {
      nextSubtitleIndex = _currentSubtitleStreamIndex!;
    } else {
      nextSubtitleIndex = _resolveInitialSubtitleIndex(
        preferredIndex: null,
        mediaSource: targetSource,
      );
    }

    final currentPosition = _controller?.value.position;
    final wasPlaying = _controller?.value.isPlaying ?? false;

    final session = ++_switchSession;
    _isControllerSwitching = true;
    try {
      final url = await widget.embyApi.getPlaybackUrl(
        widget.itemId,
        mediaSourceIndex: targetIndex,
        audioStreamIndex: nextAudioIndex,
        subtitleStreamIndex: nextSubtitleIndex,
      );
      if (url.isEmpty) {
        Logger.e("切换版本失败：播放地址为空", _tag);
        return;
      }

      final newController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await newController.initialize();
      if (!mounted || session != _switchSession) {
        await newController.dispose();
        return;
      }

      final oldController = _controller;
      setState(() {
        _controller = newController;
        _currentMediaSourceIndex = targetIndex;
        _audioStreams = audioStreams;
        _subtitleStreams = subtitleStreams;
        _currentAudioStreamIndex = nextAudioIndex;
        _currentSubtitleStreamIndex = nextSubtitleIndex;
        _currentVersionLabel = _buildVersionLabel(targetSource);
      });

      await _controller?.setVolume(_currentVolume);
      await _controller?.setPlaybackSpeed(_playbackSpeed);
      if (currentPosition != null) {
        await _controller?.seekTo(currentPosition);
      }
      await _applySubtitleSelection(nextSubtitleIndex);
      if (!mounted || session != _switchSession) return;
      if (wasPlaying) {
        await _controller?.play();
      }

      oldController?.removeListener(_onPlayerStateChanged);
      oldController?.removeListener(_onVideoControllerValueChanged);
      await oldController?.dispose();

      _controller?.addListener(_onPlayerStateChanged);
      _addVideoListeners();
      Logger.i("版本切换完成: $targetIndex", _tag);
    } catch (e, stackTrace) {
      Logger.e("切换版本失败", _tag, e, stackTrace);
    } finally {
      _isControllerSwitching = false;
    }
  }

  Future<void> _switchAudioStream(int index) async {
    if (_isControllerSwitching) {
      Logger.w("正在切换播放源，忽略重复操作", _tag);
      return;
    }
    Logger.i("切换音频流: $index", _tag);
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      Logger.w("播放器未初始化，无法切换音轨", _tag);
      return;
    }

    // 优先使用 fvp 轨道切换，避免重建 controller 带来的中断。
    try {
      setState(() {
        _currentAudioStreamIndex = index;
      });
      controller.setAudioTracks([index]);
      Logger.i("音频切换完成（fvp 轨道切换）", _tag);
    } catch (e, stackTrace) {
      Logger.w("fvp 轨道切换失败，回退到重建 controller 切换音轨", _tag);
      Logger.e("轨道切换异常", _tag, e, stackTrace);
      await _switchAudioStreamByRebuild(index);
    }
  }

  Future<void> _switchAudioStreamByRebuild(int index) async {
    final session = ++_switchSession;
    _isControllerSwitching = true;
    try {
      if (_playbackInfo == null) {
        Logger.e("无法切换音频：播放信息为空", _tag);
        return;
      }

      final currentPosition = _controller?.value.position;
      final url = await widget.embyApi.getPlaybackUrl(
        widget.itemId,
        mediaSourceIndex: _currentMediaSourceIndex,
        audioStreamIndex: index,
        subtitleStreamIndex: _currentSubtitleStreamIndex,
      );

      if (url.isEmpty) {
        Logger.e("获取新播放地址失败", _tag);
        return;
      }

      final newController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await newController.initialize();
      if (!mounted || session != _switchSession) {
        await newController.dispose();
        return;
      }

      final oldController = _controller;
      setState(() {
        _controller = newController;
        _currentAudioStreamIndex = index;
      });

      await _controller?.setVolume(_currentVolume);
      if (currentPosition != null) {
        await _controller?.seekTo(currentPosition);
      }
      if (_currentSubtitleStreamIndex != null) {
        await _applySubtitleSelection(_currentSubtitleStreamIndex!);
      }
      if (!mounted || session != _switchSession) return;
      if (oldController?.value.isPlaying ?? false) {
        await _controller?.play();
      }

      oldController?.removeListener(_onPlayerStateChanged);
      oldController?.removeListener(_onVideoControllerValueChanged);
      await oldController?.dispose();

      _controller?.addListener(_onPlayerStateChanged);
      _addVideoListeners();
      Logger.i("音频切换完成（回退重建 controller）", _tag);
    } catch (e, stackTrace) {
      Logger.e("回退切换音频失败", _tag, e, stackTrace);
    } finally {
      _isControllerSwitching = false;
    }
  }

  Future<void> _disableSubtitleSafely() async {
    if (_controller == null) return;

    _controller?.setSubtitleTracks([]);
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted || _controller == null) return;

    final activeTracks = _controller?.getActiveSubtitleTracks();
    if (activeTracks != null && activeTracks.isNotEmpty) {
      Logger.w('setSubtitleTracks([]) 未清空字幕轨，尝试兼容回退 setVideoTracks([])', _tag);
      _controller?.setVideoTracks([]);
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted || _controller == null) return;
    }

    Logger.d('关闭字幕后 active subtitle tracks: ${_controller?.getActiveSubtitleTracks()}', _tag);
  }

  Future<void> _applySubtitleSelection(int subtitleIndex) async {
    if (!mounted || _controller == null) return;
    if (subtitleIndex == -1) {
      await _disableSubtitleSafely();
      return;
    }

    final subtitleUrl = await widget.embyApi.getSubtitleUrl(
      widget.itemId,
      subtitleIndex,
      mediaSourceIndex: _currentMediaSourceIndex,
    );
    if (subtitleUrl == null || subtitleUrl.isEmpty || !mounted || _controller == null) return;

    _controller?.setExternalSubtitle(subtitleUrl);
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted || _controller == null) return;

    final activeTracks = _controller?.getActiveSubtitleTracks();
    if (activeTracks != null && activeTracks.isNotEmpty) {
      _controller?.setSubtitleTracks([activeTracks.first]);
    }
  }

  Future<void> _switchSubtitleStream(int index) async {
    Logger.i("切换字幕流: $index", _tag);
    if (_isControllerSwitching) {
      Logger.w("正在切换播放源，忽略重复操作", _tag);
      return;
    }
    try {
      if (_playbackInfo == null) {
        Logger.e("无法切换字幕：播放信息为空", _tag);
        return;
      }
      if (index < 0) {
        await _switchSubtitleStreamByRebuild(index);
        return;
      }

      // 先尝试外挂字幕注入，兼容性更好；失败再回退重建流。
      setState(() {
        _currentSubtitleStreamIndex = index;
      });
      await _applySubtitleSelection(index);
      final activeTracks = _controller?.getActiveSubtitleTracks() ?? const [];
      if (activeTracks.isEmpty) {
        Logger.w("外挂字幕未激活，回退重建播放流切换字幕", _tag);
        await _switchSubtitleStreamByRebuild(index);
      } else {
        Logger.i("字幕切换完成（外挂字幕）", _tag);
      }
    } catch (e, stackTrace) {
      Logger.e("切换字幕失败", _tag, e, stackTrace);
    }
  }

  Future<void> _switchSubtitleStreamByRebuild(int index) async {
    final session = ++_switchSession;
    _isControllerSwitching = true;
    try {
      final currentPosition = _controller?.value.position;
      final wasPlaying = _controller?.value.isPlaying ?? false;
      final targetSubtitleIndex = index >= 0 ? index : -1;

      final url = await widget.embyApi.getPlaybackUrl(
        widget.itemId,
        mediaSourceIndex: _currentMediaSourceIndex,
        audioStreamIndex: _currentAudioStreamIndex,
        subtitleStreamIndex: targetSubtitleIndex >= 0 ? targetSubtitleIndex : null,
        subtitleMethod: targetSubtitleIndex >= 0 ? 'Embed' : 'None',
      );
      if (url.isEmpty) {
        Logger.e("切换字幕失败：播放地址为空", _tag);
        return;
      }

      final newController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await newController.initialize();
      if (!mounted || session != _switchSession) {
        await newController.dispose();
        return;
      }

      final oldController = _controller;
      setState(() {
        _controller = newController;
        _currentSubtitleStreamIndex = targetSubtitleIndex;
      });

      await _controller?.setVolume(_currentVolume);
      await _controller?.setPlaybackSpeed(_playbackSpeed);
      if (currentPosition != null) {
        await _controller?.seekTo(currentPosition);
      }
      if (wasPlaying) {
        await _controller?.play();
      }

      oldController?.removeListener(_onPlayerStateChanged);
      oldController?.removeListener(_onVideoControllerValueChanged);
      await oldController?.dispose();

      _controller?.addListener(_onPlayerStateChanged);
      _addVideoListeners();
      Logger.i("字幕切换完成: $targetSubtitleIndex", _tag);
    } finally {
      _isControllerSwitching = false;
    }
  }

  int _resolveInitialSubtitleIndex({
    required int? preferredIndex,
    required Map<String, dynamic> mediaSource,
  }) {
    if (preferredIndex != null) return preferredIndex;

    final defaultIndex = mediaSource['DefaultSubtitleStreamIndex'];
    if (defaultIndex is int) return defaultIndex;

    final subtitleStreams = mediaSource['MediaStreams']
        ?.where((s) => s['Type'] == 'Subtitle')
        ?.toList();
    if (subtitleStreams is List && subtitleStreams.isNotEmpty) {
      final first = subtitleStreams.first;
      if (first is Map<String, dynamic> && first['Index'] is int) {
        return first['Index'] as int;
      }
    }
    return -1;
  }

  String _resolveInitialSubtitleMethod() {
    final subtitleIndex = _currentSubtitleStreamIndex;
    if (subtitleIndex != null && subtitleIndex >= 0) {
      return 'Embed';
    }

    // 只有外部明确传了 -1（用户主动关闭字幕）才强制禁用字幕，
    // 否则交给服务端默认策略，避免部分服务端在初始化时拒绝 None。
    if (widget.initialSubtitleStreamIndex == -1) {
      return 'None';
    }
    return '';
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
    if (_isNavigatingToEpisode) {
      Logger.w("下一集导航已在进行中，忽略重复触发", _tag);
      return;
    }
    if (mounted) {
      await _switchToEpisodeWithFinalize(
        _nextEpisode!['Id'],
        _nextEpisode!['Name'],
        fromStart: true,
        episodeNumber: (_nextEpisode!['IndexNumber'] as num).toInt(),
      );
    }
  }

  // 加载剧集列表
  Future<void> _loadEpisodeList() async {
    Logger.d("开始加载剧集列表", _tag);
    try {
      final response = await widget.embyApi.getEpisodes(
        seriesId: widget.seriesId!,
        userId: widget.embyApi.userId!,
        seasonNumber: widget.seasonNumber,
        fields: 'Path,MediaSources,UserData',
      );

      if (response['Items'] != null) {
        setState(() {
          _episodeList = response['Items'] as List;
        });
        Logger.i("成功加载 ${_episodeList?.length} 集", _tag);
        
        // 滚动到当前播放的剧集
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToCurrentEpisode();
        });
      }
    } catch (e, stackTrace) {
      Logger.e("加载剧集列表失败", _tag, e, stackTrace);
    }
  }

  void _scrollToCurrentEpisode() {
    if (_episodeList == null || !_playlistScrollController.hasClients) return;

    final currentIndex = _currentEpisodeIndex;
    if (currentIndex != -1) {
      final targetOffset = (currentIndex * _playlistItemExtent)
          .clamp(0.0, _playlistScrollController.position.maxScrollExtent);
      _playlistScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
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
    );
  }

  void _handleTVRemoteKey(KeyEvent event) {
    if (!_isTV) return;

    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.select:
          if (_showPlaylist && _focusedEpisodeIndex != null) {
            final episode = _episodeList![_focusedEpisodeIndex!];
            _onEpisodeSelected(episode);
          } else {
            _togglePlayPause();
          }
          break;
        case LogicalKeyboardKey.mediaPlayPause:
          _togglePlayPause();
          break;
        case LogicalKeyboardKey.mediaTrackNext:
          _playNextEpisode();
          break;
        case LogicalKeyboardKey.mediaTrackPrevious:
          // TODO: 实现上一集功能
          break;
        case LogicalKeyboardKey.arrowLeft:
          if (_showPlaylist && _isPlaylistFocused) {
            _togglePlaylist();
          } else {
            _seekRelative(const Duration(seconds: -10));
            _showSeekAnimation(-10);
          }
          break;
        case LogicalKeyboardKey.arrowRight:
          if (!_showPlaylist) {
            _seekRelative(const Duration(seconds: 10));
            _showSeekAnimation(10);
          }
          break;
        case LogicalKeyboardKey.arrowUp:
          if (_showPlaylist && _isPlaylistFocused) {
            setState(() {
              _focusedEpisodeIndex = (_focusedEpisodeIndex ?? 0) - 1;
              if (_focusedEpisodeIndex! < 0) {
                _focusedEpisodeIndex = _episodeList!.length - 1;
              }
            });
            _scrollToFocusedEpisode();
          } else {
            _adjustVolume(_volumeStep);
          }
          break;
        case LogicalKeyboardKey.arrowDown:
          if (_showPlaylist && _isPlaylistFocused) {
            setState(() {
              _focusedEpisodeIndex = (_focusedEpisodeIndex ?? -1) + 1;
              if (_focusedEpisodeIndex! >= _episodeList!.length) {
                _focusedEpisodeIndex = 0;
              }
            });
            _scrollToFocusedEpisode();
          } else {
            _adjustVolume(-_volumeStep);
          }
          break;
        case LogicalKeyboardKey.contextMenu:
          _togglePlaylist();
          break;
        case LogicalKeyboardKey.escape:
        case LogicalKeyboardKey.goBack:
          if (_showPlaylist) {
            _togglePlaylist();
          } else {
            Navigator.of(context).pop();
          }
          break;
      }
    }
  }

  void _scrollToFocusedEpisode() {
    if (_focusedEpisodeIndex == null || !_playlistScrollController.hasClients) return;

    final targetOffset = (_focusedEpisodeIndex! * _playlistItemExtent)
        .clamp(0.0, _playlistScrollController.position.maxScrollExtent);
    _playlistScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  int get _currentEpisodeIndex {
    if (_episodeList == null) return -1;
    return _episodeList!.indexWhere((episode) => episode['Id'] == widget.itemId);
  }

  double get _playlistItemExtent => _isTV ? 88.0 : 72.0;

  void _onPlaylistFocusChange() {
    if (mounted) {
      setState(() {
        _isPlaylistFocused = _playlistFocusNode.hasFocus;
      });
    }
  }

  bool get _shouldShowPlaylist {
    // 如果是电视剧（有 seriesId），显示播放列表
    if (widget.seriesId != null) {
      Logger.d("显示播放列表：这是一个电视剧", _tag);
      return true;
    }
    
    Logger.d("不显示播放列表：这是一个独立的视频", _tag);
    return false;
  }

  String get _currentMediaSourceId {
    final mediaSources = _availableMediaSources;
    if (mediaSources.isEmpty ||
        _currentMediaSourceIndex < 0 ||
        _currentMediaSourceIndex >= mediaSources.length) {
      return '';
    }
    return mediaSources[_currentMediaSourceIndex]['Id']?.toString() ?? '';
  }

  void _syncCurrentEpisodeProgress(Duration position, Duration duration) {
    if (_episodeList == null || _episodeList!.isEmpty) return;
    final idx = _currentEpisodeIndex;
    if (idx < 0 || idx >= _episodeList!.length) return;
    final rawPercent = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds) * 100.0
        : 0.0;
    final playedPercent = rawPercent.clamp(0.0, 100.0);
    final played = playedPercent >= 95.0;

    final episode = _episodeList![idx];
    if (episode is! Map<String, dynamic>) return;
    final userData = (episode['UserData'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final oldPercentRaw = userData['PlayedPercentage'];
    final oldPercent = oldPercentRaw is num ? oldPercentRaw.toDouble() : 0.0;
    final oldPlayed = userData['Played'] == true;

    if ((oldPercent - playedPercent).abs() < 0.5 && oldPlayed == played) {
      return;
    }

    userData['PlayedPercentage'] = playedPercent;
    userData['Played'] = played;
    userData['PlaybackPositionTicks'] = position.inMicroseconds * 10;
    episode['UserData'] = userData;
    if (mounted) setState(() {});
  }

  // 强制横屏方法
  void _setLandscape() {
    final orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.portrait) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      Logger.d("强制切换到横屏模式", _tag);
    }
  }

  // 更新缓冲进度
  void _updateBufferedPosition() {
    if (_controller == null || !mounted) return;

    // 从 FVP 的缓冲事件中获取缓冲进度
    if (_controller!.value.buffered.isNotEmpty) {
      final bufferedRanges = _controller!.value.buffered;
      Duration maxBuffered = Duration.zero;
      
      // 找出最大的缓冲范围
      for (final range in bufferedRanges) {
        if (range.end > maxBuffered) {
          maxBuffered = range.end;
        }
      }

      if (maxBuffered > Duration.zero) {
        setState(() {
          _buffered = maxBuffered;
        });
        Logger.v("缓冲进度更新: ${_formatDuration(_buffered)}", _tag);
      }
    }
  }

  // 添加视频监听器
  void _addVideoListeners() {
    if (_controller == null) return;

    // 防止重复注册监听器
    _controller!.removeListener(_onVideoControllerValueChanged);
    _controller!.addListener(_onVideoControllerValueChanged);

    Logger.d("已添加视频播放器监听器", _tag);
  }

  String _buildVersionLabel(Map<String, dynamic> mediaSource) {
    final mediaStreams = mediaSource['MediaStreams'];
    Map<String, dynamic>? videoStream;
    Map<String, dynamic>? audioStream;
    if (mediaStreams is List) {
      for (final stream in mediaStreams) {
        if (stream is! Map<String, dynamic>) continue;
        if (stream['Type'] == 'Video' && videoStream == null) {
          videoStream = stream;
        } else if (stream['Type'] == 'Audio' && audioStream == null) {
          audioStream = stream;
        }
        if (videoStream != null && audioStream != null) {
          break;
        }
      }
    }

    final parts = <String>[];

    final sourceName = mediaSource['Name']?.toString();
    final sourcePath = mediaSource['Path']?.toString();
    final parsedFromName = _extractResolutionFromText(sourceName) ?? _extractResolutionFromText(sourcePath);
    if (parsedFromName != null) {
      parts.add(parsedFromName);
    } else {
      final sourceHeight = _toInt(mediaSource['Height']);
      final sourceWidth = _toInt(mediaSource['Width']);
      final streamHeight = _toInt(videoStream?['Height']);
      final streamWidth = _toInt(videoStream?['Width']);
      final bestHeight = sourceHeight ?? streamHeight;
      final bestWidth = sourceWidth ?? streamWidth;

      if (bestHeight != null && bestHeight > 0) {
        parts.add('${bestHeight}p');
      } else if (bestWidth != null && bestWidth > 0) {
        if (bestWidth >= 3500) {
          parts.add('4K');
        } else if (bestWidth >= 2500) {
          parts.add('1440p');
        } else if (bestWidth >= 1800) {
          parts.add('1080p');
        } else if (bestWidth >= 1200) {
          parts.add('720p');
        }
      }
    }

    final videoCodec = (videoStream?['Codec'] ?? videoStream?['VideoCodec'])?.toString().trim();
    if (videoCodec != null && videoCodec.isNotEmpty) {
      parts.add(videoCodec.toUpperCase());
    }

    final audioCodec = (audioStream?['Codec'] ?? audioStream?['AudioCodec'])?.toString().trim();
    final channels = _toInt(audioStream?['Channels']);
    final audioPartItems = <String>[];
    if (audioCodec != null && audioCodec.isNotEmpty) {
      audioPartItems.add(audioCodec.toUpperCase());
    }
    if (channels != null && channels > 0) {
      audioPartItems.add(_formatChannelLabel(channels));
    }
    if (audioPartItems.isNotEmpty) {
      parts.add(audioPartItems.join(' '));
    }

    if (parts.isNotEmpty) {
      return parts.join(' · ');
    }

    if (sourceName is String && sourceName.trim().isNotEmpty) {
      return sourceName.trim();
    }
    return '';
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _formatChannelLabel(int channels) {
    if (channels == 8) return '7.1';
    if (channels == 6) return '5.1';
    if (channels == 2) return '2.0';
    if (channels == 1) return '1.0';
    return '$channels ch';
  }

  String? _extractResolutionFromText(String? text) {
    if (text == null || text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower.contains('2160p') || lower.contains('4k') || lower.contains('uhd')) return '4K';
    if (lower.contains('1440p') || lower.contains('2k')) return '1440p';
    if (lower.contains('1080p') || lower.contains('fhd')) return '1080p';
    if (lower.contains('720p') || lower.contains('hd')) return '720p';
    if (lower.contains('480p')) return '480p';
    return null;
  }
}
