vim9script

# Functions for backend computations, like Zeller's congruence formula,
# computation of calendar of a given month/year, etc

export const month_n2_to_str = {
  01: "January",
  02: "February",
  03: "March",
  04: "April",
  05: "May",
  06: "June",
  07: "July",
  08: "August",
  09: "September",
  10: "October",
  11: "November",
  12: "December",
}

# Number of days in a given month
def DaysInMonth(year: number, month: number): number
    if month == 2
        # Leap year check
        if (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
            return 29
        endif
        return 28
    endif
    if index([1, 3, 5, 7, 8, 10, 12], month) != -1
        return 31
    endif
    return 30
enddef

# Build calendar for a given date
# Returns weekday of a date (0=Monday, 6=Sunday)
def WeekdayOfDate(year: number, month: number, day: number): number
    # Implement modified Zeller's congruence
    # Zeller's h: 0=Saturday, ..., 6=Friday
    var month_adj = month
    var year_adj = year
    if month_adj < 3
        month_adj += 12
        year_adj -= 1
    endif
    var h = (day + (13 * (month_adj + 1)) / 5 + year_adj + (year_adj / 4) - (year_adj / 100) + (year_adj / 400)) % 7
    # Convert to Monday=0 ... Sunday=6
    return (h + 5) % 7
enddef

# TODO: if 1st January is in the last week of December, then it shall be set
# to w1. However, we cannot distinguish the month as we just pass a calendar
# Convert ISO (Monday-start) calendar to US (Sunday-start) calendar
export def ConvertISOtoUS(iso_calendar: list<list<number>>, month: number): list<list<number>>
    var us_calendar: list<list<number>> = []
    var carry_sunday = 0
    var carry_week = 0  # ISO week of carried Sunday
    var iso_week_present = len(iso_calendar[0]) == 8 ? true : false

    for week in iso_calendar
        var new_week = week[0 : 6]
        var iso_week = iso_week_present ? week[7] : -1
        var sunday = new_week[6]

        # Prepend carryover Sunday at start
        insert(new_week, carry_sunday, 0)
        remove(new_week, 7)

        # Determine US week number
        if iso_week_present
          var us_week = iso_week
          add(new_week, us_week)
          carry_week = iso_week
        endif

        add(us_calendar, new_week)

        # Carry Sunday to next row
        carry_sunday = sunday
    endfor

    # Add last row if a Sunday remains
    if carry_sunday != 0
      var last_week = iso_week_present
        ?  [carry_sunday, 0, 0, 0, 0, 0, 0, carry_week + 1]
        :  [carry_sunday, 0, 0, 0, 0, 0, 0]
      add(us_calendar, last_week)
    endif

    # Remove first row if all zeros
    if count(us_calendar[0][0 : 6], 0) == 7
        remove(us_calendar, 0)
    endif

    # TODO: check it better
    # If 1st of January falls in the last week of the year, then it become the
    # first week of the year
    # if month == 12 && us_calendar[-1][-2] != 31
    #   us_calendar[-1][-1] = 1
    # endif

    return us_calendar
enddef

# Compute ISO 8601 week number for a given date
def ISOWeekNumber(year: number, month: number, day: number): number
    var wd = WeekdayOfDate(year, month, day)

    # Day-of-year
    var dim = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
        dim[1] = 29
    endif
    var doy = day
    for i in range(0, month - 1)
        if i > 0
            doy += dim[i - 1]
        endif
    endfor

    # Thursday of the week
    var doy_thu = doy + (3 - wd)

    # Days in year
    var days_in_year = 365
    if (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
        days_in_year = 366
    endif

    # Determine ISO year
    var iso_year = year
    if doy_thu < 1
        iso_year -= 1
        if (iso_year % 4 == 0 && iso_year % 100 != 0) || (iso_year % 400 == 0)
            doy_thu += 366
        else
            doy_thu += 365
        endif
    elseif doy_thu > days_in_year
        iso_year += 1
        doy_thu -= days_in_year
    endif

    # Week 1 start: Monday of the week containing Jan 4
    var jan4_wd = WeekdayOfDate(iso_year, 1, 4)
    var week1_start = 4 - jan4_wd

    # ISO week number
    return float2nr(1 + floor((doy_thu - week1_start - 1) / 7))
enddef

# Generate calendar with optional ISO week numbers at the end, 0=Monday
export def CalendarMonth_iso8601(
    year: number,
    month: number,
    add_weeknum: bool = false): list<list<number>>

    var month_days = DaysInMonth(year, month)
    var first_wday = WeekdayOfDate(year, month, 1)  # weekday 0=Mon

    var weeks: list<list<number>> = []
    var week: list<number> = []

    # Get ISO week number of the first day of the month
    var week_num = ISOWeekNumber(year, month, 1)


    # Fill first week with blanks before day 1
    for _ in range(first_wday)
        week->add(0)
    endfor

    # Fill days
    for d in range(1, month_days)
        week->add(d)
        if week->len() == 7
            if add_weeknum
                week->add(week_num)
            endif
            weeks->add(week)
            week = []
            # If the first week of January is the same as the previous year,
            # then reset the week number
            week_num = month == 1 && (week_num == 52 || week_num == 53)
              ? 1
              : week_num + 1
        endif
    endfor

    # Fill trailing blanks
    if !empty(week)
        while week->len() < 7
            week->add(0)
        endwhile
        if add_weeknum
            week->add(week_num)
        endif
        weeks->add(week)
    endif

    return weeks
enddef
