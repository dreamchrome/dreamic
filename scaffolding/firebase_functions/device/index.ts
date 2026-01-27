/**
 * DeviceService Firebase Functions scaffolding.
 *
 * This module exports the device management functions for use in consuming apps.
 *
 * @packageVersion dreamic ^0.4.0
 *
 * ## Quick Start
 *
 * 1. Copy this `device/` folder to your Firebase Functions `src/` directory
 * 2. Add to your main `index.ts`:
 *    ```typescript
 *    export * from "./device";
 *    ```
 * 3. Install dependencies:
 *    ```bash
 *    npm install luxon
 *    npm install -D @types/luxon
 *    ```
 * 4. Deploy:
 *    ```bash
 *    firebase deploy --only functions
 *    ```
 *
 * ## What's Exported
 *
 * **Required (client-facing):**
 * - `deviceAction` - Unified callable for device CRUD operations
 *
 * **Utilities (for your custom functions):**
 * - Timezone utilities from `./timezone_utils`
 * - Time-window query utilities from `./device_time_queries`
 *
 * **Optional Templates (NOT exported by default):**
 * - `device_scheduled.ts` - Scheduled function examples
 * - `device_triggers.ts` - Firestore trigger examples
 *
 * To use the optional templates, import and re-export them explicitly:
 * ```typescript
 * export { sendMorningNotifications } from "./device/device_scheduled";
 * export { onDeviceTimezoneChange } from "./device/device_triggers";
 * ```
 */

// ============================================================
// Client-Facing Callables (Required)
// ============================================================

export { deviceAction } from "./device_callable";

// ============================================================
// Utilities (for custom functions)
// ============================================================

// Timezone utilities
export {
  isValidIanaTimezone,
  getOffsetMinutesAtUtcInstant,
  getLocalMinutesOfDay,
  getLocalHour,
  isHourInTimezone,
  localTimeToUtc,
  validateOffsetMinutes,
  formatOffset,
} from "./timezone_utils";

export type { OffsetValidationResult } from "./timezone_utils";

// Time-window query utilities
export {
  queryDeviceCandidatesByLocalTime,
  isNowInLocalTimeWindow,
  getDevicesInLocalTimeWindow,
  groupByUserMostRecentDevice,
  groupByUserAllDevices,
} from "./device_time_queries";

export type {
  LocalTimeTarget,
  LocalTimeWindowQueryOptions,
  DeviceDoc,
} from "./device_time_queries";

// ============================================================
// Optional Templates (NOT exported - import explicitly if needed)
// ============================================================
// See device_scheduled.ts and device_triggers.ts for templates
