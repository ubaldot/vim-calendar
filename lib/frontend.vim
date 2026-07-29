vim9script

import autoload "./backend.vim"

const cal_bufname    = '__Calendar'
const WEEK_BUF_NAME  = '__WeekView__'
const WEEK_TIME_COL  = 8
const WEEK_DAY_COL   = 16
const WEEK_DAY_FULL  = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

const weekdays: dict<list<string>> = {
  us: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'],
  eu: ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'],
  work: ['Mo', 'Tu', 'We', 'Th', 'Fr'],
}
const month_num_to_string = backend.month_num_to_str

var cfg_position = 'left'
var cfg_cal_type = 'eu'
var cfg_show_week_number = false
var cfg_number_of_months = 3
var cfg_holidays: dict<any> = {}
var cfg_search_grep = 'internal'
var cfg_diaries: dict<any> = {My_Diary: {path: '~/my_diary', resolution: 'month'}}
var cfg_active_diary = 'My_Diary'
var cfg_diary_path = '~/my_diary'
var cfg_auto_create_diary_dirs = false
var cfg_action = 'OpenDiaryPage'
var cfg_appointments_path = ''
var popup_id = -1
var help_popup_id = -1
var popup_year = 0
var popup_month = 0
var popup_day_cells: list<dict<any>> = []
var popup_day_index = -1
var state_base_year = 0
var state_base_month = 0
var state_blocks: list<dict<any>> = []
var state_diary_rows: dict<string> = {}
var week_view_winid = -1

# Normalize window placement to supported values.
def NormalizePos(v: any): string
  var pos = type(v) == v:t_string ? tolower(v) : 'left'
  return index(['left', 'right', 'popup'], pos) >= 0 ? pos : 'left'
enddef

# Normalize calendar type to supported values.
def NormalizeCalType(v: any): string
  var t = type(v) == v:t_string ? tolower(v) : 'eu'
  return index(['eu', 'us', 'work'], t) >= 0 ? t : 'eu'
enddef

# Initialize script-local runtime state from g:calendar_config.
def InitVariables(): bool

  if !exists('g:calendar_config')
    g:calendar_config = {}
  elseif type(g:calendar_config) != v:t_dict
    echoerr "'g:calendar_config' must be a dict"
    return false
  endif

  var cfg = g:calendar_config

  cfg_position = NormalizePos(get(cfg, 'position', 'left'))
  cfg_cal_type = NormalizeCalType(get(cfg, 'cal_type', 'eu'))
  cfg_show_week_number = !!get(cfg, 'show_week_number', false)
  cfg_number_of_months = max([1, get(cfg, 'number_of_months', 3)])

  var h = get(cfg, 'holidays', {})
  cfg_holidays = type(h) == v:t_dict ? h : {}

  cfg_search_grep = tolower(get(cfg, 'search_grep', 'internal'))
  if cfg_search_grep !=# 'internal' && cfg_search_grep !=# 'external'
    cfg_search_grep = 'internal'
  endif

  cfg_action = get(cfg, 'action', 'OpenDiaryPage')
  cfg_auto_create_diary_dirs = !!get(cfg, 'auto_create_diary_dirs', false)

  var d = get(cfg, 'diaries_dict', {})
  cfg_diaries = type(d) == v:t_dict && !empty(d) ? d : {My_Diary: {path: '~/my_diary', resolution: 'month'}}

  cfg_active_diary = get(cfg, 'active_diary', '')
  if empty(cfg_active_diary) || !has_key(cfg_diaries, cfg_active_diary)
    cfg_active_diary = keys(cfg_diaries)[0]
    g:calendar_config.active_diary = cfg_active_diary
  endif

  var active = cfg_diaries[cfg_active_diary]

  cfg_diary_path = has_key(active, 'path') ? active.path : '~/my_diary'
  cfg_appointments_path = get(active, 'appointments_path', '')

  return true

enddef

# Resolve month name from backend map.
def MonthName(month: number): string
  return month_num_to_string[printf('%02d', month)]
enddef

# Return rendered weekday labels based on calendar type.
def WeekLabels(): list<string>
  return get(weekdays, cfg_cal_type, weekdays.eu)
enddef

# Return number of rendered day columns for current calendar type.
def DayCols(): number
  return cfg_cal_type ==# 'work' ? 5 : 7
enddef

# Check if week numbers are enabled.
def WeekNumberEnabled(): bool
  return cfg_show_week_number
enddef

# Get month weeks from backend and adapt shape for cal_type.
def MonthWeeks(year: number, month: number): list<list<number>>
  var weeks: list<list<number>> = values(backend.CalendarMonth_iso8601(year, month, WeekNumberEnabled()))[0]

  if cfg_cal_type ==# 'us'
    var us_rows: list<list<number>> = []
    var carry_sunday = 0
    var carry_week = 0

    for row in weeks
      var us_row = row[0 : 6]
      var sunday = us_row[6]
      insert(us_row, carry_sunday, 0)
      remove(us_row, 7)
      if WeekNumberEnabled()
        var wk = len(row) > 7 ? row[7] : 0
        add(us_row, wk)
        carry_week = wk
      endif
      us_rows->add(us_row)
      carry_sunday = sunday
    endfor

    if carry_sunday != 0
      var last_row = [carry_sunday, 0, 0, 0, 0, 0, 0]
      if WeekNumberEnabled()
        add(last_row, carry_week + 1)
      endif
      us_rows->add(last_row)
    endif
    weeks = us_rows
  endif

  if cfg_cal_type ==# 'work'
    var out: list<list<number>> = []
    for row in weeks
      var short_row = row[0 : 4]
      if WeekNumberEnabled()
        add(short_row, row[7])
      endif
      if short_row[0 : 4] != [0, 0, 0, 0, 0]
        out->add(short_row)
      endif
    endfor
    return out
  endif
  return weeks
