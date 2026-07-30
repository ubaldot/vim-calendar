vim9script

# Pure calendar view builder.
# All state is initialized via Configure() / SetActiveDiary() before any
# Build* call.  No UI side-effects.

import autoload "./backend.vim"

const month_num_to_string = backend.month_num_to_str

const weekdays: dict<list<string>> = {
  us: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'],
  eu: ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'],
  work: ['Mo', 'Tu', 'We', 'Th', 'Fr'],
}

var cfg_cal_type        = 'eu'
var cfg_show_week_number = false
var cfg_number_of_months = 3
var cfg_position        = 'left'
var cfg_holidays: dict<any>  = {}
var cfg_diaries: dict<any>   = {}
var cfg_active_diary    = ''
var cfg_diary_path      = '~/my_diary'

# Initialize all view config from a dict (call from InitVariables).
export def Configure(cfg: dict<any>)
  cfg_cal_type          = get(cfg, 'cal_type',          'eu')
  cfg_show_week_number  = get(cfg, 'show_week_number',  false)
  cfg_number_of_months  = get(cfg, 'number_of_months',  3)
  cfg_position          = get(cfg, 'position',          'left')
  cfg_holidays          = get(cfg, 'holidays',          {})
  cfg_diaries           = get(cfg, 'diaries',           {})
  cfg_active_diary      = get(cfg, 'active_diary',      '')
  cfg_diary_path        = get(cfg, 'diary_path',        '~/my_diary')
enddef

# Update only active-diary fields (call from ActivateDiary).
export def SetActiveDiary(name: string, path: string)
  cfg_active_diary = name
  cfg_diary_path   = path
enddef

export def WeekNumberEnabled(): bool
  return cfg_show_week_number
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
export def AddMonths(year: number, month: number, delta: number): list<number>
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
export def DiaryFilePath(year: number, month: number, _day: number): string
  var year_dir = $"{expand(cfg_diary_path)}/{printf('%04d', year)}"
  return $"{year_dir}/{MonthName(month)}.md"
enddef

# Build one month text block and local highlight positions.
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

# Compose multi-month vertical view.
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
export def BuildView(base_year: number, base_month: number): dict<any>
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

# vim: shiftwidth=2 softtabstop=2 noexpandtab
