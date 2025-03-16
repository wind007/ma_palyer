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
      Logger.w('无效的图片URL: $imageUrl', _tag);
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
      color: backgroundColor ?? Colors.grey[300],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: iconSize ?? 32,
            color: iconColor ?? Colors.black45,
          ),
          if (title != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                title!,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _defaultErrorBuilder(BuildContext context, Object error, StackTrace? stackTrace) {
    Logger.e('加载图片失败: $imageUrl', _tag, error, stackTrace);
    return _buildPlaceholder(context);
  }

  Widget _defaultLoadingBuilder(BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
    if (loadingProgress == null) return child;
    return Container(
      width: width,
      height: height,
      color: backgroundColor ?? Colors.grey[200],
      child: Center(
        child: CircularProgressIndicator(
          value: loadingProgress.expectedTotalBytes != null
              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
              : null,
          strokeWidth: 2,
        ),
      ),
    );
  }
} 