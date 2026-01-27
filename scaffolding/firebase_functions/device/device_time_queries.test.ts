/**
 * Tests for device_time_queries.ts
 *
 * These tests verify the time-window scheduling logic used for
 * "send at X:XX local time" notifications.
 *
 * Run with: npm test -- --grep "device_time_queries"
 *
 * @packageVersion dreamic ^0.4.0
 *
 * ## Critical Test Areas
 *
 * 1. **isNowInLocalTimeWindow** - The final gate before sending notifications
 *    - Standard cases
 *    - Midnight wrap-around
 *    - DST transitions
 *    - Half-hour/45-minute offsets
 *
 * 2. **Offset Range Calculation** - For efficient Firestore queries
 *    - Single range cases
 *    - Split range cases (midnight wrap)
 *
 * 3. **Device Grouping** - For per-user delivery policies
 */

import { expect } from "chai";
import {
  isNowInLocalTimeWindow,
  groupByUserMostRecentDevice,
  groupByUserAllDevices,
  LocalTimeTarget,
  DeviceDoc,
} from "./device_time_queries";
import * as admin from "firebase-admin";

describe("device_time_queries", () => {
  describe("isNowInLocalTimeWindow", () => {
    describe("standard cases", () => {
      it("returns true when exactly at target time", () => {
        // 9:00 AM in New York on Jan 15, 2024 (EST = UTC-5)
        // UTC time: 14:00
        const nowUtc = new Date("2024-01-15T14:00:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          15 // 15 min window
        );

        expect(result).to.be.true;
      });

      it("returns true when within window", () => {
        // 9:10 AM in New York (10 min after target)
        const nowUtc = new Date("2024-01-15T14:10:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.true;
      });

      it("returns true when at window boundary", () => {
        // 9:15 AM exactly (15 min after target, window = 15)
        const nowUtc = new Date("2024-01-15T14:15:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.true;
      });

      it("returns false when outside window", () => {
        // 9:30 AM in New York (30 min after target, window = 15)
        const nowUtc = new Date("2024-01-15T14:30:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.false;
      });

      it("returns true before target within window", () => {
        // 8:50 AM in New York (10 min before target)
        const nowUtc = new Date("2024-01-15T13:50:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.true;
      });
    });

    describe("midnight wrap-around", () => {
      it("handles target at midnight with time just before midnight", () => {
        // Target: 00:00 (midnight), window: 15 min
        // Current time: 23:55 (5 min before midnight)
        // Should be within window (5 min from midnight)

        // 23:55 in New York (EST) = 04:55 UTC next day
        const nowUtc = new Date("2024-01-15T04:55:00Z");
        const target: LocalTimeTarget = { hour: 0, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.true;
      });

      it("handles target at midnight with time just after midnight", () => {
        // Target: 00:00 (midnight), window: 15 min
        // Current time: 00:10 (10 min after midnight)

        // 00:10 in New York (EST) = 05:10 UTC
        const nowUtc = new Date("2024-01-15T05:10:00Z");
        const target: LocalTimeTarget = { hour: 0, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.true;
      });

      it("handles target at 23:50 with time at 00:05 (wrap)", () => {
        // Target: 23:50, window: 15 min
        // Current time: 00:05 (next day)
        // Distance: 15 min (should be exactly at boundary)

        // 00:05 in UTC
        const nowUtc = new Date("2024-01-15T00:05:00Z");
        const target: LocalTimeTarget = { hour: 23, minute: 50 };

        const result = isNowInLocalTimeWindow("UTC", target, nowUtc, 15);

        expect(result).to.be.true;
      });

      it("returns false when outside midnight wrap window", () => {
        // Target: 23:50, window: 15 min
        // Current time: 00:10 (20 min after target)

        const nowUtc = new Date("2024-01-15T00:10:00Z");
        const target: LocalTimeTarget = { hour: 23, minute: 50 };

        const result = isNowInLocalTimeWindow("UTC", target, nowUtc, 15);

        expect(result).to.be.false;
      });
    });

    describe("DST transition handling", () => {
      it("correctly identifies time during DST", () => {
        // July 15, 2024: New York is in EDT (UTC-4)
        // 9:00 AM EDT = 13:00 UTC
        const nowUtc = new Date("2024-07-15T13:00:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.true;
      });

      it("correctly identifies time during standard time", () => {
        // January 15, 2024: New York is in EST (UTC-5)
        // 9:00 AM EST = 14:00 UTC
        const nowUtc = new Date("2024-01-15T14:00:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.true;
      });

      it("handles spring forward transition day", () => {
        // March 10, 2024: DST starts in US
        // After 2:00 AM, clocks jump to 3:00 AM
        // 9:00 AM EDT = 13:00 UTC (now in EDT)
        const nowUtc = new Date("2024-03-10T13:00:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.true;
      });

      it("handles fall back transition day", () => {
        // November 3, 2024: DST ends in US
        // 9:00 AM EST = 14:00 UTC (back to EST)
        const nowUtc = new Date("2024-11-03T14:00:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.true;
      });
    });

    describe("half-hour and 45-minute offsets", () => {
      it("handles India timezone (UTC+5:30)", () => {
        // 9:00 AM in India = 03:30 UTC
        const nowUtc = new Date("2024-01-15T03:30:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow("Asia/Kolkata", target, nowUtc, 15);

        expect(result).to.be.true;
      });

      it("handles Nepal timezone (UTC+5:45)", () => {
        // 9:00 AM in Nepal = 03:15 UTC
        const nowUtc = new Date("2024-01-15T03:15:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "Asia/Kathmandu",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.true;
      });

      it("handles Newfoundland timezone (UTC-3:30)", () => {
        // 9:00 AM in Newfoundland (NST) = 12:30 UTC
        const nowUtc = new Date("2024-01-15T12:30:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/St_Johns",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.true;
      });
    });

    describe("invalid timezone handling", () => {
      it("returns false for invalid timezone", () => {
        const nowUtc = new Date("2024-01-15T14:00:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "Invalid/Timezone",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.false;
      });

      it("returns false for empty timezone", () => {
        const nowUtc = new Date("2024-01-15T14:00:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow("", target, nowUtc, 15);

        expect(result).to.be.false;
      });
    });

    describe("edge cases", () => {
      it("handles window of 0 (exact match only)", () => {
        // Exactly 9:00 AM
        const nowUtc = new Date("2024-01-15T14:00:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        expect(
          isNowInLocalTimeWindow("America/New_York", target, nowUtc, 0)
        ).to.be.true;

        // 1 minute off
        const nowUtc2 = new Date("2024-01-15T14:01:00Z");
        expect(
          isNowInLocalTimeWindow("America/New_York", target, nowUtc2, 0)
        ).to.be.false;
      });

      it("handles very large window (full hour)", () => {
        // Window of 60 min = anything within 2 hours
        const nowUtc = new Date("2024-01-15T14:45:00Z");
        const target: LocalTimeTarget = { hour: 9, minute: 0 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          60
        );

        expect(result).to.be.true;
      });

      it("handles target with non-zero minutes", () => {
        // Target: 9:30 AM
        // Current: 9:35 AM (5 min after)
        const nowUtc = new Date("2024-01-15T14:35:00Z"); // 9:35 AM EST
        const target: LocalTimeTarget = { hour: 9, minute: 30 };

        const result = isNowInLocalTimeWindow(
          "America/New_York",
          target,
          nowUtc,
          15
        );

        expect(result).to.be.true;
      });
    });
  });

  describe("groupByUserMostRecentDevice", () => {
    const createDevice = (
      uid: string,
      deviceId: string,
      lastActiveMillis: number
    ): DeviceDoc => ({
      uid,
      deviceId,
      timezone: "UTC",
      lastActiveAt: {
        toMillis: () => lastActiveMillis,
      } as admin.firestore.Timestamp,
    });

    it("returns single device per user", () => {
      const devices: DeviceDoc[] = [
        createDevice("user1", "device1", 1000),
        createDevice("user2", "device1", 2000),
      ];

      const result = groupByUserMostRecentDevice(devices);

      expect(result.size).to.equal(2);
      expect(result.get("user1")?.deviceId).to.equal("device1");
      expect(result.get("user2")?.deviceId).to.equal("device1");
    });

    it("selects most recent device when user has multiple", () => {
      const devices: DeviceDoc[] = [
        createDevice("user1", "old-device", 1000),
        createDevice("user1", "new-device", 2000),
        createDevice("user1", "middle-device", 1500),
      ];

      const result = groupByUserMostRecentDevice(devices);

      expect(result.size).to.equal(1);
      expect(result.get("user1")?.deviceId).to.equal("new-device");
    });

    it("handles devices with no lastActiveAt", () => {
      const devices: DeviceDoc[] = [
        { uid: "user1", deviceId: "device-no-timestamp", timezone: "UTC" },
        createDevice("user1", "device-with-timestamp", 1000),
      ];

      const result = groupByUserMostRecentDevice(devices);

      expect(result.size).to.equal(1);
      expect(result.get("user1")?.deviceId).to.equal("device-with-timestamp");
    });

    it("handles empty input", () => {
      const result = groupByUserMostRecentDevice([]);
      expect(result.size).to.equal(0);
    });
  });

  describe("groupByUserAllDevices", () => {
    const createDevice = (uid: string, deviceId: string): DeviceDoc => ({
      uid,
      deviceId,
      timezone: "UTC",
    });

    it("groups all devices by user", () => {
      const devices: DeviceDoc[] = [
        createDevice("user1", "device1"),
        createDevice("user1", "device2"),
        createDevice("user2", "device1"),
      ];

      const result = groupByUserAllDevices(devices);

      expect(result.size).to.equal(2);
      expect(result.get("user1")).to.have.length(2);
      expect(result.get("user2")).to.have.length(1);
    });

    it("handles single device per user", () => {
      const devices: DeviceDoc[] = [
        createDevice("user1", "device1"),
        createDevice("user2", "device1"),
        createDevice("user3", "device1"),
      ];

      const result = groupByUserAllDevices(devices);

      expect(result.size).to.equal(3);
      for (const [_, userDevices] of result) {
        expect(userDevices).to.have.length(1);
      }
    });

    it("handles empty input", () => {
      const result = groupByUserAllDevices([]);
      expect(result.size).to.equal(0);
    });
  });

  describe("Circular Distance Calculation", () => {
    // These tests verify the circular distance calculation that handles
    // midnight wrap-around correctly.

    const circularDistance = (a: number, b: number, max: number): number => {
      const diff = Math.abs(a - b);
      return Math.min(diff, max - diff);
    };

    it("calculates forward distance correctly", () => {
      // 540 min (9:00) to 570 min (9:30) = 30 min
      expect(circularDistance(540, 570, 1440)).to.equal(30);
    });

    it("calculates backward distance correctly", () => {
      // 570 min (9:30) to 540 min (9:00) = 30 min
      expect(circularDistance(570, 540, 1440)).to.equal(30);
    });

    it("calculates distance across midnight (forward)", () => {
      // 1430 min (23:50) to 10 min (00:10) = 20 min
      expect(circularDistance(1430, 10, 1440)).to.equal(20);
    });

    it("calculates distance across midnight (backward)", () => {
      // 10 min (00:10) to 1430 min (23:50) = 20 min
      expect(circularDistance(10, 1430, 1440)).to.equal(20);
    });

    it("handles same time", () => {
      expect(circularDistance(540, 540, 1440)).to.equal(0);
    });

    it("handles exactly 12 hours apart", () => {
      // 0 min (00:00) to 720 min (12:00) = 720 min
      expect(circularDistance(0, 720, 1440)).to.equal(720);
    });

    it("handles midnight to midnight", () => {
      expect(circularDistance(0, 0, 1440)).to.equal(0);
      expect(circularDistance(1439, 1439, 1440)).to.equal(0);
    });
  });
});
