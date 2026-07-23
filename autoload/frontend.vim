vim9script

import autoload "./backend.vim"

const cal_bufname = '__Calendar'

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
var cfg_diaries: dict<any> = {My_Diary: {path: '~/my_diary', resolution: 'day'}}
var cfg_active_diary = 'My_Diary'
var cfg_diary_path = '~/my_diary'
var cfg_diary_resolution = 'day'
var cfg_action = 'OpenDiaryPage'
var popup_id = -1
var help_popup_id = -1
var popup_year = 0
var popup_month = 0
var state_base_year = 0
var state_base_month = 0
var state_blocks: list<dict<any>> = []
var state_diary_rows: dict<string> = {}

# Normalize diary resolution to supported values.
def NormalizeResolution(v: any): string
  return type(v) == v:t_string && tolower(v) ==# 'month' ? 'month' : 'day'
enddef

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

  var d = get(cfg, 'diaries_dict', {})
  cfg_diaries = type(d) == v:t_dict && !empty(d) ? d : {My_Diary: {path: '~/my_diary', resolution: 'month'}}

  cfg_active_diary = get(cfg, 'active_diary', '')
  if empty(cfg_active_diary) || !has_key(cfg_diaries, cfg_active_diary)
    cfg_active_diary = keys(cfg_diaries)[0]
    g:calendar_config.active_diary = cfg_active_diary
  endif

  var active = cfg_diaries[cfg_active_diary]

  cfg_diary_path = has_key(active, 'path') ? active.path : '~/my_diary'
  cfg_diary_resolution = NormalizeResolution(has_key(active, 'resolution') ? active.resolution : get(cfg, 'diary_resolution', 'month'))

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
def DiaryFilePath(year: number, month: number, day: number): string
  var year_dir = $"{expand(cfg_diary_path)}/{printf('%04d', year)}"
  var m = MonthName(month)

  if cfg_diary_resolution ==# 'month'
    return $"{year_dir}/{m}.md"
  endif
  return $"{year_dir}/{m}/{printf('%02d', day)}.md"
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
  var week_positions: list<list<number>> = []
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
        sun_positions->add([lnum, start_col + 1, 2])
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
    week: week_positions,
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
  var week_all: list<list<number>> = []
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
    extend(week_all, ShiftPositions(m.week, start_line - 1, 0))

    out_lines->add('')
    line_cursor += 1
  endfor

  return {lines: out_lines, blocks: blocks, today: today_all, sat: sat_all, sun: sun_all, week: week_all}
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
  composed.week = ShiftPositions(composed.week, 2, 0)

  var diary_rows = AppendDiarySection(composed.lines)

  return {
    lines: composed.lines,
    blocks: composed.blocks,
    diary_rows: diary_rows,
    today: composed.today,
    sat: composed.sat,
    sun: composed.sun,
    week: composed.week,
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
  setlocal buftype=nofile bufhidden=delete noswapfile nowrap nolist nomodified
  if exists('+winfixbuf')
    setlocal winfixbuf
  endif
  setlocal fdc=0 nonu
  if has('+relativenumber') || exists('+relativenumber')
    setlocal nornu
  endif

  return win_getid()
enddef

# Apply syntax/match highlights to the current calendar buffer.
def ApplyHighlights(view: dict<any>)
  if exists('w:cal_today') | silent! matchdelete(w:cal_today) | endif
  if exists('w:cal_sat') | silent! matchdelete(w:cal_sat) | endif
  if exists('w:cal_sun') | silent! matchdelete(w:cal_sun) | endif
  if exists('w:cal_week') | silent! matchdelete(w:cal_week) | endif
  if exists('w:cal_help') | silent! matchdelete(w:cal_help) | endif
  if exists('w:cal_header') | silent! matchdelete(w:cal_header) | endif
  if exists('w:cal_currlist') | silent! matchdelete(w:cal_currlist) | endif

  if !empty(view.today) | w:cal_today = matchaddpos('CalToday', view.today, 40) | endif
  if !empty(view.sat) | w:cal_sat = matchaddpos('CalSaturday', view.sat, 30) | endif
  if !empty(view.sun) | w:cal_sun = matchaddpos('CalSunday', view.sun, 30) | endif
  if !empty(view.week) | w:cal_week = matchaddpos('CalWeeknm', view.week, 35) | endif

  w:cal_help = matchadd('CalHelpHint', '^Hit "?" for help$', 20)
  w:cal_header = matchadd('CalHeader', '^\s*[A-Za-z]\+\s\+\d\{4}$', 25)
  w:cal_currlist = matchadd('CalCurrList', '^(\*).*$', 15)
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
  setlocal filetype=calendar
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

  g:calendar_config.active_diary = name
  cfg_active_diary = name

  var d = cfg_diaries[name]
  cfg_diary_path = has_key(d, 'path') ? d.path : cfg_diary_path
  cfg_diary_resolution = NormalizeResolution(has_key(d, 'resolution') ? d.resolution : 'day')

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
enddef

# Close split window or popup calendar.
def Close()
  if popup_id > 0
    # Calendar in popup case
    popup_close(popup_id)
    popup_id = -1
  else
    # Calendar in window case
    bwipeout!
  endif
enddef

# Default action: open/create markdown diary file for selected date.
def OpenDiaryPage(day: number, month: number, year: number, week: number)
  if !isdirectory(expand(cfg_diary_path))
    confirm($"please create diary directory: {cfg_diary_path}", 'OK')
    return
  endif

  var year_dir = $"{expand(cfg_diary_path)}/{printf('%04d', year)}"
  if isdirectory(year_dir) == 0
    confirm($"please create diary directory: {year_dir}", 'OK')
    return
  endif

  if cfg_diary_resolution ==# 'day'
    var month_dir = $"{year_dir}/{MonthName(month)}"
    if isdirectory(month_dir) == 0
      confirm($"please create diary directory: {month_dir}", 'OK')
      return
    endif
  endif

  var file = substitute(DiaryFilePath(year, month, day), ' ', '\\ ', 'g')
  silent! wincmd p
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
    '<CR>  open/switch on cursor',
    '<Up>  previous month',
    '<Down>  next month',
    '<Left>  previous year',
    '<Right>  next year',
    't  go to today',
    'q / <Esc>  close',
    '',
    'h/j/k/l  move cursor',
  ]
  if help_popup_id > 0
    popup_close(help_popup_id)
  endif
  help_popup_id = popup_create(lines, {
    title: ' Calendar Help ',
    pos: 'center',
    borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    border: [1, 1, 1, 1],
    filter: HelpPopupFilter,
    mapping: 0,
  })
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
    Action()
    return true
  elseif key ==# '?'
    CalendarHelp()
    return true
  elseif key ==# 'h' || key ==# 'j' || key ==# 'k' || key ==# 'l'
    win_execute(id, $'normal! {key}')
    return true
  endif
  return false
enddef

# Main entrypoint used by :Calendar command.
export def Show(year: number = -1, month: number = -1): string

  if !InitVariables()
    return ''
  endif

  # Process :Calendar arguments
  var y = year == -1 ? str2nr(strftime('%Y')) : year
  var m = month == -1 ? str2nr(strftime('%m')) : month

  # Actually render the calendar
  RenderView(y, m)

  return ''
enddef

# Search keyword across diary markdown files.
export def Search(keyword: string)

  if !InitVariables()
    return
  endif

  if cfg_search_grep ==# 'internal'
    var pattern = escape(keyword, '/\')
    execute $"vimgrep /{pattern}/{escape(cfg_diary_path, ' ')}/**/*.md"
  else
    execute $"grep! {keyword} {escape(cfg_diary_path, ' ')}/**/*.md"
  endif

  silent cwindow

enddef

hi def link CalSaturday LineNr
hi def link CalSunday WarningMsg
hi def link CalRuler Normal
hi def link CalWeeknm Visual
hi def link CalToday Visual
hi def link CalHeader WarningMsg
hi def link CalHoliday WarningMsg
hi def link CalCurrList Error
hi def link CalHelpHint Question
