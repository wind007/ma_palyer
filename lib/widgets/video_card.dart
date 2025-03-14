import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import '../utils/logger.dart';

class VideoCard extends StatelessWidget {
  static const String _tag = "VideoCard";
  
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
  Widget build(BuildContext context) {
    final imageUrl = api.getImageUrl(
      itemId: video['Id'],
      imageType: 'Primary',
      width: imageWidth,
      height: imageHeight,
      quality: imageQuality,
      tag: video['ImageTags']?['Primary'],
    );

    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovering = false;
        
        return MouseRegion(
          onEnter: (_) => setState(() => isHovering = true),
          onExit: (_) => setState(() => isHovering = false),
          child: GestureDetector(
            onTap: () => onTap(video),
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 2/3,
                          child: Image.network(
                            imageUrl,
                            headers: {'X-Emby-Token': server.accessToken},
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey[300],
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      video['Name'] ?? '未知标题',
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      // 收藏和播放状态按钮
                      if (isHovering)
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
                                    video['UserData']?['IsFavorite'] == true
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: video['UserData']?['IsFavorite'] == true
                                        ? Colors.red
                                        : Colors.white,
                                  ),
                                  onPressed: () async {
                                    try {
                                      final isFavorite = video['UserData']?['IsFavorite'] == true;
                                      await api.toggleFavorite(video['Id'], isFavorite);
                                      setState(() {
                                        video['UserData'] ??= {};
                                        video['UserData']['IsFavorite'] = !isFavorite;
                                      });
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
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
                                    video['UserData']?['Played'] == true
                                        ? Icons.check_circle
                                        : Icons.check_circle_outline,
                                    color: video['UserData']?['Played'] == true
                                        ? Colors.green
                                        : Colors.white,
                                  ),
                                  onPressed: () async {
                                    try {
                                      final isPlayed = video['UserData']?['Played'] == true;
                                      await api.togglePlayed(video['Id'], isPlayed);
                                      setState(() {
                                        video['UserData'] ??= {};
                                        video['UserData']['Played'] = !isPlayed;
                                      });
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
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
                      if (video['UserData']?['PlaybackPositionTicks'] != null &&
                          video['UserData']?['PlaybackPositionTicks'] > 0)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            value: video['UserData']?['PlaybackPositionTicks'] /
                                video['RunTimeTicks'],
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
                    video['Name'] ?? '未知标题',
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
      },
    );
  }
} 