import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dreamic/versioning/app_version_update_service.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:dreamic/presentation/helpers/app_reloader/appreloader.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateBanner extends StatelessWidget {
  final VersionUpdateInfo updateInfo;
  final VoidCallback? onDismiss;
  final bool showCloseButton;

  const AppUpdateBanner({
    super.key,
    required this.updateInfo,
    this.onDismiss,
    this.showCloseButton = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!updateInfo.hasUpdate) {
      return const SizedBox.shrink();
    }

    return Material(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: updateInfo.isRequired
              ? Theme.of(context).colorScheme.errorContainer
              : Theme.of(context).colorScheme.primaryContainer,
          border: Border(
            bottom: BorderSide(
              color: updateInfo.isRequired
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              updateInfo.isRequired ? Icons.warning : Icons.info,
              color: updateInfo.isRequired
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    updateInfo.isRequired ? 'App Update Required' : 'App Update Available',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: updateInfo.isRequired
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    updateInfo.isRequired
                        ? kIsWeb
                            ? 'Please refresh to version ${updateInfo.targetVersion} to continue using the app.'
                            : 'Please update to version ${updateInfo.targetVersion} to continue using the app.'
                        : kIsWeb
                            ? 'Version ${updateInfo.targetVersion} is now available.'
                            : 'Version ${updateInfo.targetVersion} is now available.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: updateInfo.isRequired
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () => kIsWeb ? reloadApp() : _launchAppStore(updateInfo.appStoreUrl),
              style: ElevatedButton.styleFrom(
                backgroundColor: updateInfo.isRequired
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
                foregroundColor: updateInfo.isRequired
                    ? Theme.of(context).colorScheme.onError
                    : Theme.of(context).colorScheme.onPrimary,
              ),
              child: Text(kIsWeb ? 'Refresh' : 'Update'),
            ),
            if (showCloseButton && !updateInfo.isRequired) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: onDismiss,
                icon: Icon(
                  Icons.close,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _launchAppStore(String url) async {
    logd('Launching app store: $url');
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        loge('Could not launch app store URL: $url');
      }
    } catch (e) {
      loge('Error launching app store: $e');
    }
  }
}

class AppUpdateToast extends StatefulWidget {
  final VersionUpdateInfo updateInfo;
  final Duration displayDuration;
  final VoidCallback? onDismiss;

  const AppUpdateToast({
    super.key,
    required this.updateInfo,
    this.displayDuration = const Duration(seconds: 8),
    this.onDismiss,
  });

  @override
  State<AppUpdateToast> createState() => _AppUpdateToastState();
}

class _AppUpdateToastState extends State<AppUpdateToast> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();

    // Auto dismiss for recommended updates
    if (!widget.updateInfo.isRequired) {
      Future.delayed(widget.displayDuration, () {
        if (mounted) {
          _dismiss();
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _dismiss() {
    _animationController.reverse().then((_) {
      widget.onDismiss?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.updateInfo.hasUpdate) {
      return const SizedBox.shrink();
    }

    return SlideTransition(
      position: _slideAnimation,
      child: AppUpdateBanner(
        updateInfo: widget.updateInfo,
        onDismiss: widget.updateInfo.isRequired ? null : _dismiss,
        showCloseButton: !widget.updateInfo.isRequired,
      ),
    );
  }
}

class AppUpdateDialog extends StatelessWidget {
  final VersionUpdateInfo updateInfo;

  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          // Icon(
          //   updateInfo.isRequired ? Icons.warning : Icons.info,
          //   color: updateInfo.isRequired
          //       ? Theme.of(context).colorScheme.error
          //       : Theme.of(context).colorScheme.primary,
          // ),
          Icon(
            Icons.info,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            updateInfo.isRequired
                ? kIsWeb
                    ? 'Refresh Required'
                    : 'Update Required'
                : kIsWeb
                    ? 'Refresh Available'
                    : 'Update Available',
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            updateInfo.isRequired
                ? kIsWeb
                    ? 'An update is required to continue using the app. Please refresh to version ${updateInfo.targetVersion}.'
                    : 'An update is required to continue using the app. Please update to version ${updateInfo.targetVersion}.'
                : kIsWeb
                    ? 'A new version (${updateInfo.targetVersion}) is available. Would you like to refresh now?'
                    : 'A new version (${updateInfo.targetVersion}) is available. Would you like to update now?',
          ),
          const SizedBox(height: 16),
          Text(
            'Current version: ${updateInfo.currentVersion}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        if (!updateInfo.isRequired)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
        ElevatedButton(
          onPressed: () {
            if (kIsWeb) {
              reloadApp();
            } else {
              _launchAppStore(updateInfo.appStoreUrl);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: updateInfo.isRequired
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),
          child: Text(kIsWeb ? 'Refresh Now' : 'Update Now'),
        ),
      ],
    );
  }

  Future<void> _launchAppStore(String url) async {
    logd('Launching app store: $url');
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        loge('Could not launch app store URL: $url');
      }
    } catch (e) {
      loge('Error launching app store: $e');
    }
  }
}
