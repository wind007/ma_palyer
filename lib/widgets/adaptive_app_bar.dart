import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AdaptiveAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final ScrollController? scrollController;
  final bool centerTitle;
  final Widget? titleWidget;
  final bool floating;
  final bool pinned;
  final bool snap;
  final double? expandedHeight;
  final Widget? flexibleSpace;

  const AdaptiveAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.scrollController,
    this.centerTitle = true,
    this.titleWidget,
    this.floating = false,
    this.pinned = true,
    this.snap = false,
    this.expandedHeight,
    this.flexibleSpace,
  });

  SystemUiOverlayStyle _overlayStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appBarTheme = theme.appBarTheme;
    final overlay = _overlayStyle(context);
    final foreground =
        appBarTheme.foregroundColor ?? colorScheme.onSurface;
    final iconTheme =
        appBarTheme.iconTheme ?? IconThemeData(color: colorScheme.onSurface);

    final appBarWidget = AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: foreground,
      iconTheme: iconTheme,
      systemOverlayStyle: overlay,
      title: titleWidget ?? (title != null ? Text(title!) : null),
      actions: actions,
      leading: leading,
      bottom: bottom,
      centerTitle: centerTitle,
      flexibleSpace: flexibleSpace,
    );

    if (scrollController != null) {
      return SliverAppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: foreground,
        iconTheme: iconTheme,
        systemOverlayStyle: overlay,
        title: titleWidget ?? (title != null ? Text(title!) : null),
        actions: actions,
        leading: leading,
        bottom: bottom,
        centerTitle: centerTitle,
        floating: floating,
        pinned: pinned,
        snap: snap,
        expandedHeight: expandedHeight,
        flexibleSpace: flexibleSpace,
      );
    }

    return appBarWidget;
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));
} 