enddef

# Shift a (year, month) pair by a signed month delta.
# Example: AddMonths(2026, 1, -1) => [2025, 12], AddMonths(2026, 12, 1) => [2027, 1].
# This keeps month within [1..12] and carries overflow/underflow into the year.
def AddMonths(year: number, month: number, delta: number): list<number>
  var y = year
  var m = month + delta

  while m < 1
    y -= 1
    m += 12
  endwhile

  while m > 12
    y += 1
    m -= 12
  endwhile

  return [y, m]
enddef

# Check whether a specific date is configured as holiday.
def IsHoliday(year: number, month: number, day: number): bool
  return has_key(cfg_holidays, printf('%04d-%02d-%02d', year, month, day))
enddef

# Build diary file path for current resolution mode.
def DiaryFilePath(year: number, month: number, _day: number): string
  var year_dir = $"{expand(cfg_diary_path)}/{printf('%04d', year)}"
  return $"{year_dir}/{MonthName(month)}.md"
enddef

# Build one month text block and local highlight positions.
# This is the modern equivalent of the old DisplaySingleCal().
def BuildMonthLines(year: number, month: number): dict<any>
  var weeks = MonthWeeks(year, month)
  var labels = WeekLabels()
  var day_cols = DayCols()
  var lines: list<string> = []
  var today_positions: list<list<number>> = []
  var sat_positions: list<list<number>> = []
  var sun_positions: list<list<number>> = []
  var holiday_positions: list<list<number>> = []
  var week_positions: list<list<number>> = []
  var day_cells: list<dict<any>> = []
  var header = $"{MonthName(month)} {year}"
  var day_col_start = WeekNumberEnabled() ? 4 : 2
  var body_width = day_cols * 3 + (WeekNumberEnabled() ? 4 : 1)
  var pad = max([1, (body_width - len(header)) / 2])

  lines->add($"{repeat(' ', pad)}{header}")
  lines->add(WeekNumberEnabled() ? $"WK  {join(labels, ' ')}" : $"  {join(labels, ' ')}")

  for row_idx in range(0, len(weeks) - 1)
    var row = weeks[row_idx]
    var line = WeekNumberEnabled() ? $"{printf('%2d', len(row) > day_cols ? row[day_cols] : 0)} " : ' '
    for col_idx in range(0, day_cols - 1)
      var d = row[col_idx]
      if d == 0
        line ..= '   '
        continue
      endif
      var mark = ' '
      line ..= $"{mark}{printf('%2d', d)}"
    endfor
    lines->add(line)

    var lnum = len(lines)
    for col_idx in range(0, day_cols - 1)
      var d = row[col_idx]
      if d == 0
        continue
      endif
      var start_col = day_col_start + col_idx * 3
      day_cells->add({
        day: d,
        row: row_idx,
        col: col_idx,
        line: lnum,
        colpos: start_col + 1,
      })
      if cfg_cal_type ==# 'eu' && col_idx == 5
        sat_positions->add([lnum, start_col + 1, 2])
      elseif cfg_cal_type ==# 'eu' && col_idx == 6
        sun_positions->add([lnum, start_col + 1, 2])
      elseif cfg_cal_type ==# 'us' && col_idx == 0
        sun_positions->add([lnum, start_col + 1, 2])
      elseif cfg_cal_type ==# 'us' && col_idx == 6
        sat_positions->add([lnum, start_col + 1, 2])
      endif
      if IsHoliday(year, month, d)
        holiday_positions->add([lnum, start_col + 1, 2])
      endif
      if printf('%04d%02d%02d', year, month, d) ==# strftime('%Y%m%d')
        today_positions->add([lnum, start_col + 1, 2])
      endif
    endfor
    if WeekNumberEnabled()
      week_positions->add([lnum, 1, 2])
    endif
  endfor
  if WeekNumberEnabled()
    week_positions->insert([2, 1, 2])
  endif

  return {
    lines: lines,
    today: today_positions,
    sat: sat_positions,
    sun: sun_positions,
    holiday: holiday_positions,
    week: week_positions,
    cells: day_cells,
    day_col_start: day_col_start,
    day_col_end: day_col_start + day_cols * 3 - 1,
  }
enddef

# Shift match positions by line/column offsets.
def ShiftPositions(pos: list<list<number>>, line_off: number, col_off: number): list<list<number>>
  return pos->mapnew((_, p) => [p[0] + line_off, p[1] + col_off, p[2]])
enddef

