// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library DateTime {
        uint constant DAY_IN_SECONDS = 86400;
        uint constant YEAR_IN_SECONDS = 31536000;
        uint constant LEAP_YEAR_IN_SECONDS = 31622400;

        uint constant HOUR_IN_SECONDS = 3600;
        uint constant MINUTE_IN_SECONDS = 60;

        uint16 constant ORIGIN_YEAR = 1970;
        uint constant leapYearsBefore_ORIGIN_YEAR = (ORIGIN_YEAR - 1) / 4 - (ORIGIN_YEAR - 1) / 100 + (ORIGIN_YEAR - 1) / 400;

    function getMonthName(uint8 month) public pure returns (string memory monthName) {
        if (month == 1) monthName = "Jan";
        if (month == 2) monthName = "Feb";
        if (month == 3) monthName = "Mar";
        if (month == 4) monthName = "Apr";
        if (month == 5) monthName = "May";
        if (month == 6) monthName = "Jun";
        if (month == 7) monthName = "Jul";
        if (month == 8) monthName = "Aug";
        if (month == 9) monthName = "Sep";
        if (month == 10) monthName = "Oct";
        if (month == 11) monthName = "Nov";
        if (month == 12) monthName = "Dec";
    }

        function isLeapYear(uint16 year) public pure returns (bool) {
                if (year % 4 != 0) {
                        return false;
                }
                if (year % 100 != 0) {
                        return true;
                }
                if (year % 400 != 0) {
                        return false;
                }
                return true;
        }

        function leapYearsBefore(uint year) public pure returns (uint) {
                year -= 1;
                return year / 4 - year / 100 + year / 400;
        }

        function getDaysInMonth(uint8 month, bool isLeap) public pure returns (uint8) {
                if (month == 1 || month == 3 || month == 5 || month == 7 || month == 8 || month == 10 || month == 12) {
                        return 31;
                }
                else if (month == 4 || month == 6 || month == 9 || month == 11) {
                        return 30;
                }
                else if (isLeap) {
                        return 29;
                }
                else {
                        return 28;
                }
        }

        function parseTimestamp(uint timestamp) internal pure returns (uint8 day, uint8 month, uint16 year, uint8 hour, uint8 minute) {
                uint secondsAccountedFor = 0;
                uint buf;
                uint8 i;

                // Year
                year = getYear(timestamp);
                bool isLeap = isLeapYear(year);
                buf = leapYearsBefore(year) - leapYearsBefore_ORIGIN_YEAR;

                secondsAccountedFor += LEAP_YEAR_IN_SECONDS * buf;
                secondsAccountedFor += YEAR_IN_SECONDS * (year - ORIGIN_YEAR - buf);

                // Month
                uint secondsInMonth;
                for (i = 1; i <= 12; i++) {
                        secondsInMonth = DAY_IN_SECONDS * getDaysInMonth(i, isLeap);
                        if (secondsInMonth + secondsAccountedFor > timestamp) {
                                month = i;
                                break;
                        }
                        secondsAccountedFor += secondsInMonth;
                }

                // Day
                for (i = 1; i <= getDaysInMonth(month, isLeap); i++) {
                        if (DAY_IN_SECONDS + secondsAccountedFor > timestamp) {
                                day = i;
                                break;
                        }
                        secondsAccountedFor += DAY_IN_SECONDS;
                }

                // Hour
                hour = getHour(timestamp);

                // Minute
                minute = getMinute(timestamp);
        }

        function getYear(uint timestamp) public pure returns (uint16) {
                uint secondsAccountedFor = 0;
                uint16 year;
                uint numLeapYears;

                // Year
                year = uint16(ORIGIN_YEAR + timestamp / YEAR_IN_SECONDS);
                numLeapYears = leapYearsBefore(year) - leapYearsBefore_ORIGIN_YEAR;

                secondsAccountedFor += LEAP_YEAR_IN_SECONDS * numLeapYears;
                secondsAccountedFor += YEAR_IN_SECONDS * (year - ORIGIN_YEAR - numLeapYears);

                while (secondsAccountedFor > timestamp) {
                        if (isLeapYear(uint16(year - 1))) {
                                secondsAccountedFor -= LEAP_YEAR_IN_SECONDS;
                        }
                        else {
                                secondsAccountedFor -= YEAR_IN_SECONDS;
                        }
                        year -= 1;
                }
                return year;
        }

        function getHour(uint timestamp) public pure returns (uint8) {
                return uint8((timestamp / 60 / 60) % 24);
        }

        function getMinute(uint timestamp) public pure returns (uint8) {
                return uint8((timestamp / 60) % 60);
        }
}