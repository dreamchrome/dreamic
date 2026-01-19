import 'package:flutter/widgets.dart';

/// Result of initializing notifications.
///
/// Returned by [NotificationService.initializeNotifications] to indicate
/// the outcome of the initialization attempt.
enum NotificationInitResult {
  /// Successfully initialized and permission granted.
  success,

  /// User denied notification permission (may be able to request again on Android).
  permissionDenied,

  /// Permission permanently denied - must direct user to system settings.
  /// (iOS after first denial, Android after "Don't ask again")
  permissionPermanentlyDenied,

  /// Permission request was blocked by the system (OEM restriction, etc.).
  /// The user never saw the dialog - don't count as a denial.
  permissionRequestBlocked,

  /// FCM is disabled in this AuthService instance.
  fcmDisabledInstance,

  /// FCM is disabled in AppConfigBase.
  fcmDisabledConfig,

  /// Already initialized.
  alreadyInitialized,

  /// Initialization failed due to an error.
  error,
}

/// Result of running the full notification permission flow.
///
/// Returned by [NotificationService.runNotificationPermissionFlow] to indicate
/// how the flow completed.
enum NotificationFlowResult {
  /// Permission granted (newly or already had it).
  granted,

  /// Permission was already granted, FCM initialized silently.
  alreadyGranted,

  /// User declined at value proposition dialog.
  declinedValueProposition,

  /// User denied the system permission request.
  deniedPermission,

  /// User denied permanently (iOS or Android "Don't ask again").
  deniedPermanently,

  /// User chose not to ask again after previous denial (denied state).
  skippedAskAgain,

  /// Skipped go-to-settings prompt due to config (showGoToSettingsPrompt=false,
  /// or timing/count limits reached).
  skippedGoToSettings,

  /// User declined to go to settings when prompted.
  declinedGoToSettings,

  /// User was directed to system settings (mobile platforms).
  /// The app cannot know if the user actually enabled notifications there.
  openedSettings,

  /// Web: User accepted the go-to-settings prompt but browser settings cannot
  /// be opened programmatically. The app should show manual instructions.
  /// This is distinct from [openedSettings] which is used on mobile platforms.
  shownWebInstructions,

  /// FCM is disabled in configuration.
  fcmDisabled,

  /// An error occurred.
  error,
}

/// Information about when/how notification permission was denied.
///
/// Used to implement "ask again after X days" or "ask again after Y launches" logic.
class NotificationDenialInfo {
  /// When the user last denied permission.
  final DateTime lastDenialTime;

  /// Total number of times permission was denied by the user.
  final int denialCount;

  /// Whether this was a permanent denial (user must go to settings).
  final bool isPermanent;

  /// Total number of times we attempted to request permission.
  /// (may be higher than denialCount if some requests were blocked)
  final int requestAttemptCount;

  /// When we last attempted to request permission.
  final DateTime? lastRequestAttemptTime;

  /// Whether the last request was blocked by the system (no dialog shown).
  final bool lastRequestWasBlocked;

  const NotificationDenialInfo({
    required this.lastDenialTime,
    required this.denialCount,
    required this.isPermanent,
    this.requestAttemptCount = 0,
    this.lastRequestAttemptTime,
    this.lastRequestWasBlocked = false,
  });

  /// Creates a [NotificationDenialInfo] from JSON.
  factory NotificationDenialInfo.fromJson(Map<String, dynamic> json) {
    return NotificationDenialInfo(
      lastDenialTime: DateTime.fromMillisecondsSinceEpoch(
        json['lastDenialTime'] as int,
      ),
      denialCount: json['denialCount'] as int,
      isPermanent: json['isPermanent'] as bool,
      requestAttemptCount: json['requestAttemptCount'] as int? ?? 0,
      lastRequestAttemptTime: json['lastRequestAttemptTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              json['lastRequestAttemptTime'] as int,
            )
          : null,
      lastRequestWasBlocked: json['lastRequestWasBlocked'] as bool? ?? false,
    );
  }

