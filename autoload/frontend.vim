vim9script

import autoload "./backend.vim"

# Example: Get current date's calendar
var yy = str2nr(strftime('%Y'))
var mm = str2nr(strftime('%m'))
var dd = str2nr(strftime('%d'))
var Ww = str2nr(strftime('%W'))

# cal_type 0 = iso, 1 = us, 2 = work days
def DisplaySingleCal(year: number, month: number, cal_type: number, inc_week: bool): list<list<number>>
  # Identify today, check if it is visible
  var is_today_year_month = strftime('%Y') == printf('%04d', year)
      && strftime('%m') == printf('%02d', month)

  # Switch options
  var weekdays = ''
  var calendar: list<list<number>>
  # For highlighting Saturday and Sunday
  var col_Sat = -1
  var col_Sun = -1

  if cal_type == 0
    weekdays = 'Mo Tu We Th Fr Sa Su'
    calendar = backend.CalendarMonth_iso8601(year, month, inc_week)
    col_Sat = 17
    col_Sun = 20
  elseif cal_type == 1
    weekdays =  'Su Mo Tu We Th Fr Sa'
    calendar = backend.ConvertISOtoUS(
      backend.CalendarMonth_iso8601(year, month, inc_week), month
    )
    col_Sat = 20
    col_Sun = 2
  elseif cal_type == 2
    weekdays =  'Mo Tu We Th Fr'
    calendar = backend.CalendarMonth_iso8601(year, month, inc_week)
      ->mapnew((_, val) => add(val[0 : 4], val[7]))
      ->filter((_, val) => val[0 : 4] != [0, 0, 0, 0, 0] )
    col_Sat = -1
    col_Sun = -1
  else
    echoerr "[vim-calendar]: 'cal_type' shall be 0, 1 or 2"
  endif

  # Fix head
  var month_str = backend.month_n2_to_str[printf('%02d', month)]
  var padding = max([0, 18 - len(month_str)]) / 2 - 2 * cal_type
  var year_month = $"{repeat(' ', padding)}{month_str} {year}"
  appendbufline('%', line('$'), $"{year_month}")
  matchadd('WarningMsg', year_month)

  # Fix weekdays
  padding = inc_week ? 4 : 1
  appendbufline('%', line('$'), $" {weekdays}")
  matchadd('StatusLine', weekdays)


  # Build the calendar
  for line in calendar
    var firstline = line('$')
    var line_cleaned: string =
      line->mapnew((_, val) => printf('%02d', val))
    ->map((_, val) => substitute(val, '00', '  ', 'g'))
    ->map((_, val) => substitute(val, '^0', ' ', 'g'))
    ->map((_, val) => substitute(val, ',', ' ', 'g'))
    ->join()
    appendbufline('%', firstline, $" {line_cleaned}")

    if cal_type != 2
      # Higlight Saturdays
      range(firstline + 1, line('$'))
        ->map((_, val) => matchaddpos('Special', [[val, col_Sat, 2]]))

      # Highlight Sundays
      range(firstline + 1, line('$'))
        ->map((_, val) => matchaddpos('Error', [[val, col_Sun, 2]]))
    endif

    # Highlight week
    if inc_week
      var col_Week = cal_type == 2 ? 17 : 23
      range(firstline + 1, line('$'))
        ->map((_, val) => matchaddpos('CursorLineNr', [[val, col_Week, 2]]))
    endif

    # Highlight today
    if is_today_year_month
      const today = strftime('%d')
      var line_span = range(firstline + 1, line('$'))
        ->map((_, val) => $'\%{val}l')->join('\|')
      matchadd('DiffAdd', $'{line_span}\zs{today}')
    endif
  endfor
  return calendar
enddef

def DisplayMultipleCal(
    year: number,
    month: number,
    cal_type: number = 0,
    inc_week: bool = false,
    N: number = 3)
  vnew
  for ii in range(N)
    if ii == 0 && month == 1
      DisplaySingleCal(year - 1, 12, cal_type, inc_week)
    else
      DisplaySingleCal(year, month - 1 + ii, cal_type, inc_week)
    endif
    appendbufline('%', line('$'), '')
  endfor
enddef

# ===================== TESTS =================================
# Expected results are for January of different years
const expected_results = {
  '2005': [0, 0, 0, 0, 0, 1, 2, 53],
  '2006': [0, 0, 0, 0, 0, 0, 1, 52],
  '2010': [0, 0, 0, 0, 1, 2, 3, 53],
  '2015': [0, 0, 0, 1, 2, 3, 4, 1],
  '2016': [0, 0, 0, 0, 1, 2, 3, 53],
  '2018': [1, 2, 3, 4, 5, 6, 7, 1],
  '2021': [0, 0, 0, 0, 1, 2, 3, 53],
  '2022': [0, 0, 0, 0, 0, 1, 2, 52],
  '2024': [1, 2, 3, 4, 5, 6, 7, 1]
}
var actual_results = {}
var current_result = {}
const test_years = [2005, 2006, 2010, 2015, 2016, 2018, 2021, 2022, 2024]
for yyy in test_years
  var cal = backend.CalendarMonth_iso8601(yyy, 1, true)
  current_result = {[yyy]: cal[0]}
  extend(actual_results, current_result)
endfor
# echom assert_equal(expected_results, actual_results)

# Start on Sunday
const expected_us_results = {
  '2005': [0, 0, 0, 0, 0, 0, 1, 53],  # Jan 1 is Saturday → week 53 prev. year
  '2006': [1, 2, 3, 4, 5, 6, 7, 1],   # Jan 1 is Sunday → week 1
  '2010': [0, 0, 0, 0, 0, 1, 2, 53],   # first Sunday Jan 3
  '2015': [0, 0, 0, 0, 1, 2, 3, 1],   # first Sunday Jan 4
  '2016': [0, 0, 0, 0, 0, 1, 2, 53],   # first Sunday Jan 3
  '2018': [0, 1, 2, 3, 4, 5, 6, 1],   # first Sunday Jan 7
  '2021': [0, 0, 0, 0, 0, 1, 2, 53],   # first Sunday Jan 3
  '2022': [0, 0, 0, 0, 0, 0, 1, 52],   # first Sunday Jan 2
  '2024': [0, 1, 2, 3, 4, 5, 6, 1]    # first Sunday Jan 7
}

actual_results = {}
current_result = {}
for yyy in test_years
  var cal = backend.ConvertISOtoUS(backend.CalendarMonth_iso8601(yyy, 1, true), 1)
  current_result = {[yyy]: cal[0]}
  extend(actual_results, current_result)
endfor
# echom assert_equal(expected_us_results, actual_results)

var Y  = 2025
var M = 1
var CAL_TYPE = 0
DisplayMultipleCal(Y, M, CAL_TYPE, true)
# vnew
# DisplaySingleCal(XXX, 8, false, true)
# DisplaySingleCal(XXX, 8, true, true)
