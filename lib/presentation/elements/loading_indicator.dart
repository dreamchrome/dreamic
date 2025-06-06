import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({
    super.key,
    this.radius = 20.0,
    this.darkMode = false,
    this.showBackground = false,
  });

  final double radius;
  final bool darkMode;
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    // final bool isApplePlatform = !kIsWeb && (Platform.isIOS || Platform.isMacOS);
    final bool isApplePlatform = kIsWeb || (Platform.isIOS || Platform.isMacOS);

    return Container(
      decoration: showBackground
          ? BoxDecoration(
              color: darkMode ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.4),
              shape: BoxShape.circle,
            )
          : null,
      padding: showBackground ? const EdgeInsets.all(8.0) : null,
      width: radius * 2,
      height: radius * 2,
      child: isApplePlatform
          ? CupertinoActivityIndicator(
              // radius: radius / 2,
              radius: radius,
              // color: darkMode ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
              color: darkMode ? const Color(0xFFFFFFFF) : null,
            )
          : CircularProgressIndicator(
              // strokeWidth: radius / 10,
              valueColor: darkMode ? const AlwaysStoppedAnimation<Color>(
                  // darkMode ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
                  Color(0xFFFFFFFF)) : null,
            ),
    );
  }
}