  /// Converts this [NotificationDenialInfo] to JSON.
  Map<String, dynamic> toJson() {
    return {
      'lastDenialTime': lastDenialTime.millisecondsSinceEpoch,
      'denialCount': denialCount,
      'isPermanent': isPermanent,
      'requestAttemptCount': requestAttemptCount,
      'lastRequestAttemptTime': lastRequestAttemptTime?.millisecondsSinceEpoch,
      'lastRequestWasBlocked': lastRequestWasBlocked,
    };
  }

  /// Creates a copy of this [NotificationDenialInfo] with the given fields replaced.
  NotificationDenialInfo copyWith({
    DateTime? lastDenialTime,
    int? denialCount,
    bool? isPermanent,
    int? requestAttemptCount,
    DateTime? lastRequestAttemptTime,
    bool? lastRequestWasBlocked,
  }) {
    return NotificationDenialInfo(
      lastDenialTime: lastDenialTime ?? this.lastDenialTime,
      denialCount: denialCount ?? this.denialCount,
      isPermanent: isPermanent ?? this.isPermanent,
      requestAttemptCount: requestAttemptCount ?? this.requestAttemptCount,
      lastRequestAttemptTime: lastRequestAttemptTime ?? this.lastRequestAttemptTime,
      lastRequestWasBlocked: lastRequestWasBlocked ?? this.lastRequestWasBlocked,
    );
  }

  @override
  String toString() {
    return 'NotificationDenialInfo('
        'lastDenialTime: $lastDenialTime, '
        'denialCount: $denialCount, '
        'isPermanent: $isPermanent, '
        'requestAttemptCount: $requestAttemptCount, '
        'lastRequestAttemptTime: $lastRequestAttemptTime, '
        'lastRequestWasBlocked: $lastRequestWasBlocked)';
  }
}

/// Information about "go to settings" prompts shown to user.
///
/// Used to implement configurable limits on how often to prompt users
/// to enable notifications via settings.
class GoToSettingsPromptInfo {
  /// When the user was last shown the "go to settings" prompt.
  final DateTime lastPromptTime;

  /// Total number of times the prompt was shown.
  final int promptCount;

  /// Whether user declined (false) or opened settings (true) last time.
  final bool lastActionWasOpenSettings;

  const GoToSettingsPromptInfo({
    required this.lastPromptTime,
    required this.promptCount,
    required this.lastActionWasOpenSettings,
  });

  /// Creates a [GoToSettingsPromptInfo] from JSON.
  factory GoToSettingsPromptInfo.fromJson(Map<String, dynamic> json) {
    return GoToSettingsPromptInfo(
      lastPromptTime: DateTime.fromMillisecondsSinceEpoch(
        json['lastPromptTime'] as int,
      ),
      promptCount: json['promptCount'] as int,
      lastActionWasOpenSettings: json['lastActionWasOpenSettings'] as bool,
    );
  }

  /// Converts this [GoToSettingsPromptInfo] to JSON.
  Map<String, dynamic> toJson() {
    return {
      'lastPromptTime': lastPromptTime.millisecondsSinceEpoch,
      'promptCount': promptCount,
      'lastActionWasOpenSettings': lastActionWasOpenSettings,
    };
  }

  /// Creates a copy of this [GoToSettingsPromptInfo] with the given fields replaced.
  GoToSettingsPromptInfo copyWith({
    DateTime? lastPromptTime,
    int? promptCount,
    bool? lastActionWasOpenSettings,
  }) {
    return GoToSettingsPromptInfo(
      lastPromptTime: lastPromptTime ?? this.lastPromptTime,
      promptCount: promptCount ?? this.promptCount,
      lastActionWasOpenSettings: lastActionWasOpenSettings ?? this.lastActionWasOpenSettings,
    );
  }

  @override
  String toString() {
    return 'GoToSettingsPromptInfo('
        'lastPromptTime: $lastPromptTime, '
        'promptCount: $promptCount, '
        'lastActionWasOpenSettings: $lastActionWasOpenSettings)';
  }
}

/// Strings for the notification permission flow dialogs.
///
/// Provide localized versions of these for your app.
class NotificationFlowStrings {
  // Value proposition dialog (shown first time)
  final String valuePropositionTitle;
  final String valuePropositionMessage;
  final String valuePropositionAcceptButton;
  final String valuePropositionDeclineButton;

