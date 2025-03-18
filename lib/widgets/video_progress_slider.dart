import 'package:flutter/material.dart';

class VideoProgressSlider extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool isDragging;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  const VideoProgressSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.isDragging,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final value = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
        
    final bufferedValue = duration.inMilliseconds > 0
        ? buffered.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 2.0,
        activeTrackColor: Colors.red,
        // 已缓冲但未播放的部分显示为灰色
        inactiveTrackColor: Colors.white.withOpacity(0.5),
        // 未缓冲的部分显示为深灰色
        secondaryActiveTrackColor: Colors.white.withOpacity(0.3),
        thumbColor: Colors.red,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 6.0,
        ),
        overlayColor: Colors.red.withOpacity(0.3),
        overlayShape: const RoundSliderOverlayShape(
          overlayRadius: 12.0,
        ),
        // 自定义轨道形状以支持缓冲进度显示
        trackShape: _CustomTrackShape(bufferedValue: bufferedValue),
      ),
      child: Slider(
        value: value.clamp(0.0, 1.0),
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

class _CustomTrackShape extends RoundedRectSliderTrackShape {
  final double bufferedValue;

  const _CustomTrackShape({required this.bufferedValue});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    // 获取轨道的矩形区域
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    // 计算缓冲进度的位置
    final double bufferedX = trackRect.left + trackRect.width * bufferedValue;
    
    // 绘制未缓冲的背景
    final Paint unBufferedPaint = Paint()
      ..color = sliderTheme.secondaryActiveTrackColor ?? Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    context.canvas.drawRect(trackRect, unBufferedPaint);

    // 绘制已缓冲的部分
    if (bufferedValue > 0) {
      final Rect bufferedRect = Rect.fromLTRB(
        trackRect.left,
        trackRect.top,
        bufferedX,
        trackRect.bottom,
      );
      final Paint bufferedPaint = Paint()
        ..color = sliderTheme.inactiveTrackColor ?? Colors.grey
        ..style = PaintingStyle.fill;
      context.canvas.drawRect(bufferedRect, bufferedPaint);
    }

    // 绘制已播放的部分
    if (thumbCenter.dx > trackRect.left) {
      final Rect activeRect = Rect.fromLTRB(
        trackRect.left,
        trackRect.top,
        thumbCenter.dx,
        trackRect.bottom,
      );
      final Paint activePaint = Paint()
        ..color = sliderTheme.activeTrackColor ?? Colors.red
        ..style = PaintingStyle.fill;
      context.canvas.drawRect(activeRect, activePaint);
    }
  }
} 