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
  final int? crossAxisCount;
  final double childAspectRatio;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double cardWidth;
  final int imageWidth;
  final int imageHeight;
  final bool useSliverGrid;

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
    this.crossAxisCount,
    this.childAspectRatio = 0.6,
    this.crossAxisSpacing = 12,
    this.mainAxisSpacing = 12,
    this.cardWidth = 130,
    this.imageWidth = 200,
    this.imageHeight = 300,
    this.useSliverGrid = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePadding = padding ?? EdgeInsets.zero;
    
    final gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 200.0,  // 每个卡片的最大宽度
      childAspectRatio: childAspectRatio,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );

    final itemBuilder = (BuildContext context, int index) {
      if (index == videos.length) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      }

      final video = videos[index];
      return VideoCard(
        key: ValueKey(video['Id']),  // 添加唯一的key
        video: video,
        api: api,
        server: server,
        onTap: onVideoTap,
        width: cardWidth,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    };

    if (useSliverGrid) {
      return SliverPadding(
        padding: effectivePadding,
        sliver: SliverGrid(
          gridDelegate: gridDelegate,
          delegate: SliverChildBuilderDelegate(
            itemBuilder,
            childCount: videos.length + (hasMore ? 1 : 0),
          ),
        ),
      );
    }

    return GridView.builder(
      controller: scrollController,
      padding: effectivePadding,
      gridDelegate: gridDelegate,
      itemCount: videos.length + (hasMore ? 1 : 0),
      itemBuilder: itemBuilder,
    );
  }
} 