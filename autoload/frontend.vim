vim9script

import autoload "./backend.vim"

# Example: Get current date's calendar
var yy = str2nr(strftime('%Y'))
var mm = str2nr(strftime('%m'))
var dd = str2nr(strftime('%d'))
var Ww = str2nr(strftime('%W'))

# def CalendarPopup(calendar: any)
#    var popup_id = popup_create(calendar, {
#         title: " Calendar ",
#         line: 1,
#         col: 1,
#         pos: "topleft",
#         posinvert: false,
#         filter: HelpMeFilter,
#         borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
#         border: [1, 1, 1, 1],
#         maxheight: &lines - 1,
#         mapping: 0,
#         })
# enddef

# def HelpMeFilter(id: number, key: string): bool
#   # To handle the keys when release notes popup is visible
#   # Close
#   if key ==# 'q' || key ==# "\<esc>"
#     popup_close(id)
#   # Move down
#   elseif ["\<tab>", "\<C-n>", "\<Down>", "\<ScrollWheelDown>"]->index(key) != -1
#     win_execute(id, "normal! \<c-e>")
#   # Move up
#   elseif ["\<S-Tab>", "\<C-p>", "\<Up>", "\<ScrollWheelUp>"]->index(key) != -1
#     win_execute(id, "normal! \<c-y>")
#   # Jump down
#   elseif key == "\<C-f>"
#     win_execute(id, "normal! \<c-f>")
#   # Jump up
#   elseif key == "\<C-b>"
#     win_execute(id, "normal! \<c-b>")
#   else
#     return false
#   endif
#   return true
# enddef

# cal_type 0 = iso, 1 = us, 2 = work days
def DisplaySingleCal(year: number, month: number, cal_type: number, inc_week: bool): dict<list<list<number>>>
  # Identify today, check if it is visible
  var is_today_year_month = strftime('%Y') == printf('%04d', year)
      && strftime('%m') == printf('%02d', month)

  # Switch options
  var weekdays = ''
  var calendar: dict<list<list<number>>>
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
      backend.CalendarMonth_iso8601(year, month, inc_week)
    )
    col_Sat = 20
    col_Sun = 2
  elseif cal_type == 2
    weekdays =  'Mo Tu We Th Fr'
    const [calendar_key, calendar_values] = items(backend.CalendarMonth_iso8601(year, month, inc_week))[0]
    const calendar_values_short_week = calendar_values
      ->mapnew((_, val) => add(val[0 : 4], val[7]))
      ->filter((_, val) => val[0 : 4] != [0, 0, 0, 0, 0] )
    calendar = {[calendar_key]: calendar_values_short_week}
    col_Sat = -1
    col_Sun = -1
  else
    echoerr "[vim-calendar]: 'cal_type' shall be 0, 1 or 2"
  endif

  # Fix head
  var month_year_str = keys(calendar)[0]
  var padding = cal_type == 2
    ? max([2, 13 - len(month_year_str)])
    : max([5, 15 - len(month_year_str)])
  var year_month = $"{repeat(' ', padding)}{month_year_str}"
  appendbufline('%', line('$'), $"{year_month}")
  matchadd('WarningMsg', year_month)

  # Fix weekdays
  padding = inc_week ? 4 : 1
  appendbufline('%', line('$'), $" {weekdays}")
  matchadd('StatusLine', weekdays)


  # Build the calendar values
  for line in values(calendar)[0]
    var firstline = line('$')
    var line_cleaned: string =
      line->mapnew((_, val) => printf('%02d', val))
    ->map((_, val) => substitute(val, '00', '  ', 'g'))
    ->map((_, val) => substitute(val, '^0', ' ', 'g'))
    ->map((_, val) => substitute(val, ',', ' ', 'g'))
    ->join()
    appendbufline('%', firstline, $" {line_cleaned}")


    # Highligh
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
  var lines = getline(1, '$')
  # close
  #   # TODO: remove me
  #   CalendarPopup(lines)
enddef

# ===================== TESTS =================================
# Expected results are for January of different years
const expected_results = [
  {'January 2005': [0, 0, 0, 0, 0, 1, 2, 53]},
  {'January 2006': [0, 0, 0, 0, 0, 0, 1, 52]},
  {'January 2010': [0, 0, 0, 0, 1, 2, 3, 53]},
  {'January 2015': [0, 0, 0, 1, 2, 3, 4, 1]},
  {'January 2016': [0, 0, 0, 0, 1, 2, 3, 53]},
  {'January 2018': [1, 2, 3, 4, 5, 6, 7, 1]},
  {'January 2021': [0, 0, 0, 0, 1, 2, 3, 53]},
  {'January 2022': [0, 0, 0, 0, 0, 1, 2, 52]},
  {'January 2024': [1, 2, 3, 4, 5, 6, 7, 1]}
]
const test_years = [2005, 2006, 2010, 2015, 2016, 2018, 2021, 2022, 2024]
var ii = 0
for yyy in test_years
  var [calendar_key, calendar_values] = items(backend.CalendarMonth_iso8601(yyy, 1, true))[0]
  var actual_result = {['January ' .. yyy]: calendar_values[0]}
  echom assert_equal(expected_results[ii], actual_result)
  ii += 1
endfor

# Start on Sunday
const expected_us_results = [
  {'January 2005': [0, 0, 0, 0, 0, 0, 1, 53]},  # Jan 1 is Saturday → week 53 prev. year
  {'January 2006': [1, 2, 3, 4, 5, 6, 7, 1]},   # Jan 1 is Sunday → week 1
  {'January 2010': [0, 0, 0, 0, 0, 1, 2, 53]},   # first Sunday Jan 3
  {'January 2015': [0, 0, 0, 0, 1, 2, 3, 1]},   # first Sunday Jan 4
  {'January 2016': [0, 0, 0, 0, 0, 1, 2, 53]},   # first Sunday Jan 3
  {'January 2018': [0, 1, 2, 3, 4, 5, 6, 1]},   # first Sunday Jan 7
  {'January 2021': [0, 0, 0, 0, 0, 1, 2, 53]},   # first Sunday Jan 3
  {'January 2022': [0, 0, 0, 0, 0, 0, 1, 52]},   # first Sunday Jan 2
  {'January 2024': [0, 1, 2, 3, 4, 5, 6, 1]}    # first Sunday Jan 7
]
ii = 0
messages clear
for yyy in test_years
  var [calendar_key, calendar_values] = items(backend.ConvertISOtoUS(backend.CalendarMonth_iso8601(yyy, 1, true)))[0]
  var actual_result = {['January ' .. yyy]: calendar_values[0]}
  echom assert_equal(expected_us_results[ii], actual_result)
  ii += 1
endfor
var Y  = 2025
var M = 11
var CAL_TYPE = 2
DisplayMultipleCal(Y, M, CAL_TYPE, true)
# vnew
# DisplaySingleCal(Y, M, 0, true)
# DisplaySingleCal(Y, M, 1, true)
# DisplaySingleCal(Y, M, 2, true)
