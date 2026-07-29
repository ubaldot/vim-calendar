vim9script

# Calendar highlight group definitions and match management.
# All functions operate on the current window (split mode) or a given winid
# (popup mode). No imports needed — callers pass the few pieces of state
# required (curr_week_num, week_num_enabled).

# Update only the CalCurrWeek match in the current window.
export def UpdateCurrWeek(curr_week_num: number)
  if exists('w:cal_curr_week') | silent! matchdelete(w:cal_curr_week) | endif
  var save_pos = getcurpos()
  if search($'^\s*{curr_week_num}\s', 'cw') > 0
    normal! 0w
    var start_pos = getcurpos()
    w:cal_curr_week = matchaddpos('CalCurrWeek',
      [[start_pos[1], start_pos[2], col('$') - start_pos[2]]], 25)
  endif
  setpos('.', save_pos)
enddef

# Apply all calendar match highlights to the current (split) window.
export def Apply(view: dict<any>, curr_week_num: number, week_num_enabled: bool)
  if exists('w:cal_today') | silent! matchdelete(w:cal_today) | endif
  if exists('w:cal_sat') | silent! matchdelete(w:cal_sat) | endif
  if exists('w:cal_sun') | silent! matchdelete(w:cal_sun) | endif
  if exists('w:cal_holiday') | silent! matchdelete(w:cal_holiday) | endif
  if exists('w:cal_week') | silent! matchdelete(w:cal_week) | endif
  if exists('w:cal_curr_week') | silent! matchdelete(w:cal_curr_week) | endif
  if exists('w:cal_weekdays') | silent! matchdelete(w:cal_weekdays) | endif
  if exists('w:cal_help') | silent! matchdelete(w:cal_help) | endif
  if exists('w:cal_header') | silent! matchdelete(w:cal_header) | endif
  if exists('w:cal_currlist') | silent! matchdelete(w:cal_currlist) | endif

  if !empty(view.today) | w:cal_today = matchaddpos('CalToday', view.today, 40) | endif
  if !empty(view.sat) | w:cal_sat = matchaddpos('CalSaturday', view.sat, 30) | endif
  if !empty(view.sun) | w:cal_sun = matchaddpos('CalSunday', view.sun, 30) | endif
  if !empty(view.holiday) | w:cal_holiday = matchaddpos('CalHoliday', view.holiday, 32) | endif
  if !empty(view.week) | w:cal_week = matchaddpos('CalWeeknm', view.week, 35) | endif
  if week_num_enabled
    UpdateCurrWeek(curr_week_num)
  endif

  w:cal_help = matchadd('CalHelpHint', '^Hit "?" for help$', 20)
  w:cal_header = matchadd('CalHeader', '^\s*[A-Za-z]\+\s\+\d\{4}$', 25)
  w:cal_currlist = matchadd('CalCurrList', '^(\*).*$', 15)
  w:cal_weekdays = matchadd('CalWeekdays', '^\s*\%(WK\s\+\)\?\%(Mo\|Tu\|We\|Th\|Fr\|Sa\|Su\)\%( \%(Mo\|Tu\|We\|Th\|Fr\|Sa\|Su\)\)\+\s*$', 22)
enddef

# Apply all calendar match highlights to a popup window.
export def ApplyPopup(winid: number, view: dict<any>, week_num_enabled: bool)
  if winid <= 0
    return
  endif
  if !empty(view.today)
    win_execute(winid, $"call matchaddpos('CalToday', {string(view.today)}, 40)")
  endif
  if !empty(view.sat)
    win_execute(winid, $"call matchaddpos('CalSaturday', {string(view.sat)}, 30)")
  endif
  if !empty(view.sun)
    win_execute(winid, $"call matchaddpos('CalSunday', {string(view.sun)}, 30)")
  endif
  if !empty(view.holiday)
    win_execute(winid, $"call matchaddpos('CalHoliday', {string(view.holiday)}, 32)")
  endif
  if !empty(view.week)
    win_execute(winid, $"call matchaddpos('CalWeeknm', {string(view.week)}, 35)")
  endif
  if week_num_enabled
    var wn = str2nr(strftime('%V'))
    win_execute(winid, [
      $"if search('^\\s*{wn}\\s', 'cw') > 0",
      "  normal! 0w",
      $"  call matchaddpos('CalCurrWeek', [[line('.'), col('.'), col('$') - col('.')]], 25)",
      "endif"
    ])
  endif
  win_execute(winid, 'call matchadd(''CalHelpHint'', ''^Hit "?" for help$'', 20)')
  win_execute(winid, 'call matchadd(''CalHeader'', ''^\s*[A-Za-z]\+\s\+\d\{4}$'', 25)')
  win_execute(winid, 'call matchadd(''CalCurrList'', ''^(\*).*$'', 15)')
  win_execute(winid, 'call matchadd(''CalWeekdays'', ''^\s*\%(WK\s\+\)\?\%(Mo\|Tu\|We\|Th\|Fr\|Sa\|Su\)\%( \%(Mo\|Tu\|We\|Th\|Fr\|Sa\|Su\)\)\+\s*$'', 22)')
enddef

hi def link CalSaturday LineNr
hi def link CalSunday Error
hi def link CalRuler Normal
hi def link CalWeekdays WarningMsg
hi def link CalWeeknm Visual
hi def link CalToday Visual
hi def link CalHeader WarningMsg
hi def link CalHoliday Error
hi def link CalCurrList Error
hi def link CalHelpHint Question
hi def link CalPopupSelection Visual
hi def link CalCurrWeek Visual
hi def link CalWeekToday Visual

# vim: shiftwidth=2 softtabstop=2 noexpandtab
