import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../utils/logger.dart';

class VideoCard extends StatefulWidget {
  final Map<String, dynamic> video;
  final EmbyApiService api;
  final ServerInfo server;
  final Function(Map<String, dynamic>) onTap;
  final double width;
  final int imageWidth;
  final int imageHeight;
  final int imageQuality;

  const VideoCard({
    super.key,
    required this.video,
    required this.api,
    required this.server,
    required this.onTap,
    this.width = 130,
    this.imageWidth = 200,
    this.imageHeight = 300,
    this.imageQuality = 80,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  static const String _tag = "VideoCard";
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final primaryTag = widget.video['ImageTags']?['Primary'];
    final imageUrl = primaryTag != null ? widget.api.getImageUrl(
      itemId: widget.video['Id'],
      imageType: 'Primary',
      width: widget.imageWidth,
      height: widget.imageHeight,
      quality: widget.imageQuality,
      tag: primaryTag,
    ) : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: () => widget.onTap(widget.video),
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 2/3,
                      child: imageUrl != null && imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            headers: {
                              'X-Emby-Token': widget.server.accessToken,
                            },
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: Colors.grey[200],
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                        : null,
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              Logger.e('加载图片失败: $imageUrl', _tag, error);
                              return _buildPlaceholder();
                            },
                          )
                        : _buildPlaceholder(),
                    ),
                  ),
                  // 收藏和播放状态按钮
                  if (_isHovering)
                    Positioned(
                      right: 4,
                      bottom: 36,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: IconButton(
                              iconSize: 18,
                              padding: const EdgeInsets.all(3),
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                widget.video['UserData']?['IsFavorite'] == true
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: widget.video['UserData']?['IsFavorite'] == true
                                    ? Colors.red
                                    : Colors.white,
                              ),
                              onPressed: () async {
                                final BuildContext currentContext = context;
                                try {
                                  final isFavorite = widget.video['UserData']?['IsFavorite'] == true;
                                  await widget.api.toggleFavorite(widget.video['Id'], isFavorite);
                                  if (!mounted) return;
                                  setState(() {
                                    widget.video['UserData'] ??= {};
                                    widget.video['UserData']['IsFavorite'] = !isFavorite;
                                  });
                                } catch (e) {
                                  if (!currentContext.mounted) return;
                                  ScaffoldMessenger.of(currentContext).showSnackBar(
                                    SnackBar(content: Text('操作失败: $e')),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: IconButton(
                              iconSize: 18,
                              padding: const EdgeInsets.all(3),
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                widget.video['UserData']?['Played'] == true
                                    ? Icons.check_circle
                                    : Icons.check_circle_outline,
                                color: widget.video['UserData']?['Played'] == true
                                    ? Colors.green
                                    : Colors.white,
                              ),
                              onPressed: () async {
                                final BuildContext currentContext = context;
                                try {
                                  final isPlayed = widget.video['UserData']?['Played'] == true;
                                  await widget.api.togglePlayed(widget.video['Id'], isPlayed);
                                  if (!mounted) return;
                                  setState(() {
                                    widget.video['UserData'] ??= {};
                                    widget.video['UserData']['Played'] = !isPlayed;
                                  });
                                } catch (e) {
                                  if (!currentContext.mounted) return;
                                  ScaffoldMessenger.of(currentContext).showSnackBar(
                                    SnackBar(content: Text('操作失败: $e')),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  // 播放进度条
                  if (widget.video['UserData']?['PlaybackPositionTicks'] != null &&
                      widget.video['UserData']?['PlaybackPositionTicks'] > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: widget.video['UserData']?['PlaybackPositionTicks'] /
                            widget.video['RunTimeTicks'],
                        backgroundColor: Colors.black45,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.red,
                        ),
                        minHeight: 2,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 1),
              Text(
                widget.video['Name'] ?? '未知标题',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.image_not_supported_outlined,
            size: 32,
            color: Colors.black45,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              widget.video['Name'] ?? '未知标题',
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
      ),
    );
  }
} 