  // Go to settings dialog (shown when permanently denied)
  final String goToSettingsTitle;
  final String goToSettingsMessage;
  final String goToSettingsButton;
  final String goToSettingsCancelButton;

  // Ask again dialog (shown after previous denial, when can retry)
  final String askAgainTitle;
  final String askAgainMessage;
  final String askAgainAcceptButton;
  final String askAgainDeclineButton;

  // Web-specific: Instructions when can't open settings
  final String webSettingsInstructionsTitle;
  final String webSettingsInstructionsMessage;
  final String webSettingsInstructionsButton;

  const NotificationFlowStrings({
    this.valuePropositionTitle = 'Enable Notifications',
    this.valuePropositionMessage = 'Stay updated with important alerts and messages.',
    this.valuePropositionAcceptButton = 'Enable',
    this.valuePropositionDeclineButton = 'Not Now',
    this.goToSettingsTitle = 'Notifications Disabled',
    this.goToSettingsMessage =
        'To receive notifications, please enable them in your device settings.',
    this.goToSettingsButton = 'Open Settings',
    this.goToSettingsCancelButton = 'Cancel',
    this.askAgainTitle = 'Enable Notifications?',
    this.askAgainMessage =
        'You previously declined notifications. Would you like to enable them now?',
    this.askAgainAcceptButton = 'Yes, Enable',
    this.askAgainDeclineButton = 'No Thanks',
    this.webSettingsInstructionsTitle = 'Enable Notifications',
    this.webSettingsInstructionsMessage = 'To enable notifications:\n\n'
        "1. Click the lock/info icon in your browser's address bar\n"
        '2. Find "Notifications" in the permissions list\n'
        '3. Change it from "Block" to "Allow"\n'
        '4. Refresh this page',
    this.webSettingsInstructionsButton = 'Got It',
  });

  /// Creates a copy of this [NotificationFlowStrings] with the given fields replaced.
  NotificationFlowStrings copyWith({
    String? valuePropositionTitle,
    String? valuePropositionMessage,
    String? valuePropositionAcceptButton,
    String? valuePropositionDeclineButton,
    String? goToSettingsTitle,
    String? goToSettingsMessage,
    String? goToSettingsButton,
    String? goToSettingsCancelButton,
    String? askAgainTitle,
    String? askAgainMessage,
    String? askAgainAcceptButton,
    String? askAgainDeclineButton,
    String? webSettingsInstructionsTitle,
    String? webSettingsInstructionsMessage,
    String? webSettingsInstructionsButton,
  }) {
    return NotificationFlowStrings(
      valuePropositionTitle: valuePropositionTitle ?? this.valuePropositionTitle,
      valuePropositionMessage: valuePropositionMessage ?? this.valuePropositionMessage,
      valuePropositionAcceptButton:
          valuePropositionAcceptButton ?? this.valuePropositionAcceptButton,
      valuePropositionDeclineButton:
          valuePropositionDeclineButton ?? this.valuePropositionDeclineButton,
      goToSettingsTitle: goToSettingsTitle ?? this.goToSettingsTitle,
      goToSettingsMessage: goToSettingsMessage ?? this.goToSettingsMessage,
      goToSettingsButton: goToSettingsButton ?? this.goToSettingsButton,
      goToSettingsCancelButton: goToSettingsCancelButton ?? this.goToSettingsCancelButton,
      askAgainTitle: askAgainTitle ?? this.askAgainTitle,
      askAgainMessage: askAgainMessage ?? this.askAgainMessage,
      askAgainAcceptButton: askAgainAcceptButton ?? this.askAgainAcceptButton,
      askAgainDeclineButton: askAgainDeclineButton ?? this.askAgainDeclineButton,
      webSettingsInstructionsTitle:
          webSettingsInstructionsTitle ?? this.webSettingsInstructionsTitle,
      webSettingsInstructionsMessage:
          webSettingsInstructionsMessage ?? this.webSettingsInstructionsMessage,
      webSettingsInstructionsButton:
          webSettingsInstructionsButton ?? this.webSettingsInstructionsButton,
    );
  }
}

