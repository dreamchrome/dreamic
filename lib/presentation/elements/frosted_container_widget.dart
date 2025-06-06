import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:dreamic/presentation/helpers/colors_common.dart';

class FrostedContainerWidget extends StatelessWidget {
  final Widget? child;
  final double blurAmount;
  final int opacity;
  final double borderRadius;
  final Color color;

  const FrostedContainerWidget({
    super.key,
    this.child,
    this.blurAmount = 15.0,
    this.opacity = ColorsCommon.alphaForOverlay,
    this.borderRadius = 0.0,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurAmount,
          sigmaY: blurAmount,
        ),
        child: Container(
          //color: Colors.white.withAlpha(AppColors.alphaForOverlay),
          decoration: BoxDecoration(
            color: color.withAlpha(opacity),
            //border: Border.all(color: Colors.grey),
          ),
          child: child ?? Container(),
        ),
      ),
    );
  }
}
