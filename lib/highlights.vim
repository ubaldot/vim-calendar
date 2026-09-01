vim9script

# Calendar highlight group definitions and match management.
# Shared state is read from t:cal_* (tab-local).

# Remove only matches owned by vim-calendar from the target window.
def ClearCalendarMatches(win_id: number)
  for match in getmatches(win_id)
    if get(match, 'group', '') =~# '^Cal'
      matchdelete(match.id, win_id)
    endif
  endfor
enddef

# Highlight today's column in the __WeekHeader__ window.
# today_week_key: the Monday date string for today's ISO week (caller computes
# it to avoid importing backend here). Only highlights when today is in the
# displayed week (t:cal_week_key).
export def WeekHeader(win_id: number, today_week_key: string)
  ClearCalendarMatches(win_id)
  if today_week_key !=# get(t:, 'cal_week_key', '')
    return
  endif
  var today_d = str2nr(strftime('%d'))
  matchadd('CalWeekToday', $' {today_d},[^│]*', 10, -1, {window: win_id})
enddef

# Update only the CalCurrWeek match in the current window (the week-number
# column highlight that follows navigation).  Removes the old match by ID,
# then searches for the current week number and re-adds it.
export def UpdateCurrWeek()
  try | matchdelete(get(w:, 'cal_curr_week', -1)) | catch | endtry
  var curr_week_num = get(t:, 'cal_curr_week_num', 0)
  if curr_week_num == 0
    return
  endif
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
# Clears calendar-owned matches first, then adds today/sat/sun/holiday/week
# marks and static patterns (help hint, header, diary list, weekday row).
export def Apply(view: dict<any>, week_num_enabled: bool)
  ClearCalendarMatches(win_getid())

  if !empty(view.today) | matchaddpos('CalToday', view.today, 40) | endif
  if !empty(view.sat) | matchaddpos('CalSaturday', view.sat, 30) | endif
  if !empty(view.sun) | matchaddpos('CalSunday', view.sun, 30) | endif
  if !empty(view.holiday) | matchaddpos('CalHoliday', view.holiday, 32) | endif
  if !empty(view.week) | matchaddpos('CalWeeknm', view.week, 35) | endif
  if week_num_enabled
    UpdateCurrWeek()
  endif

  matchadd('CalHelpHint', '^Hit "?" for help$', 20)
  matchadd('CalHeader', '^\s*[A-Za-z]\+\s\+\d\{4}$', 25)
  matchadd('CalCurrList', '^(\*).*$', 15)
  matchadd('CalWeekdays', '^\s*\%(WK\s\+\)\?\%(Mo\|Tu\|We\|Th\|Fr\|Sa\|Su\)\%( \%(Mo\|Tu\|We\|Th\|Fr\|Sa\|Su\)\)\+\s*$', 22)
enddef

def DefineTodayHighlight()
  if !empty(hlget('CalToday'))
    return
  endif
  var visual = hlget('Visual', true)
  if empty(visual)
    highlight default CalToday term=bold cterm=bold gui=bold
    return
  endif

  var today = visual[0]
  remove(today, 'id')
  today.name = 'CalToday'
  for mode in ['term', 'cterm', 'gui']
    var attributes = get(today, mode, {})
    attributes.bold = true
    today[mode] = attributes
  endfor
  hlset([today])
enddef

hi def link CalSaturday LineNr
hi def link CalSunday Error
hi def link CalRuler Normal
hi def link CalWeekdays WarningMsg
hi def link CalWeeknm Visual
DefineTodayHighlight()
hi def link CalHeader WarningMsg
hi def link CalHoliday Error
hi def link CalCurrList Error
hi def link CalHelpHint Question
hi def link CalCurrWeek Visual
hi def CalWeekToday term=bold cterm=bold gui=bold

# vim: shiftwidth=2 softtabstop=2 noexpandtab
