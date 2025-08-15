vim9script

import "./backend.vim"

# Example: Get current date's calendar
var yy = str2nr(strftime('%Y'))
var mm = str2nr(strftime('%m'))
var dd = str2nr(strftime('%d'))
var Ww = str2nr(strftime('%W'))

def DisplaySingleCal(year: number, month: number, start_on_sunday: bool, inc_week: bool): list<list<number>>
  # Identify today
  var is_today_year_month = strftime('%Y') == printf('%04d', year)
      && strftime('%m') == printf('%02d', month)

  # TODO
  const five_days = false

  # Fix head
  var month_str = backend.month_n2_to_str[printf('%02d', month)]
  var padding = max([0, 18 - len(month_str)]) / 2
  var year_month = $"{repeat(' ', padding)}{month_str} {year}"
  appendbufline('%', line('$'), $"{year_month}")
  matchadd('WarningMsg', year_month)

  # Fix weekdays
  var weekdays = start_on_sunday
    ? 'Su Mo Tu We Th Fr Sa'
    : 'Mo Tu We Th Fr Sa Su'

  padding = inc_week ? 4 : 1
  appendbufline('%', line('$'), $" {weekdays}")
  matchadd('StatusLine', weekdays)

  # Actual days
  var cal = start_on_sunday
    ? backend.ConvertISOtoUS(backend.CalendarMonth_iso8601(year, month, inc_week), month)
    : backend.CalendarMonth_iso8601(year, month, inc_week)

  # For the highlight
  const col_Sa = start_on_sunday ? 20 : 17
  const col_Su = start_on_sunday ? 2 : 20

  # Build the calendar
  for line in cal
    var firstline = line('$')
    var line_cleaned: string =
      line->mapnew((_, val) => printf('%02d', val))
    ->map((_, val) => substitute(val, '00', '  ', 'g'))
    ->map((_, val) => substitute(val, '^0', ' ', 'g'))
    ->map((_, val) => substitute(val, ',', ' ', 'g'))
    ->join()
    appendbufline('%', firstline, $" {line_cleaned}")

    if !five_days
      # Higlight Saturdays
      range(firstline + 1, line('$'))
        ->map((_, val) => matchaddpos('Special', [[val, col_Sa, 2]]))

      # Highlight Sundays
      range(firstline + 1, line('$'))
        ->map((_, val) => matchaddpos('Error', [[val, col_Su, 2]]))
    endif

    if inc_week
      # Highlight week
      range(firstline + 1, line('$'))
        ->map((_, val) => matchaddpos('CursorLineNr', [[val, 23, 2]]))
    endif

    # Highlight today
    if is_today_year_month
      const today = strftime('%d')
      var line_span = range(firstline + 1, line('$'))
        ->map((_, val) => $'\%{val}l')->join('\|')
      matchadd('DiffAdd', $'{line_span}\zs{today}')
    endif
  endfor
  return cal
enddef

def DisplayMultipleCal(
    year: number,
    month: number,
    start_on_sunday: bool = true,
    inc_week: bool = false,
    N: number = 3)
  vnew
  for ii in range(N)
    DisplaySingleCal(year, month - 1 + ii, start_on_sunday, inc_week)
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

var XXX  = 2025
vnew
DisplaySingleCal(XXX, 8, false, true)
DisplaySingleCal(XXX, 8, true, true)
