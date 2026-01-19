import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/widgets.dart';

import '../../notifications/notification_types.dart';

/// Built-in dialogs for the notification permission flow.
///
/// Uses adaptive_dialog for platform-native look (Material on Android, Cupertino on iOS).

/// Shows a value proposition dialog explaining why notifications are valuable.
///
/// Returns `true` if user wants to proceed with permission request, `false` otherwise.
Future<bool> showNotificationValuePropositionDialog(
  BuildContext context,
  NotificationFlowStrings strings,
) async {
  final result = await showOkCancelAlertDialog(
    context: context,
    title: strings.valuePropositionTitle,
    message: strings.valuePropositionMessage,
    okLabel: strings.valuePropositionAcceptButton,
    cancelLabel: strings.valuePropositionDeclineButton,
  );
  return result == OkCancelResult.ok;
}

/// Shows a dialog prompting the user to go to system settings to enable notifications.
///
/// Returns `true` if user wants to open settings, `false` otherwise.
Future<bool> showNotificationGoToSettingsDialog(
  BuildContext context,
  NotificationFlowStrings strings,
) async {
  final result = await showOkCancelAlertDialog(
    context: context,
    title: strings.goToSettingsTitle,
    message: strings.goToSettingsMessage,
    okLabel: strings.goToSettingsButton,
    cancelLabel: strings.goToSettingsCancelButton,
  );
  return result == OkCancelResult.ok;
}

/// Shows a dialog asking the user if they want to enable notifications after previously declining.
///
/// The [info] parameter contains information about previous denials, which can be used
/// for custom logic if needed.
///
/// Returns `true` if user wants to try enabling notifications again, `false` otherwise.
Future<bool> showNotificationAskAgainDialog(
  BuildContext context,
  NotificationFlowStrings strings,
  NotificationDenialInfo info,
) async {
  final result = await showOkCancelAlertDialog(
    context: context,
    title: strings.askAgainTitle,
    message: strings.askAgainMessage,
    okLabel: strings.askAgainAcceptButton,
    cancelLabel: strings.askAgainDeclineButton,
  );
  return result == OkCancelResult.ok;
}

/// Shows web-specific instructions for enabling notifications in the browser.
///
/// Unlike mobile platforms, web cannot programmatically open browser settings,
/// so this dialog provides step-by-step instructions instead.
///
/// Returns `true` when user acknowledges the instructions.
Future<bool> showWebSettingsInstructionsDialog(
  BuildContext context,
  NotificationFlowStrings strings,
) async {
  final result = await showOkAlertDialog(
    context: context,
    title: strings.webSettingsInstructionsTitle,
    message: strings.webSettingsInstructionsMessage,
    okLabel: strings.webSettingsInstructionsButton,
  );
  return result == OkCancelResult.ok;
}
