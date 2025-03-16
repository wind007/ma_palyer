import 'package:flutter/material.dart';
import '../utils/logger.dart';

class EmbyImage extends StatelessWidget {
  static const String _tag = "EmbyImage";

  final String? imageUrl;
  final Map<String, String> headers;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final String? title;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? iconSize;
  final Widget Function(BuildContext, dynamic, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;

  const EmbyImage({
    super.key,
    this.imageUrl,
    required this.headers,
    this.width,
    this.height,
    this.fit,
    this.title,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty || !imageUrl!.startsWith('http')) {
      return _buildPlaceholder(context);
    }

    return Image.network(
      imageUrl!,
      headers: headers,
      width: width,
      height: height,
      fit: fit ?? BoxFit.cover,
      errorBuilder: errorBuilder ?? _defaultErrorBuilder,
      loadingBuilder: loadingBuilder ?? _defaultLoadingBuilder,
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: backgroundColor ?? Colors.grey[900],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie,
            size: iconSize ?? 64,
            color: iconColor ?? Colors.grey[700],
          ),
          if (title != null) ...[
            const SizedBox(height: 16),
            Text(
              title!,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _defaultErrorBuilder(BuildContext context, Object error, StackTrace? stackTrace) {
    Logger.w("加载图片失败: $imageUrl", _tag, error, stackTrace);
    return _buildPlaceholder(context);
  }

  Widget _defaultLoadingBuilder(BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
    if (loadingProgress == null) {
      return child;
    }

    return Container(
      width: width,
      height: height,
      color: backgroundColor ?? Colors.grey[900],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie,
            size: iconSize ?? 64,
            color: iconColor ?? Colors.grey[700],
          ),
          const SizedBox(height: 16),
          CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                : null,
          ),
        ],
      ),
    );
  }
} 