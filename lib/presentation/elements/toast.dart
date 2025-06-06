import 'package:flutter/material.dart';

class ToastManager {
  static final List<OverlayEntry> _toasts = [];
  // Track the current non-auto-dismissing toast
  static OverlayEntry? _currentPersistentToast;

  static void showToast(
    BuildContext context,
    Widget content, {
    bool autoDismiss = true,
    Duration duration = const Duration(seconds: 2),
    bool replacePrevious = true,
  }) {
    final overlay = Overlay.of(context);

    // If this is not an auto-dismissing toast and replacePrevious is true,
    // remove any existing persistent toast
    if (!autoDismiss && replacePrevious && _currentPersistentToast != null) {
      removeToast(entry: _currentPersistentToast);
      _currentPersistentToast = null;
    }

    // Create a controller to handle the toast state
    final toastController = ToastController();

    // Create the toast with its controller
    final toast = ToastWidget(
      content: content,
      controller: toastController,
    );

    // Create the overlay entry
    final overlayEntry = OverlayEntry(
      builder: (context) => toast,
    );

    // Set the overlay entry in the controller
    toastController.overlayEntry = overlayEntry;

    _toasts.add(overlayEntry);
    overlay.insert(overlayEntry);

    // Store reference to non-auto-dismissing toast
    if (!autoDismiss) {
      _currentPersistentToast = overlayEntry;
    }

    // Auto remove after duration if enabled
    if (autoDismiss) {
      Future.delayed(duration, () {
        removeToast(entry: overlayEntry);
      });
    }
  }

  static void removeToast({OverlayEntry? entry}) {
    if (entry != null && _toasts.contains(entry)) {
      // If this is the current persistent toast, clear the reference
      if (entry == _currentPersistentToast) {
        _currentPersistentToast = null;
      }

      _toasts.remove(entry);
      entry.remove();
    } else {
      // If no entry is provided, remove the last toast
      if (_toasts.isNotEmpty) {
        final lastToast = _toasts.last;
        _toasts.remove(lastToast);
        lastToast.remove();
      }
    }
  }
}

// Controller class to handle the mutable overlay entry reference
class ToastController {
  OverlayEntry? overlayEntry;
}

class ToastWidget extends StatefulWidget {
  final Widget content;
  final ToastController controller;

  // Now all fields are final, maintaining immutability
  const ToastWidget({
    super.key,
    required this.content,
    required this.controller,
  });

  @override
  _ToastWidgetState createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5), // Start slightly below
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);

    _controller.forward();
  }

  void dismiss() {
    _controller.reverse().then((_) {
      // Use the controller to access the overlay entry
      if (widget.controller.overlayEntry != null) {
        ToastManager.removeToast(entry: widget.controller.overlayEntry);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 24, // Account for status bar + extra padding
      left: 0,
      right: 0, // Left and right set to 0 for horizontal centering
      child: SlideTransition(
        position: _offsetAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            // Center horizontally
            child: Material(
              elevation: 20,
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.of(context).size.width * 0.85, // Reasonable max width constraint
                  minWidth: 100, // Some reasonable minimum width
                ),
                margin: const EdgeInsets.symmetric(horizontal: 16), // Horizontal margins
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: widget.content, // Let content determine size
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
