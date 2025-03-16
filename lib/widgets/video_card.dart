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
  // ignore: unused_field
  bool _isHovering = false;

  bool get _isCollection {
    final type = widget.video['Type']?.toString().toLowerCase();
    final collectionType = widget.video['CollectionType']?.toString().toLowerCase();
    return type == 'boxset' || collectionType == 'movies' || type == 'moviescollection';
  }

  @override
  Widget build(BuildContext context) {
    String? imageUrl;
    
    // 按优先级尝试获取不同类型的图片
    if (widget.video['ImageTags']?['Primary'] != null) {
      imageUrl = widget.api.getImageUrl(
        itemId: widget.video['Id'],
        imageType: 'Primary',
        width: widget.imageWidth,
        height: widget.imageHeight,
        quality: widget.imageQuality,
        tag: widget.video['ImageTags']['Primary'],
      );
    } else if (widget.video['ImageTags']?['Thumb'] != null) {
      imageUrl = widget.api.getImageUrl(
        itemId: widget.video['Id'],
        imageType: 'Thumb',
        width: widget.imageWidth,
        height: widget.imageHeight,
        quality: widget.imageQuality,
        tag: widget.video['ImageTags']['Thumb'],
      );
    } else if (widget.video['BackdropImageTags'] != null && 
              (widget.video['BackdropImageTags'] as List).isNotEmpty) {
      imageUrl = widget.api.getImageUrl(
        itemId: widget.video['Id'],
        imageType: 'Backdrop',
        width: widget.imageWidth,
        height: widget.imageHeight,
        quality: widget.imageQuality,
        tag: widget.video['BackdropImageTags'][0],
      );
    } else if (widget.video['ImageTags']?['Logo'] != null) {
      imageUrl = widget.api.getImageUrl(
        itemId: widget.video['Id'],
        imageType: 'Logo',
        width: widget.imageWidth,
        height: widget.imageHeight,
        quality: widget.imageQuality,
        tag: widget.video['ImageTags']['Logo'],
      );
    } else if (widget.video['ImageTags']?['Banner'] != null) {
      imageUrl = widget.api.getImageUrl(
        itemId: widget.video['Id'],
        imageType: 'Banner',
        width: widget.imageWidth,
        height: widget.imageHeight,
        quality: widget.imageQuality,
        tag: widget.video['ImageTags']['Banner'],
      );
    }

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
                      child: Stack(
                        children: [
                          // 图片
                          Positioned.fill(
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
                          // 渐变遮罩
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withAlpha(120),
                                  ],
                                  stops: const [0.7, 1.0],
                                ),
                              ),
                            ),
                          ),
                          // 状态图标
                          if (!_isCollection && (widget.video['UserData']?['IsFavorite'] == true || 
                              widget.video['UserData']?['Played'] == true))
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.video['UserData']?['IsFavorite'] == true)
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black38,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.favorite,
                                        color: Colors.red,
                                        size: 14,
                                      ),
                                    ),
                                  if (widget.video['UserData']?['IsFavorite'] == true && 
                                      widget.video['UserData']?['Played'] == true)
                                    const SizedBox(width: 4),
                                  if (widget.video['UserData']?['Played'] == true)
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black38,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 14,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          // 系列标识
                          if (_isCollection)
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.collections,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    if (widget.video['ChildCount'] != null) ...[
                                      const SizedBox(width: 2),
                                      Text(
                                        '${widget.video['ChildCount']}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          // 长按菜单触发区域
                          Positioned.fill(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => widget.onTap(widget.video),
                                onLongPress: () {
                                  _showOptionsDialog(context);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
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

  void _showOptionsDialog(BuildContext context) {
    // 如果是系列，不显示收藏和播放状态选项
    if (_isCollection) return;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  widget.video['UserData']?['IsFavorite'] == true
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: widget.video['UserData']?['IsFavorite'] == true
                      ? Colors.red
                      : null,
                ),
                title: const Text('收藏'),
                onTap: () async {
                  Navigator.pop(context);
                  final isFavorite = widget.video['UserData']?['IsFavorite'] == true;
                  final currentContext = context;
                  try {
                    await widget.api.toggleFavorite(widget.video['Id'], isFavorite);
                    if (!mounted) return;
                    setState(() {
                      widget.video['UserData'] ??= {};
                      widget.video['UserData']['IsFavorite'] = !isFavorite;
                    });
                  } catch (e) {
                    if (!mounted) return;
                    if (currentContext.mounted) {
                      ScaffoldMessenger.of(currentContext).showSnackBar(
                        SnackBar(content: Text('操作失败: $e')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  widget.video['UserData']?['Played'] == true
                      ? Icons.check_circle
                      : Icons.check_circle_outline,
                  color: widget.video['UserData']?['Played'] == true
                      ? Colors.green
                      : null,
                ),
                title: const Text('标记为已播放'),
                onTap: () async {
                  Navigator.pop(context);
                  final isPlayed = widget.video['UserData']?['Played'] == true;
                  final currentContext = context;
                  try {
                    await widget.api.togglePlayed(widget.video['Id'], isPlayed);
                    if (!mounted) return;
                    setState(() {
                      widget.video['UserData'] ??= {};
                      widget.video['UserData']['Played'] = !isPlayed;
                    });
                  } catch (e) {
                    if (!mounted) return;
                    if (currentContext.mounted) {
                      ScaffoldMessenger.of(currentContext).showSnackBar(
                        SnackBar(content: Text('操作失败: $e')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
} 