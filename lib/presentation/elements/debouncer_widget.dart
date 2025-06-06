import 'package:flutter/material.dart';
import 'package:tap_debouncer/tap_debouncer.dart';

class DebouncerWidget extends StatelessWidget {
  const DebouncerWidget({
    super.key,
    required this.onTap,
    required this.builder,
  });

  final Function()? onTap;
  final Widget Function(BuildContext context, Function()? onTap) builder;

  @override
  Widget build(BuildContext context) {
    return TapDebouncer(
      // cooldown: const Duration(milliseconds: 1000),
      builder: builder,
      onTap: onTap != null
          ? () async {
              final result = onTap!();
              if (result is Future) {
                await result;
              }
            }
          : null,
    );
  }
}

class DebouncerInkedWell extends StatelessWidget {
  const DebouncerInkedWell({
    super.key,
    required this.onTap,
    this.borderRadius,
    required this.child,
  });

  final BorderRadius? borderRadius;
  final Function()? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return child;
    }
    // return InkWell(
    //   borderRadius: borderRadius,
    //   onTap: onTap,
    //   child: child,
    // );
    return DebouncerWidget(
      onTap: onTap,
      builder: (context, onDebounceTap) {
        return InkWell(
          borderRadius: borderRadius,
          onTap: onDebounceTap,
          child: child,
        );
      },
    );
  }
}

// class DebouncerInkedWell extends StatelessWidget {
//   const DebouncerInkedWell({
//     super.key,
//     required this.onTap,
//     this.borderRadius,
//     required this.child,
//   });

//   final BorderRadius? borderRadius;
//   final Function()? onTap;
//   final Widget child;

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(borderRadius: borderRadius, onTap: onTap, child: child);
//   }
// }
