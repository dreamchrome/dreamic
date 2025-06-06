import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ScrollableWithScrollbars extends StatefulWidget {
  const ScrollableWithScrollbars({
    super.key,
    required this.child,
    this.controller,
    this.scrollbarsOnlyOnWeb = false,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final ScrollController? controller;
  final bool scrollbarsOnlyOnWeb;
  final EdgeInsetsGeometry padding;

  @override
  _ScrollableWithScrollbarsState createState() => _ScrollableWithScrollbarsState();
}

class _ScrollableWithScrollbarsState extends State<ScrollableWithScrollbars> {
  late final ScrollController scrollController;

  @override
  void initState() {
    super.initState();
    scrollController = widget.controller ?? ScrollController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      scrollController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: widget.scrollbarsOnlyOnWeb ? kIsWeb : true,
      trackVisibility: widget.scrollbarsOnlyOnWeb ? kIsWeb : true,
      controller: scrollController,
      child: SingleChildScrollView(
        padding: widget.padding,
        controller: scrollController,
        child: widget.child,
      ),
    );
  }
}
