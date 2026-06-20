// App Core
export 'app/app_cubit.dart';
export 'app/app_root_widget.dart';
export 'app/app_config_base.dart';

// App Startup
export 'app/startup/dreamic_app_init_gate.dart';
export 'app/startup/dreamic_app_init_host.dart';
export 'app/startup/dreamic_splash.dart';
export 'app/startup/dreamic_bootstrap.dart';

// Presentation Components
export 'presentation/network_error_widget.dart';
export 'presentation/app_state_wrapper.dart';

// Presentation Elements
export 'presentation/elements/error_message_widget.dart';
export 'presentation/elements/loading_indicator.dart';
export 'presentation/elements/overlay_submitting_widget.dart';
export 'presentation/elements/overlay_progress.dart';
export 'presentation/elements/app_update_widgets.dart';

// Notification Elements
export 'presentation/elements/notification_permission_bottom_sheet.dart';
export 'presentation/elements/notification_permission_status_widget.dart';
export 'presentation/elements/notification_permission_builder.dart';
export 'presentation/elements/notification_badge_widget.dart';

// Presentation Helpers
export 'presentation/helpers/bloc_exception.dart';
export 'presentation/helpers/colors_common.dart';
export 'presentation/helpers/cubit_base.dart';
export 'presentation/helpers/cubit_helpers.dart';
export 'presentation/helpers/loading_retry_wrapper.dart';
export 'presentation/helpers/loading_wrapper.dart';
export 'presentation/helpers/page_statuses.dart';
export 'presentation/helpers/sizes_common.dart';
export 'presentation/helpers/widget_helpers.dart';
export 'presentation/helpers/adaptive_icons.dart';

// App Helpers
export 'versioning/app_version_update_service.dart';
export 'app/helpers/app_lifecycle_service.dart';
export 'app/helpers/app_remote_config_init.dart';
export 'error_reporting/error_reporter_interface.dart';
export 'app/helpers/app_errorhandling_init.dart';
export 'app/helpers/app_configs_init.dart';
export 'app/helpers/app_firebase_init.dart';
export 'app/helpers/app_cubit_init.dart';

// Notification Helpers
export 'notifications/notification_service.dart';
export 'notifications/notification_permission_helper.dart';
export 'notifications/notification_background_handler.dart';
export 'notifications/notification_channel_manager.dart';
export 'notifications/notification_image_loader.dart';

// Notification Models
export 'data/models/notification_payload.dart';
export 'data/models/notification_action.dart';
export 'data/models/notification_permission_status.dart';

// Device Models
export 'data/models/device_platform.dart';
export 'data/models/device_info.dart';

// Responsive
// `show` clause is required (not cosmetic): `@visibleForTesting` is a lint-only
// annotation and does not remove `classify` from the exported API, so a bare
// export would leak it as a fifth symbol. The four §4 symbols are the entire
// public surface; `classify` stays importable directly from the implementation
// file for tests, and `_ResponsiveData` is private regardless.
export 'presentation/responsive/responsive.dart'
    show DeviceSize, Breakpoints, ResponsiveScope, ResponsiveContext;

// URL Opener
export 'presentation/helpers/url_opener/url_opener.dart';

// File Opener
export 'presentation/helpers/file_opener/fileopener.dart';

// App Reloader
export 'presentation/helpers/app_reloader/appreloader.dart';

// Data Models and Converters
export 'data/models_bases/base_firestore_model.dart';
export 'data/helpers/model_converters.dart';
export 'data/helpers/enum_converters.dart';
export 'data/helpers/repository_failure.dart';

// Data Repositories
export 'data/repos/auth_service_int.dart';
export 'data/repos/auth_service_impl.dart';
export 'data/repos/remote_config_repo_int.dart';
export 'data/repos/remote_config_repo_liveimple.dart';
export 'data/repos/device_service_int.dart';
export 'data/repos/device_service_impl.dart';
export 'data/repos/dreamic_services.dart';

// Utilities
export 'utils/logger.dart';
export 'utils/retry_it.dart';
export 'utils/string_validators.dart';


// Test Utilities
export 'test_utils/mock_app_cubit.dart';