/// Configuration for the notification permission flow.
///
/// Allows customization of timing, limits, strings, and dialog builders.
class NotificationFlowConfig {
  //
  // Re-ask configuration (when permission denied but can still show system dialog)
  //

  /// How long to wait before asking again after denial.
  final Duration askAgainAfter;

  /// Maximum number of times to ask after denials (0 = never ask again).
  final int maxAskCount;

  //
  // Go-to-settings configuration (when permanently denied)
  //

  /// Whether to show the "go to settings" prompt at all when permanently denied.
  /// Set to false if your app should never prompt users to change settings.
  /// Default: true
  final bool showGoToSettingsPrompt;

  /// How long to wait before showing the "go to settings" prompt again.
  /// Only applies if user previously declined to go to settings.
  /// Default: 30 days (or Duration.zero to never ask again after first decline)
  final Duration goToSettingsAskAgainAfter;

  /// Maximum number of times to show the "go to settings" prompt.
  /// 0 = never show, 1 = show once only, null = unlimited (respects duration only)
  /// Default: null (unlimited, respects duration)
  final int? goToSettingsMaxAskCount;

  //
  // Strings and custom builders
  //

  /// Strings for built-in dialogs (for localization).
  final NotificationFlowStrings strings;

  /// Custom builder for value proposition dialog.
  /// Return true to proceed with permission request, false to cancel.
  /// If null, uses built-in dialog with [strings].
  final Future<bool> Function(BuildContext context)? valuePropositionBuilder;

  /// Custom builder for go-to-settings dialog.
  /// Return true to open settings, false to cancel.
  /// If null, uses built-in dialog with [strings].
  /// Note: If [showGoToSettingsPrompt] is false, this is never called.
  final Future<bool> Function(BuildContext context)? goToSettingsBuilder;

  /// Custom builder for ask-again dialog.
  /// Return true to ask again, false to skip.
  /// If null, uses built-in dialog with [strings].
  final Future<bool> Function(BuildContext context, NotificationDenialInfo info)? askAgainBuilder;

  const NotificationFlowConfig({
    // Re-ask defaults
    this.askAgainAfter = const Duration(days: 7),
    this.maxAskCount = 3,
    // Go-to-settings defaults
    this.showGoToSettingsPrompt = true,
    this.goToSettingsAskAgainAfter = const Duration(days: 30),
    this.goToSettingsMaxAskCount, // null = unlimited
    // Strings and builders
    this.strings = const NotificationFlowStrings(),
    this.valuePropositionBuilder,
    this.goToSettingsBuilder,
    this.askAgainBuilder,
  });

  /// Creates a copy of this [NotificationFlowConfig] with the given fields replaced.
  NotificationFlowConfig copyWith({
    Duration? askAgainAfter,
    int? maxAskCount,
    bool? showGoToSettingsPrompt,
    Duration? goToSettingsAskAgainAfter,
    int? goToSettingsMaxAskCount,
    NotificationFlowStrings? strings,
    Future<bool> Function(BuildContext context)? valuePropositionBuilder,
    Future<bool> Function(BuildContext context)? goToSettingsBuilder,
    Future<bool> Function(BuildContext context, NotificationDenialInfo info)? askAgainBuilder,
  }) {
    return NotificationFlowConfig(
      askAgainAfter: askAgainAfter ?? this.askAgainAfter,
      maxAskCount: maxAskCount ?? this.maxAskCount,
      showGoToSettingsPrompt: showGoToSettingsPrompt ?? this.showGoToSettingsPrompt,
      goToSettingsAskAgainAfter: goToSettingsAskAgainAfter ?? this.goToSettingsAskAgainAfter,
      goToSettingsMaxAskCount: goToSettingsMaxAskCount ?? this.goToSettingsMaxAskCount,
      strings: strings ?? this.strings,
      valuePropositionBuilder: valuePropositionBuilder ?? this.valuePropositionBuilder,
      goToSettingsBuilder: goToSettingsBuilder ?? this.goToSettingsBuilder,
      askAgainBuilder: askAgainBuilder ?? this.askAgainBuilder,
    );
  }
}