# Compose multi-month vertical view (left/right positions).
def BuildVerticalComposite(months: list<dict<any>>): dict<any>
  var out_lines: list<string> = []
  var blocks: list<dict<any>> = []
  var today_all: list<list<number>> = []
  var sat_all: list<list<number>> = []
  var sun_all: list<list<number>> = []
  var holiday_all: list<list<number>> = []
  var week_all: list<list<number>> = []
  var cells_all: list<dict<any>> = []
  var line_cursor = 1

  for m in months
    var start_line = line_cursor
    extend(out_lines, m.lines)
    line_cursor += len(m.lines)

    blocks->add({
      year: m.year,
      month: m.month,
      line_start: start_line + 2,
      line_end: line_cursor - 1,
      col_start: 1,
      col_end: len(m.lines[0]),
      day_col_start: m.day_col_start,
      day_col_end: m.day_col_end,
    })

    extend(today_all, ShiftPositions(m.today, start_line - 1, 0))
    extend(sat_all, ShiftPositions(m.sat, start_line - 1, 0))
    extend(sun_all, ShiftPositions(m.sun, start_line - 1, 0))
    extend(holiday_all, ShiftPositions(m.holiday, start_line - 1, 0))
    extend(week_all, ShiftPositions(m.week, start_line - 1, 0))
    for c in m.cells
      cells_all->add({
        day: c.day,
        row: c.row,
        col: c.col,
        line: c.line + start_line - 1,
        colpos: c.colpos,
      })
    endfor

    out_lines->add('')
    line_cursor += 1
  endfor

  return {lines: out_lines, blocks: blocks, today: today_all, sat: sat_all, sun: sun_all, holiday: holiday_all, week: week_all, cells: cells_all}
enddef

