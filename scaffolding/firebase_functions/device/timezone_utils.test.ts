/**
 * Tests for timezone_utils.ts
 *
 * These tests verify DST-safe timezone handling for device scheduling.
 * Run with: npm test -- --grep "timezone_utils"
 *
 * @packageVersion dreamic ^0.4.0
 *
 * ## Test Categories
 *
 * 1. **Timezone Validation** - isValidIanaTimezone
 * 2. **Offset Calculation** - getOffsetMinutesAtUtcInstant
 * 3. **Local Time Calculation** - getLocalMinutesOfDay
 * 4. **Edge Cases** - DST transitions, half-hour offsets, boundary conditions
 */

import { expect } from "chai";
import {
  isValidIanaTimezone,
  getOffsetMinutesAtUtcInstant,
  getLocalMinutesOfDay,
  getLocalHour,
  isHourInTimezone,
  localTimeToUtc,
  validateOffsetMinutes,
  formatOffset,
} from "./timezone_utils";

describe("timezone_utils", () => {
  describe("isValidIanaTimezone", () => {
    describe("valid timezones", () => {
      it("accepts standard IANA timezones", () => {
        expect(isValidIanaTimezone("America/New_York")).to.be.true;
        expect(isValidIanaTimezone("Europe/London")).to.be.true;
        expect(isValidIanaTimezone("Asia/Tokyo")).to.be.true;
        expect(isValidIanaTimezone("Australia/Sydney")).to.be.true;
      });

      it("accepts UTC", () => {
        expect(isValidIanaTimezone("UTC")).to.be.true;
      });

      it("accepts Etc/GMT offsets", () => {
        expect(isValidIanaTimezone("Etc/GMT")).to.be.true;
        expect(isValidIanaTimezone("Etc/GMT+5")).to.be.true;
        expect(isValidIanaTimezone("Etc/GMT-5")).to.be.true;
      });

      it("accepts half-hour offset timezones", () => {
        expect(isValidIanaTimezone("Asia/Kolkata")).to.be.true; // UTC+5:30
        expect(isValidIanaTimezone("Asia/Kathmandu")).to.be.true; // UTC+5:45
        expect(isValidIanaTimezone("America/St_Johns")).to.be.true; // UTC-3:30
      });

      it("accepts nested region timezones", () => {
        expect(isValidIanaTimezone("America/Indiana/Knox")).to.be.true;
        expect(isValidIanaTimezone("America/Argentina/Buenos_Aires")).to.be.true;
      });
    });

    describe("invalid timezones", () => {
      it("rejects invalid timezone strings", () => {
        expect(isValidIanaTimezone("Invalid/Zone")).to.be.false;
        expect(isValidIanaTimezone("Not/A/Real/Zone")).to.be.false;
        expect(isValidIanaTimezone("America/InvalidCity")).to.be.false;
      });

      it("rejects empty string", () => {
        expect(isValidIanaTimezone("")).to.be.false;
      });

      it("rejects null and undefined", () => {
        expect(isValidIanaTimezone(null as unknown as string)).to.be.false;
        expect(isValidIanaTimezone(undefined as unknown as string)).to.be.false;
      });

      it("rejects offset strings (not IANA format)", () => {
        expect(isValidIanaTimezone("+05:30")).to.be.false;
        expect(isValidIanaTimezone("UTC+5")).to.be.false;
        expect(isValidIanaTimezone("GMT-5")).to.be.false;
      });

      it("rejects abbreviations", () => {
        expect(isValidIanaTimezone("EST")).to.be.false;
        expect(isValidIanaTimezone("PST")).to.be.false;
        expect(isValidIanaTimezone("IST")).to.be.false;
      });
    });
  });

  describe("getOffsetMinutesAtUtcInstant", () => {
    describe("standard offsets", () => {
      it("returns correct offset for UTC", () => {
        const offset = getOffsetMinutesAtUtcInstant(
          "UTC",
          new Date("2024-01-15T12:00:00Z")
        );
        expect(offset).to.equal(0);
      });

      it("returns negative offset for US Eastern (winter)", () => {
        // January = EST = UTC-5
        const offset = getOffsetMinutesAtUtcInstant(
          "America/New_York",
          new Date("2024-01-15T12:00:00Z")
        );
        expect(offset).to.equal(-300); // -5 hours
      });

      it("returns different offset for US Eastern (summer)", () => {
        // July = EDT = UTC-4
        const offset = getOffsetMinutesAtUtcInstant(
          "America/New_York",
          new Date("2024-07-15T12:00:00Z")
        );
        expect(offset).to.equal(-240); // -4 hours
      });

      it("returns positive offset for Tokyo", () => {
        const offset = getOffsetMinutesAtUtcInstant(
          "Asia/Tokyo",
          new Date("2024-01-15T12:00:00Z")
        );
        expect(offset).to.equal(540); // +9 hours
      });
    });

    describe("half-hour and 45-minute offsets", () => {
      it("returns correct offset for India (UTC+5:30)", () => {
        const offset = getOffsetMinutesAtUtcInstant(
          "Asia/Kolkata",
          new Date("2024-01-15T12:00:00Z")
        );
        expect(offset).to.equal(330); // 5.5 hours
      });

      it("returns correct offset for Nepal (UTC+5:45)", () => {
        const offset = getOffsetMinutesAtUtcInstant(
          "Asia/Kathmandu",
          new Date("2024-01-15T12:00:00Z")
        );
        expect(offset).to.equal(345); // 5.75 hours
      });

      it("returns correct offset for Newfoundland (UTC-3:30)", () => {
        // January = NST = UTC-3:30
        const offset = getOffsetMinutesAtUtcInstant(
          "America/St_Johns",
          new Date("2024-01-15T12:00:00Z")
        );
        expect(offset).to.equal(-210); // -3.5 hours
      });
    });

    describe("extreme offsets", () => {
      it("handles UTC+14 (Line Islands)", () => {
        const offset = getOffsetMinutesAtUtcInstant(
          "Pacific/Kiritimati",
          new Date("2024-01-15T12:00:00Z")
        );
        expect(offset).to.equal(840); // +14 hours
      });

      it("handles UTC-12", () => {
        const offset = getOffsetMinutesAtUtcInstant(
          "Etc/GMT+12",
          new Date("2024-01-15T12:00:00Z")
        );
        expect(offset).to.equal(-720); // -12 hours
      });
    });

    describe("error handling", () => {
      it("throws for invalid timezone", () => {
        expect(() =>
          getOffsetMinutesAtUtcInstant(
            "Invalid/Zone",
            new Date("2024-01-15T12:00:00Z")
          )
        ).to.throw();
      });
    });
  });

  describe("getLocalMinutesOfDay", () => {
    describe("standard calculations", () => {
      it("returns 0 for midnight UTC in UTC", () => {
        const minutes = getLocalMinutesOfDay("UTC", new Date("2024-01-15T00:00:00Z"));
        expect(minutes).to.equal(0);
      });

      it("returns 540 for 9:00 AM UTC in UTC", () => {
        const minutes = getLocalMinutesOfDay("UTC", new Date("2024-01-15T09:00:00Z"));
        expect(minutes).to.equal(540); // 9 * 60
      });

      it("returns 1439 for 23:59 UTC in UTC", () => {
        const minutes = getLocalMinutesOfDay("UTC", new Date("2024-01-15T23:59:00Z"));
        expect(minutes).to.equal(1439); // 23 * 60 + 59
      });

      it("calculates local time in New York correctly", () => {
        // 2024-01-15T14:00:00Z is 9:00 AM EST (UTC-5)
        const minutes = getLocalMinutesOfDay(
          "America/New_York",
          new Date("2024-01-15T14:00:00Z")
        );
        expect(minutes).to.equal(540); // 9 * 60
      });
    });

    describe("day boundary crossing", () => {
      it("handles day rollover forward", () => {
        // 2024-01-15T23:00:00Z is 2024-01-16T08:00 in Tokyo (UTC+9)
        const minutes = getLocalMinutesOfDay(
          "Asia/Tokyo",
          new Date("2024-01-15T23:00:00Z")
        );
        expect(minutes).to.equal(480); // 8 * 60
      });

      it("handles day rollover backward", () => {
        // 2024-01-15T02:00:00Z is 2024-01-14T21:00 in New York (UTC-5)
        const minutes = getLocalMinutesOfDay(
          "America/New_York",
          new Date("2024-01-15T02:00:00Z")
        );
        expect(minutes).to.equal(1260); // 21 * 60
      });
    });

    describe("half-hour offset handling", () => {
      it("calculates correctly for India (UTC+5:30)", () => {
        // 2024-01-15T03:30:00Z is 2024-01-15T09:00 in India
        const minutes = getLocalMinutesOfDay(
          "Asia/Kolkata",
          new Date("2024-01-15T03:30:00Z")
        );
        expect(minutes).to.equal(540); // 9 * 60
      });

      it("calculates correctly for Nepal (UTC+5:45)", () => {
        // 2024-01-15T03:15:00Z is 2024-01-15T09:00 in Nepal
        const minutes = getLocalMinutesOfDay(
          "Asia/Kathmandu",
          new Date("2024-01-15T03:15:00Z")
        );
        expect(minutes).to.equal(540); // 9 * 60
      });
    });
  });

  describe("getLocalHour", () => {
    it("returns correct hour", () => {
      expect(getLocalHour("UTC", new Date("2024-01-15T09:30:00Z"))).to.equal(9);
      expect(getLocalHour("UTC", new Date("2024-01-15T23:00:00Z"))).to.equal(23);
      expect(getLocalHour("UTC", new Date("2024-01-15T00:00:00Z"))).to.equal(0);
    });

    it("handles timezone offset", () => {
      // 14:00 UTC = 9:00 AM EST
      expect(
        getLocalHour("America/New_York", new Date("2024-01-15T14:00:00Z"))
      ).to.equal(9);
    });
  });

  describe("isHourInTimezone", () => {
    it("returns true when hour matches", () => {
      expect(isHourInTimezone(9, "UTC", new Date("2024-01-15T09:30:00Z"))).to.be
        .true;
    });

    it("returns false when hour does not match", () => {
      expect(isHourInTimezone(10, "UTC", new Date("2024-01-15T09:30:00Z"))).to.be
        .false;
    });

    it("returns false for invalid hour", () => {
      expect(isHourInTimezone(-1, "UTC")).to.be.false;
      expect(isHourInTimezone(24, "UTC")).to.be.false;
      expect(isHourInTimezone(1.5, "UTC")).to.be.false;
    });

    it("returns false for invalid timezone", () => {
      expect(isHourInTimezone(9, "Invalid/Zone")).to.be.false;
    });
  });

  describe("localTimeToUtc", () => {
    it("converts local time to UTC correctly", () => {
      // 9:00 AM EST should be 14:00 UTC on Jan 15, 2024
      const utc = localTimeToUtc(9, 0, "America/New_York", new Date("2024-01-15T00:00:00Z"));
      expect(utc.getUTCHours()).to.equal(14);
      expect(utc.getUTCMinutes()).to.equal(0);
    });

    it("throws for invalid hour", () => {
      expect(() => localTimeToUtc(-1, 0, "UTC")).to.throw();
      expect(() => localTimeToUtc(24, 0, "UTC")).to.throw();
    });

    it("throws for invalid minute", () => {
      expect(() => localTimeToUtc(9, -1, "UTC")).to.throw();
      expect(() => localTimeToUtc(9, 60, "UTC")).to.throw();
    });

    it("throws for invalid timezone", () => {
      expect(() => localTimeToUtc(9, 0, "Invalid/Zone")).to.throw();
    });
  });

  describe("validateOffsetMinutes", () => {
    describe("valid offsets", () => {
      it("accepts zero (UTC)", () => {
        expect(validateOffsetMinutes(0).isValid).to.be.true;
      });

      it("accepts positive offsets", () => {
        expect(validateOffsetMinutes(330).isValid).to.be.true; // India
        expect(validateOffsetMinutes(840).isValid).to.be.true; // UTC+14
      });

      it("accepts negative offsets", () => {
        expect(validateOffsetMinutes(-300).isValid).to.be.true; // EST
        expect(validateOffsetMinutes(-720).isValid).to.be.true; // UTC-12
      });

      it("accepts boundary values", () => {
        expect(validateOffsetMinutes(840).isValid).to.be.true; // UTC+14
        expect(validateOffsetMinutes(-840).isValid).to.be.true; // UTC-14
      });
    });

    describe("invalid offsets", () => {
      it("rejects null", () => {
        const result = validateOffsetMinutes(null);
        expect(result.isValid).to.be.false;
        expect(result.error).to.exist;
      });

      it("rejects undefined", () => {
        const result = validateOffsetMinutes(undefined);
        expect(result.isValid).to.be.false;
      });

      it("rejects non-numbers", () => {
        expect(validateOffsetMinutes("300" as unknown).isValid).to.be.false;
        expect(validateOffsetMinutes({} as unknown).isValid).to.be.false;
      });

      it("rejects non-integers", () => {
        expect(validateOffsetMinutes(330.5).isValid).to.be.false;
      });

      it("rejects out-of-range values", () => {
        expect(validateOffsetMinutes(841).isValid).to.be.false; // > UTC+14
        expect(validateOffsetMinutes(-841).isValid).to.be.false; // < UTC-14
        expect(validateOffsetMinutes(1000).isValid).to.be.false;
        expect(validateOffsetMinutes(-1000).isValid).to.be.false;
      });

      it("rejects Infinity and NaN", () => {
        expect(validateOffsetMinutes(Infinity).isValid).to.be.false;
        expect(validateOffsetMinutes(-Infinity).isValid).to.be.false;
        expect(validateOffsetMinutes(NaN).isValid).to.be.false;
      });
    });
  });

  describe("formatOffset", () => {
    it("formats UTC correctly", () => {
      expect(formatOffset(0)).to.equal("UTC+0");
    });

    it("formats positive whole-hour offsets", () => {
      expect(formatOffset(540)).to.equal("UTC+9");
    });

    it("formats negative whole-hour offsets", () => {
      expect(formatOffset(-300)).to.equal("UTC-5");
    });

    it("formats half-hour offsets", () => {
      expect(formatOffset(330)).to.equal("UTC+5:30");
      expect(formatOffset(-210)).to.equal("UTC-3:30");
    });

    it("formats 45-minute offset", () => {
      expect(formatOffset(345)).to.equal("UTC+5:45");
    });

    it("formats extreme offsets", () => {
      expect(formatOffset(840)).to.equal("UTC+14");
      expect(formatOffset(-720)).to.equal("UTC-12");
    });
  });

  describe("DST Transition Edge Cases", () => {
    describe("US Spring Forward (March)", () => {
      it("handles spring forward transition", () => {
        // 2024-03-10 is DST start in US
        // At 2:00 AM local, clocks jump to 3:00 AM

        // Just before transition: 2024-03-10T06:59:00Z = 1:59 AM EST (UTC-5)
        const beforeOffset = getOffsetMinutesAtUtcInstant(
          "America/New_York",
          new Date("2024-03-10T06:59:00Z")
        );
        expect(beforeOffset).to.equal(-300); // EST

        // Just after transition: 2024-03-10T08:00:00Z = 4:00 AM EDT (UTC-4)
        const afterOffset = getOffsetMinutesAtUtcInstant(
          "America/New_York",
          new Date("2024-03-10T08:00:00Z")
        );
        expect(afterOffset).to.equal(-240); // EDT
      });
    });

    describe("US Fall Back (November)", () => {
      it("handles fall back transition", () => {
        // 2024-11-03 is DST end in US
        // At 2:00 AM local, clocks fall back to 1:00 AM

        // Just before transition: 2024-11-03T05:59:00Z = 1:59 AM EDT (UTC-4)
        const beforeOffset = getOffsetMinutesAtUtcInstant(
          "America/New_York",
          new Date("2024-11-03T05:59:00Z")
        );
        expect(beforeOffset).to.equal(-240); // EDT

        // After transition: 2024-11-03T07:00:00Z = 2:00 AM EST (UTC-5)
        const afterOffset = getOffsetMinutesAtUtcInstant(
          "America/New_York",
          new Date("2024-11-03T07:00:00Z")
        );
        expect(afterOffset).to.equal(-300); // EST
      });
    });

    describe("Timezones without DST", () => {
      it("Arizona has no DST", () => {
        const winterOffset = getOffsetMinutesAtUtcInstant(
          "America/Phoenix",
          new Date("2024-01-15T12:00:00Z")
        );
        const summerOffset = getOffsetMinutesAtUtcInstant(
          "America/Phoenix",
          new Date("2024-07-15T12:00:00Z")
        );
        expect(winterOffset).to.equal(summerOffset);
        expect(winterOffset).to.equal(-420); // UTC-7 year-round
      });

      it("India has no DST", () => {
        const winterOffset = getOffsetMinutesAtUtcInstant(
          "Asia/Kolkata",
          new Date("2024-01-15T12:00:00Z")
        );
        const summerOffset = getOffsetMinutesAtUtcInstant(
          "Asia/Kolkata",
          new Date("2024-07-15T12:00:00Z")
        );
        expect(winterOffset).to.equal(summerOffset);
        expect(winterOffset).to.equal(330); // UTC+5:30 year-round
      });
    });
  });
});
