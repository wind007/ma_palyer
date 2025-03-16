import 'package:flutter/material.dart';
import '../services/emby_api.dart';
import '../services/server_manager.dart';
import './video_card.dart';

class VideoGrid extends StatelessWidget {
  
  final List<dynamic> videos;
  final EmbyApiService api;
  final ServerInfo server;
  final Function(Map<String, dynamic>) onVideoTap;
  final bool hasMore;
  final bool isLoading;
  final ScrollController scrollController;
  final EdgeInsets? padding;
  final int crossAxisCount;
  final double childAspectRatio;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double cardWidth;
  final int imageWidth;
  final int imageHeight;

  const VideoGrid({
    super.key,
    required this.videos,
    required this.api,
    required this.server,
    required this.onVideoTap,
    required this.hasMore,
    required this.isLoading,
    required this.scrollController,
    this.padding = const EdgeInsets.all(16),
    this.crossAxisCount = 5,
    this.childAspectRatio = 0.55,
    this.crossAxisSpacing = 8,
    this.mainAxisSpacing = 8,
    this.cardWidth = 120,
    this.imageWidth = 160,
    this.imageHeight = 240,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: scrollController,
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
      ),
      itemCount: videos.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == videos.length) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final video = videos[index];
        return VideoCard(
          video: video,
          api: api,
          server: server,
          onTap: onVideoTap,
          width: cardWidth,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        );
      },
    );
  }
} 