# Append diary selection section and return diary row mapping.
def AppendDiarySection(lines: list<string>): dict<string>
  var diary_rows: dict<string> = {}
  if len(cfg_diaries) <= 1
    return diary_rows
  endif

  lines->add('Calendar')
  lines->add(repeat('-', max([20, len('Calendar')])))

  for name in keys(cfg_diaries)
    lines->add(name ==# cfg_active_diary ? $"(*) {name}" : $"( ) {name}")
    diary_rows[string(len(lines))] = name
  endfor

  return diary_rows
enddef

# Build full rendered view for the selected base month.
# This is the modern equivalent of the old DisplayMultipleCalVert().
def BuildView(base_year: number, base_month: number): dict<any>
  var months: list<dict<any>> = []

  var n_months = cfg_position ==# 'popup' ? 1 : cfg_number_of_months

  var start_offset = n_months == 1 ? 0 : -((n_months - 1) / 2)

  for idx in range(0, n_months - 1)
    var ym = AddMonths(base_year, base_month, start_offset + idx)
    var m = BuildMonthLines(ym[0], ym[1])
    m.year = ym[0]
    m.month = ym[1]
    months->add(m)
  endfor

  var composed = BuildVerticalComposite(months)
  insert(composed.lines, 'Hit "?" for help', 0)
  insert(composed.lines, '', 1)

  var shifted_blocks: list<dict<any>> = []
  for b in composed.blocks
    shifted_blocks->add({
      year: b.year,
      month: b.month,
      line_start: b.line_start + 2,
      line_end: b.line_end + 2,
      col_start: b.col_start,
      col_end: b.col_end,
      day_col_start: b.day_col_start,
      day_col_end: b.day_col_end,
    })
  endfor

  composed.blocks = shifted_blocks
  composed.today = ShiftPositions(composed.today, 2, 0)
  composed.sat = ShiftPositions(composed.sat, 2, 0)
  composed.sun = ShiftPositions(composed.sun, 2, 0)
  composed.holiday = ShiftPositions(composed.holiday, 2, 0)
  composed.week = ShiftPositions(composed.week, 2, 0)
  composed.cells = composed.cells->mapnew((_, c) => ({
    day: c.day,
    row: c.row,
    col: c.col,
    line: c.line + 2,
    colpos: c.colpos,
  }))

  var diary_rows = AppendDiarySection(composed.lines)

  return {
    lines: composed.lines,
    blocks: composed.blocks,
    diary_rows: diary_rows,
    today: composed.today,
    sat: composed.sat,
    sun: composed.sun,
    holiday: composed.holiday,
    week: composed.week,
    cells: composed.cells,
  }
enddef

# Open or reuse calendar buffer window according to target position.
def OpenCalendarWindow(): number

  var bw = bufnr(cal_bufname)
  var ww = bw > 0 ? bufwinnr(bw) : -1
  if ww > 0
    execute $":{ww}wincmd w"
    return win_getid()
  endif

  if cfg_position ==# 'left'
    topleft vnew
  elseif cfg_position ==# 'right'
    botright vnew
  else
    topleft vnew
  endif

  execute $"file {cal_bufname}"
  setlocal buftype=nofile bufhidden=delete noswapfile nowrap nobuflisted nomodified
  if exists('+winfixbuf')
    setlocal winfixbuf
  endif
  setlocal fdc=0 nonu
  if has('+relativenumber') || exists('+relativenumber')
    setlocal nornu
  endif

  return win_getid()
enddef

# Apply match highlights to the current calendar buffer.
def ApplyHighlights(view: dict<any>)
  if exists('w:cal_today') | silent! matchdelete(w:cal_today) | endif
  if exists('w:cal_sat') | silent! matchdelete(w:cal_sat) | endif
  if exists('w:cal_sun') | silent! matchdelete(w:cal_sun) | endif
  if exists('w:cal_holiday') | silent! matchdelete(w:cal_holiday) | endif
  if exists('w:cal_week') | silent! matchdelete(w:cal_week) | endif
  if exists('w:cal_weekdays') | silent! matchdelete(w:cal_weekdays) | endif
  if exists('w:cal_help') | silent! matchdelete(w:cal_help) | endif
  if exists('w:cal_header') | silent! matchdelete(w:cal_header) | endif
  if exists('w:cal_currlist') | silent! matchdelete(w:cal_currlist) | endif

  if !empty(view.today) | w:cal_today = matchaddpos('CalToday', view.today, 40) | endif
  if !empty(view.sat) | w:cal_sat = matchaddpos('CalSaturday', view.sat, 30) | endif
  if !empty(view.sun) | w:cal_sun = matchaddpos('CalSunday', view.sun, 30) | endif
  if !empty(view.holiday) | w:cal_holiday = matchaddpos('CalHoliday', view.holiday, 32) | endif
  if !empty(view.week) | w:cal_week = matchaddpos('CalWeeknm', view.week, 35) | endif

  w:cal_help = matchadd('CalHelpHint', '^Hit "?" for help$', 20)
  w:cal_header = matchadd('CalHeader', '^\s*[A-Za-z]\+\s\+\d\{4}$', 25)
  w:cal_currlist = matchadd('CalCurrList', '^(\*).*$', 15)
  w:cal_weekdays = matchadd('CalWeekdays', '^\s*\%(WK\s\+\)\?\%(Mo\|Tu\|We\|Th\|Fr\|Sa\|Su\)\%( \%(Mo\|Tu\|We\|Th\|Fr\|Sa\|Su\)\)\+\s*$', 22)
enddef

def ApplyPopupHighlights(winid: number, view: dict<any>)
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
  win_execute(winid, 'call matchadd(''CalHelpHint'', ''^Hit "?" for help$'', 20)')
  win_execute(winid, 'call matchadd(''CalHeader'', ''^\s*[A-Za-z]\+\s\+\d\{4}$'', 25)')
  win_execute(winid, 'call matchadd(''CalCurrList'', ''^(\*).*$'', 15)')
  win_execute(winid, 'call matchadd(''CalWeekdays'', ''^\s*\%(WK\s\+\)\?\%(Mo\|Tu\|We\|Th\|Fr\|Sa\|Su\)\%( \%(Mo\|Tu\|We\|Th\|Fr\|Sa\|Su\)\)\+\s*$'', 22)')
enddef

def PopupSetSelectedDay(index: number)
  if popup_id <= 0 || empty(popup_day_cells)
    return
  endif
  var idx = min([max([0, index]), len(popup_day_cells) - 1])
  popup_day_index = idx
  var c = popup_day_cells[idx]
  var pos = [[c.line, c.colpos, 2]]
  win_execute(popup_id, "if getwinvar(win_getid(), 'cal_popup_day', 0) > 0 | call matchdelete(getwinvar(win_getid(), 'cal_popup_day')) | call setwinvar(win_getid(), 'cal_popup_day', 0) | endif")
  win_execute(popup_id, $"call setwinvar(win_getid(), 'cal_popup_day', matchaddpos('CalPopupSelection', {string(pos)}, 50))")
  win_execute(popup_id, $"call cursor({c.line}, {c.colpos})")
enddef

def PopupInitSelection(view: dict<any>)
  popup_day_cells = get(view, 'cells', [])
  popup_day_index = -1
  if empty(popup_day_cells)
    return
  endif
  var target_idx = 0
  if popup_year == str2nr(strftime('%Y')) && popup_month == str2nr(strftime('%m'))
    var today = str2nr(strftime('%d'))
    for i in range(0, len(popup_day_cells) - 1)
      if popup_day_cells[i].day == today
        target_idx = i
        break
      endif
    endfor
  endif
  PopupSetSelectedDay(target_idx)
enddef

def PopupMoveSelection(key: string)
  if empty(popup_day_cells) || popup_day_index < 0
    return
  endif
  var cur = popup_day_cells[popup_day_index]
  var next_idx = popup_day_index

  if key ==# 'h'
    next_idx = max([0, popup_day_index - 1])
  elseif key ==# 'l'
    next_idx = min([len(popup_day_cells) - 1, popup_day_index + 1])
  elseif key ==# 'j' || key ==# 'k'
    var target_row = key ==# 'j' ? cur.row + 1 : cur.row - 1
    var best_idx = -1
    var best_dist = 999
    for i in range(0, len(popup_day_cells) - 1)
      var c = popup_day_cells[i]
      if c.row != target_row
        continue
      endif
      var dist = abs(c.col - cur.col)
      if best_idx < 0 || dist < best_dist
        best_idx = i
        best_dist = dist
      endif
    endfor
    if best_idx >= 0
      next_idx = best_idx
    endif
  else
    return
  endif

  PopupSetSelectedDay(next_idx)
enddef

def PopupCycleDiary(step: number): bool
  if len(cfg_diaries) <= 1
    return false
  endif
  var names = keys(cfg_diaries)
  var idx = index(names, cfg_active_diary)
  if idx < 0
    idx = 0
  endif
  idx = (idx + step + len(names)) % len(names)
  if !ActivateDiary(names[idx])
    return false
  endif
  if cfg_position ==# 'popup'
    RenderView(popup_year, popup_month)
  else
    RenderView(state_base_year, state_base_month)
  endif
  return true
enddef

def PopupOpenSelectedDay(): bool
  if popup_day_index < 0 || popup_day_index >= len(popup_day_cells)
    return false
  endif
  var day = popup_day_cells[popup_day_index].day
  var week = WeekdayForDate(popup_year, popup_month, day)
  var action_name = 'OpenDiaryPage'
  if type(cfg_action) == v:t_string && !empty(cfg_action) && exists('*' .. cfg_action)
    action_name = cfg_action
  endif
  call(function(action_name), [day, popup_month, popup_year, week])
  return true
enddef

# Render calendar view into split window or popup.
def RenderView(base_year: number, base_month: number)

  var view = BuildView(base_year, base_month)

  if cfg_position ==# 'popup'
    if popup_id > 0
      popup_close(popup_id)
    endif

    popup_year = base_year
    popup_month = base_month

    popup_id = popup_create(view.lines, {
      title: ' Calendar ',
      pos: 'center',
      borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
      border: [1, 1, 1, 1],
      filter: PopupFilter,
      mapping: 0,
      drag: 0,
      scrollbar: 0,
    })
    state_base_year = base_year
    state_base_month = base_month
    state_blocks = view.blocks
    state_diary_rows = view.diary_rows
    ApplyPopupHighlights(popup_id, view)
    PopupInitSelection(view)
    return
  endif

  silent! doautocmd User CalendarBeforeShow
  var winid = OpenCalendarWindow()

  setlocal modifiable
  deletebufline('%', 1, '$')
  append(0, view.lines)
  deletebufline('%', len(view.lines) + 1)
  setlocal nomodifiable

  var width = max(view.lines->mapnew((_, s) => len(s))) + 2
  var height = len(view.lines) + 1
  if cfg_position ==# 'left' || cfg_position ==# 'right'
    execute $"vertical resize {min([max([20, width]), &columns - 5])}"
  else
    execute $"resize {min([max([8, height]), &lines - 3])}"
  endif

  state_base_year = base_year
  state_base_month = base_month
  state_blocks = view.blocks
  state_diary_rows = view.diary_rows

  CalendarBuildKeymap()
  ApplyHighlights(view)
  setlocal statusline=%!strftime('%A,\ %Y-%m-%d')

  if !empty(view.today)
    cursor(view.today[0][0], view.today[0][1])
  endif
  win_execute(winid, 'normal! zv')
enddef

# Compute ISO weekday (1=Mon..7=Sun) for a specific date.
def WeekdayForDate(year: number, month: number, day: number): number
  var iso = values(backend.CalendarMonth_iso8601(year, month, false))[0]
  for row in iso
    for idx in range(0, 6)
      if row[idx] == day
        return idx + 1
      endif
    endfor
  endfor
  return 0
enddef

# Resolve the month block under cursor in current rendered view.
def FindBlockAtCursor(): dict<any>
  var l = line('.')
  var c = col('.')
  for block in state_blocks
    if l >= block.line_start && l <= block.line_end && c >= block.col_start && c <= block.col_end
      return block
    endif
  endfor
  return {}
enddef

def ActivateDiary(name: string): bool
  if !has_key(cfg_diaries, name)
    return false
  endif
  g:calendar_config.active_diary = name
  cfg_active_diary = name
  var d = cfg_diaries[name]
  cfg_diary_path = has_key(d, 'path') ? d.path : cfg_diary_path
  return true
enddef

# Handle diary switch when cursor is on a diary selector row, i.e. when on
# the following section
#
#    Calendar
#    -----------
#    ( ) Note
#    (*) Diary
#
def SwitchDiaryAtCursor(): bool
  var rows = state_diary_rows
  var key = string(line('.'))
  if !has_key(rows, key)
    return false
  endif

  var name = rows[key]
  if !has_key(cfg_diaries, name)
    return false
  endif

  if !ActivateDiary(name)
    return false
  endif

  var curp = getpos('.')

  RenderView(state_base_year, state_base_month)

  setpos('.', curp)
  return true
enddef

# Handle calendar navigation actions and re-render.
def HandleNavigation(arg: string): bool
  var y = state_base_year
  var m = state_base_month

  if arg ==# 'NextMonth'
    var ym = AddMonths(y, m, 1)
    y = ym[0] | m = ym[1]
  elseif arg ==# 'PrevMonth'
    var ym = AddMonths(y, m, -1)
    y = ym[0] | m = ym[1]
  elseif arg ==# 'NextYear'
    y += 1
  elseif arg ==# 'PrevYear'
    y -= 1
  elseif arg ==# 'Today'
    y = str2nr(strftime('%Y'))
    m = str2nr(strftime('%m'))
  elseif arg ==# 'NextDiary'
    PopupCycleDiary(1)
    return true
  elseif arg ==# 'PrevDiary'
    PopupCycleDiary(-1)
    return true
  else
    return false
  endif

  var curp = getpos('.')

  RenderView(y, m)

  setpos('.', curp)
  return true
enddef

# Main action for operations specified in CalendarBuildKeymap()
def Action(arg: string = '')

  if !empty(arg) && HandleNavigation(arg)
    return
  endif

  # Check first if you are in "diary selection area", e.g. in the section
  #
  #    Calendar
  #    -----------
  #    ( ) Note
  #    (*) Diary
  #
  if SwitchDiaryAtCursor()
    return
  endif

  # If cursor is on a whitespace don't do anything
  var day_string = matchstr(expand('<cword>'), '^\d\{1,2}$')
  if empty(day_string)
    return
  endif

  # Otherwise call cfg_action, but first extract [day, month, year, week]
  # arguments
  var day = str2nr(day_string)

  var block = FindBlockAtCursor()

  # Guard that the cursor is not on any weird place
  if empty(block) || col('.') < block.day_col_start || col('.') > block.day_col_end
    return
  endif

  var month = block.month
  var year = block.year
  var week = WeekdayForDate(year, month, day)

  var action_name = 'OpenDiaryPage'
  if type(cfg_action) == v:t_string && !empty(cfg_action) && exists('*' .. cfg_action)
    action_name = cfg_action
  endif
  call(function(action_name), [day, month, year, week])

  # Always refresh week view when visible
  if week_view_winid > 0 && win_id2win(week_view_winid) > 0
    RenderWeekView(year, month, day, {})
  endif
enddef

# Close split window or popup calendar.
def Close()
  if popup_id > 0
    popup_close(popup_id)
    popup_id = -1
  else
    week_view_winid = -1
    if tabpagenr('$') > 1
      tabclose!
    else
      for bname in [cal_bufname, WEEK_BUF_NAME]
        var bn = bufnr(bname)
        if bn > 0
          execute $'bwipeout! {bn}'
        endif
      endfor
    endif
  endif
enddef

def EnsureDiaryDir(path: string): bool
  if isdirectory(path)
    return true
  endif
  if cfg_auto_create_diary_dirs
    mkdir(path, 'p')
    if isdirectory(path)
      return true
    endif
    confirm($"failed to create diary directory: {path}", 'OK')
    return false
  endif
  confirm($"please create diary directory: {path}", 'OK')
  return false
enddef

# Default action: open/create markdown diary file for selected date.
def OpenDiaryPage(day: number, month: number, year: number, week: number)
  var diary_root = expand(cfg_diary_path)
  if !EnsureDiaryDir(diary_root)
    return
  endif

  var year_dir = $"{diary_root}/{printf('%04d', year)}"
  if !EnsureDiaryDir(year_dir)
    return
  endif

  var file = substitute(DiaryFilePath(year, month, day), ' ', '\\ ', 'g')
  silent! wincmd p
  if exists('+winfixbuf') && &l:winfixbuf
    setlocal nowinfixbuf
  endif
  execute $"edit {file}"

enddef

# Filter for help popup: close with q or <Esc>.
def HelpPopupFilter(id: number, key: string): bool
  if key ==# 'q' || key ==# "\<Esc>"
    popup_close(id)
    help_popup_id = -1
    return true
  endif
  return false
enddef

# Show help popup for calendar key bindings.
def CalendarHelp()
  var lines = [
    'Calendar key bindings',
    '',
    'h/j/k/l  move cursor',
    '<Up>  previous month',
    '<Down>  next month',
    '<Left>  previous year',
    '<Right>  next year',
    '<CR>  open/switch on cursor',
    't  go to today',
    '<Tab> / <S-Tab>  next/prev diary',
    '',
    'q or <Esc>  close',
  ]
  if help_popup_id > 0
    popup_close(help_popup_id)
  endif

  const popup_opts = {
    title: ' Calendar Help ',
    borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    border: [1, 1, 1, 1],
    filter: HelpPopupFilter,
    mapping: 0,
  }

  help_popup_id = popup_create(lines, popup_opts)


  # Display popup in the bottom right corner to avoid overlap
  if cfg_position ==# 'popup'
    const added_opts = {
        line: &lines,
        col: &columns,
        pos: "botright"
    }

    const popup_opts_extended = extendnew(popup_opts, added_opts)
    popup_setoptions(help_popup_id, popup_opts_extended)
  endif

enddef

# Build buffer-local key mappings for calendar interactions.
def CalendarBuildKeymap()

  nnoremap <silent> <buffer> q <ScriptCmd>Close()<CR>
  nnoremap <silent> <buffer> <Esc> <ScriptCmd>Close()<CR>
  nnoremap <silent> <buffer> <CR> <ScriptCmd>Action()<CR>
  nnoremap <silent> <buffer> <Down> <ScriptCmd>Action('NextMonth')<CR>
  nnoremap <silent> <buffer> <Up> <ScriptCmd>Action('PrevMonth')<CR>
  nnoremap <silent> <buffer> <Right> <ScriptCmd>Action('NextYear')<CR>
  nnoremap <silent> <buffer> <Left> <ScriptCmd>Action('PrevYear')<CR>
  nnoremap <silent> <buffer> t <ScriptCmd>Action('Today')<CR>
  nnoremap <silent> <buffer> <Tab> <ScriptCmd>Action('NextDiary')<CR>
  nnoremap <silent> <buffer> <S-Tab> <ScriptCmd>Action('PrevDiary')<CR>
  nnoremap <silent> <buffer> ? <ScriptCmd>CalendarHelp()<CR>

enddef

# Popup key filter for navigation and actions.
def PopupFilter(id: number, key: string): bool
  if key ==# 'q' || key ==# "\<Esc>"
    popup_close(id)
    popup_id = -1
    return true
  elseif key ==# "\<Down>"
    var ym = AddMonths(popup_year, popup_month, 1)
    popup_year = ym[0] | popup_month = ym[1]
    RenderView(popup_year, popup_month)
    return true
  elseif key ==# "\<Up>"
    var ym = AddMonths(popup_year, popup_month, -1)
    popup_year = ym[0] | popup_month = ym[1]
    RenderView(popup_year, popup_month)
    return true
  elseif key ==# "\<Right>"
    popup_year += 1
    RenderView(popup_year, popup_month)
    return true
  elseif key ==# "\<Left>"
    popup_year -= 1
    RenderView(popup_year, popup_month)
    return true
  elseif key ==# "\<CR>"
    if !PopupOpenSelectedDay()
      Action()
    endif
    Close()
    return true
  elseif key ==# '?'
    CalendarHelp()
    return true
  elseif key ==# 't'
    popup_year = str2nr(strftime('%Y'))
    popup_month = str2nr(strftime('%m'))
    RenderView(popup_year, popup_month)
    return true
  elseif key ==# "\<Tab>"
    PopupCycleDiary(1)
    return true
  elseif key ==# "\<S-Tab>"
    PopupCycleDiary(-1)
    return true
  elseif key ==# "\<CursorHold>"
    return true
  elseif key ==# 'h' || key ==# 'j' || key ==# 'k' || key ==# 'l'
    PopupMoveSelection(key)
    return true
  endif
  return false
enddef

# ─── Week view helpers ───────────────────────────────────────────────────────

# Julian Day Number formula (Fliegel & Van Flandern, 1968).
def DateToJDN(year: number, month: number, day: number): number
  var a = (14 - month) / 12
  var y = year + 4800 - a
  var m = month + 12 * a - 3
  return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
enddef

# Inverse of DateToJDN (same paper).
def JDNToDate(jdn: number): dict<any>
  var a = jdn + 32044
  var b = (4 * a + 3) / 146097
  var c = a - (146097 * b) / 4
  var d = (4 * c + 3) / 1461
  var e = c - (1461 * d) / 4
  var m = (5 * e + 2) / 153
  return {
    day:   e - (153 * m + 2) / 5 + 1,
    month: m + 3 - 12 * (m / 10),
    year:  100 * b + d - 4800 + m / 10,
  }
enddef

# Return list of 7 date dicts {year, month, day} for Mon–Sun of the ISO week
# that contains the given date.
def WeekDays(year: number, month: number, day: number): list<dict<any>>
  var wd = WeekdayForDate(year, month, day)   # 1=Mon .. 7=Sun
  var mon_jdn = DateToJDN(year, month, day) - (wd - 1)
  return range(7)->mapnew((i, _) => JDNToDate(mon_jdn + i))
enddef

# ISO week number: Thursday of the week is always in the same ISO year;
# Jan 4 is always in ISO week 1 (ISO 8601).
def ISOWeekNum(year: number, month: number, day: number): number
  var wd = WeekdayForDate(year, month, day)
  var thu_jdn = DateToJDN(year, month, day) + (4 - wd)
  var thu = JDNToDate(thu_jdn)
  var jan4_jdn = DateToJDN(thu.year, 1, 4)
  var jan4_wd = (jan4_jdn + 1) % 7
  if jan4_wd == 0
    jan4_wd = 7
  endif
  return (thu_jdn - (jan4_jdn - (jan4_wd - 1))) / 7 + 1
enddef

# Build horizontal separator line for the week grid.
# is_header: true uses ┬ (top join), false uses ┼ (cross join).
def WeekSepLine(join_char: string): string
  return repeat('─', WEEK_TIME_COL) .. join_char ..
    join(range(7)->mapnew((_, _) => repeat('─', WEEK_DAY_COL)), join_char)
enddef

# Build one data row: time column + 7 day cells separated by │.
def WeekDataRow(time_cell: string, day_cells: list<string>): string
  var tc = printf('%-*s', WEEK_TIME_COL, strcharpart(time_cell, 0, WEEK_TIME_COL))
  return tc .. '│' .. join(day_cells->mapnew(
    (_, c) => printf('%-*s', WEEK_DAY_COL, strcharpart(c, 0, WEEK_DAY_COL))), '│')
enddef

# Truncate / pad text to fit in a day cell (1-space left margin).
def CellText(text: string): string
  var max_len = WEEK_DAY_COL - 1
  var content = strcharlen(text) > max_len
    ? strcharpart(text, 0, max_len - 3) .. '...'
    : text
  return ' ' .. content
enddef

# Return [row1, row2] strings for an event cell.
def FormatEventCells(subject: string, organizer: string): list<string>
  return [CellText(subject), CellText('(' .. organizer .. ')')]
enddef

# Build the week header string, e.g. "27 - 31 Jul 2026 (week 31)".
def WeekHeaderStr(wdays: list<dict<any>>, week_num: number): string
  var first = wdays[0]
  var last  = wdays[6]
  if first.month == last.month
    return printf('%d - %d %s %d (week %d)',
      first.day, last.day, MonthName(first.month), first.year, week_num)
  endif
  return printf('%d %s - %d %s %d (week %d)',
    first.day, MonthName(first.month)[: 2],
    last.day,  MonthName(last.month)[: 2],
    last.year, week_num)
enddef

# Return the first event matching the given hour, or {} if none.
def FindHourEvent(events: dict<any>, date_key: string, hour: number): dict<any>
  for ev in get(events, date_key, [])
    if str2nr(split(get(ev, 'start', '00:00'), ':')[0]) == hour
      return ev
    endif
  endfor
  return {}
enddef

# Set up the __WeekView__ buffer in window with the given buffer number,
# repurposing it in-place.  Updates week_view_winid.  Returns true on success.
def OpenWeekViewWindow(tabnew_bufnr: number): bool
  var winnr = bufwinnr(tabnew_bufnr)
  if winnr <= 0
    return false
  endif
  win_gotoid(win_getid(winnr))
  execute $'file {WEEK_BUF_NAME}'
  setlocal buftype=nofile bufhidden=delete noswapfile nowrap nobuflisted nomodified
  setlocal textwidth=0 colorcolumn=0 fdc=0 nonu
  if has('+relativenumber') || exists('+relativenumber')
    setlocal nornu
  endif
  week_view_winid = win_getid()
  return true
enddef

# Render (or re-render) the week view buffer for the week containing
# (year, month, day).  Pass events as a dict keyed 'YYYY-MM-DD' → list of
# {start: 'HH:MM', subject: '...', organizer: '...'}.
export def RenderWeekView(year: number, month: number, day: number, events: dict<any>)
  if week_view_winid <= 0 || win_id2win(week_view_winid) == 0
    return
  endif

  var wdays    = WeekDays(year, month, day)
  var week_num = ISOWeekNum(year, month, day)

  var lines: list<string> = []

  lines->add(WeekHeaderStr(wdays, week_num))
  lines->add(WeekSepLine('┬'))

  var day_labels = wdays->mapnew(
    (i, d) => CellText(printf('%d, %s', d.day, WEEK_DAY_FULL[i])))
  lines->add(WeekDataRow(' UTC+2', day_labels))
  lines->add(WeekSepLine('┼'))

  for h in range(0, 23)
    var row1: list<string> = []
    var row2: list<string> = []
    for d in wdays
      var ev = FindHourEvent(events, printf('%04d-%02d-%02d', d.year, d.month, d.day), h)
      var [l1, l2] = empty(ev)
        ? ['', '']
        : FormatEventCells(get(ev, 'subject', ''), get(ev, 'organizer', ''))
      row1->add(l1)
      row2->add(l2)
    endfor
    lines->add(WeekDataRow(printf('%3d', h), row1))
    lines->add(WeekDataRow('', row2))
    lines->add(WeekSepLine('┼'))
  endfor

  var wv_buf = winbufnr(week_view_winid)
  setbufvar(wv_buf, '&modifiable', 1)
  deletebufline(wv_buf, 1, '$')
  setbufline(wv_buf, 1, lines)
  setbufvar(wv_buf, '&modifiable', 0)
enddef

# ─── End week view helpers ────────────────────────────────────────────────────

# Parse the JSON at path and refresh the week view.
# JSON format: list of {start, end, subject, organizer, location, body}.
export def LoadAppointments(path: string)
  if !filereadable(path)
    return
  endif
  var items: list<any> = []
  try
    items = json_decode(readfile(path)->join("\n"))
  catch
    echomsg '[Calendar] Could not parse appointments file.'
    return
  endtry

  var events: dict<list<any>> = {}
  for item in items
    var date_key = strpart(get(item, 'start', ''), 0, 10)
    if !has_key(events, date_key)
      events[date_key] = []
    endif
    events[date_key]->add({
      start:     strpart(get(item, 'start', ''), 11, 5),
      end:       strpart(get(item, 'end',   ''), 11, 5),
      subject:   get(item, 'subject',   ''),
      organizer: get(item, 'organizer', ''),
      location:  get(item, 'location',  ''),
      body:      get(item, 'body',      ''),
    })
  endfor

  var y = str2nr(strftime('%Y'))
  var m = str2nr(strftime('%m'))
  var d = str2nr(strftime('%d'))
  RenderWeekView(y, m, d, events)
enddef

# Reload appointments from the active diary's appointments_path and re-render.
export def CalendarRefresh()
  if !empty(cfg_appointments_path)
    LoadAppointments(cfg_appointments_path)
  endif
enddef

# Toggle the calendar tab: jump to it if open elsewhere, close if current,
# open fresh if not yet open.
var cal_tab_winid = -1

export def CalendarToggle()
  if !InitVariables()
    return
  endif

  if win_id2win(cal_tab_winid) > 0
    var [tabnr, _] = win_id2tabwin(cal_tab_winid)
    if tabpagenr() == tabnr
      cal_tab_winid = -1
      tabclose
    else
      execute $'tabnext {tabnr}'
      win_gotoid(cal_tab_winid)
    endif
    return
  endif

  var y = str2nr(strftime('%Y'))
  var m = str2nr(strftime('%m'))
  Show(y, m)
  cal_tab_winid = win_getid()
enddef

# Main entrypoint used by :Calendar command.
export def Show(year: number = -1, month: number = -1): string

  if !InitVariables()
    return ''
  endif

  var y = year == -1 ? str2nr(strftime('%Y')) : year
  var m = month == -1 ? str2nr(strftime('%m')) : month

  if cfg_position ==# 'popup'
    RenderView(y, m)
    return ''
  endif

  # Open a dedicated tab: calendar on one side, week view on the other.
  tabnew
  var tabnew_bufnr = bufnr('%')
  RenderView(y, m)
  var cal_winid = win_getid()

  if OpenWeekViewWindow(tabnew_bufnr)
    RenderWeekView(y, m, str2nr(strftime('%d')), {})
  endif

  win_gotoid(cal_winid)
  return ''
enddef

# Search keyword across diary markdown files.
export def Search(keyword: string, year: string = '')

  if !InitVariables()
    return
  endif

  var search_year = empty(year) ? strftime("%Y") : year

  if cfg_search_grep ==# 'internal'
    var pattern = escape(keyword, '/\')
    echom $"vimgrep /{pattern}/{escape(cfg_diary_path, ' ')}/{search_year}/**/*.md"
    execute $"vimgrep /{pattern}/{escape(cfg_diary_path, ' ')}/{search_year}/**/*.md"
  else
    execute $"grep! {keyword} {escape(cfg_diary_path, ' ')}/{search_year}/**/*.md"
  endif

  silent cwindow

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
