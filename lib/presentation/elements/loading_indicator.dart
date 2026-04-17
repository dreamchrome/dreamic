import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({
    super.key,
    this.radius = 20.0,
    this.brightness,
    this.showBackground = false,
  });

  final double radius;

  /// Explicit brightness override. When null, automatically derived from
  /// the current [Theme]. Pass [Brightness.dark] when the indicator sits
  /// on a dark surface regardless of the app theme (e.g. a frosted overlay).
  final Brightness? brightness;

  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    final bool isApplePlatform = kIsWeb || (Platform.isIOS || Platform.isMacOS);
    final bool isDark = (brightness ?? Theme.of(context).brightness) == Brightness.dark;
    final Color indicatorColor = isDark ? Colors.white : Colors.black87;

    return Container(
      decoration: showBackground
          ? BoxDecoration(
              color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            )
          : null,
      padding: showBackground ? const EdgeInsets.all(8.0) : null,
      width: radius * 2,
      height: radius * 2,
      child: isApplePlatform
          ? CupertinoActivityIndicator(
              radius: radius,
              color: indicatorColor,
            )
          : CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(indicatorColor),
            ),
    );
  }
}
