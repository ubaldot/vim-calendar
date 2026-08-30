vim9script

import autoload "./appointments.vim"
import autoload "./help_popup.vim"
import autoload "./backend.vim"
import autoload "./highlights.vim"
import autoload "./reminder.vim"

# Week view panel — self-contained module.
# Owns the week view buffers and rendering state.
# Shared state lives in t:cal_* (tab-local, single calendar tab enforced).
# Date math is delegated to backend.vim.

export const WEEK_BUF_NAME = '__WeekView__'
export const WEEK_HDR_BUF_NAME = '__WeekHeader__'
const WEEK_TIME_COL = 8
const WEEK_DAY_FULL = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

# The hour grid has one line per half hour, so an event spans as many lines as
# it lasts half hours: a 1.5-hour event covers 3 lines.  Hour separators are
# drawn between hours and do not count towards an event's span.
const ROWS_PER_HOUR = 2
const TOTAL_ROWS    = 24 * ROWS_PER_HOUR
const LINES_PER_HOUR = ROWS_PER_HOUR + 1   # 2 half-hour rows + 1 separator

# Separates side-by-side lanes inside one day cell.  Deliberately different
# from the '│' used for day boundaries so a lane split cannot be mistaken for
# the start of the next day.
const LANE_SEP = '┆'

var week_day_col          = 16   # cell width; set via Configure()
var cfg_week_display_type = 'eu' # 'eu' | 'us' | 'work'; set via Configure()
var manage_events_func = ''

# Maps body-buffer line number (as string) → list of
# {first, last, event} screen-column spans, one per rendered event block on
# that line.  A day column holds several spans when events conflict.
# Rebuilt on every RenderWeekView call.
var appt_line_map: dict<list<dict<any>>> = {}
var allday_line_map: dict<dict<any>> = {}
var slot_line_time: dict<dict<number>> = {}
var displayed_dates: list<string> = []

# Set the active diary's provider function names.  Installing a provider does
# not touch the week cache: frontend.ConfigureProvider decides when the cache
# is stale, because it alone knows whether the active diary really changed.
export def SetProviderFuncs(fetch_name: string, manage_name: string)
  t:cal_fetch_events_func = fetch_name
  manage_events_func = manage_name
enddef

# Drop every cached week.  Called when the active diary changes and by
# :CalendarRefresh.
export def ClearCache()
  appointments.Clear()
  appt_line_map = {}
enddef

# Configure display type and cell width.  Called from frontend.InitVariables.
export def Configure(display_type: string, cell_width: number)
  var valid = ['eu', 'us', 'work']
  cfg_week_display_type = index(valid, tolower(display_type)) >= 0
    ? tolower(display_type)
    : 'eu'
  week_day_col = max([8, cell_width])
enddef

# Return the number of displayed day columns.
def NumDays(): number
  return cfg_week_display_type ==# 'work' ? 5 : 7
enddef

# Return the dates shown for the configured display type.
# EU/work weeks are ISO Monday-based; US weeks are chronological Sunday-based.
def DisplayWdays(year: number, month: number, day: number,
                 wdays: list<dict<any>>): list<dict<any>>
  if cfg_week_display_type ==# 'work'
    return wdays[0 : 4]                      # Mon–Fri
  elseif cfg_week_display_type ==# 'us'
    var sunday_jdn = backend.DateToJDN(year, month, day)
      - (backend.WeekdayForDate(year, month, day) % 7)
    return range(7)->mapnew((i, _) => backend.JDNToDate(sunday_jdn + i))
  endif
  return wdays                                # eu: Mon–Sun
enddef

# Return full day-name labels in display order.
def DayFullLabels(): list<string>
  if cfg_week_display_type ==# 'work'
    return WEEK_DAY_FULL[0 : 4]
  elseif cfg_week_display_type ==# 'us'
    return [WEEK_DAY_FULL[6]] + WEEK_DAY_FULL[0 : 5]
  endif
  return WEEK_DAY_FULL
enddef

# Return the displayed week's start date for use as an appointment cache key.
def WeekCacheKey(year: number, month: number, day: number): string
  var start = cfg_week_display_type ==# 'us'
    ? backend.JDNToDate(backend.DateToJDN(year, month, day)
        - (backend.WeekdayForDate(year, month, day) % 7))
    : backend.WeekDays(year, month, day)[0]
  return printf('%04d-%02d-%02d', start.year, start.month, start.day)
enddef

def FetchRange(year: number, month: number, day: number): dict<string>
  var days = DisplayWdays(year, month, day,
    backend.WeekDays(year, month, day))
  var first = days[0]
  var last = days[-1]
  var after = backend.JDNToDate(
    backend.DateToJDN(last.year, last.month, last.day) + 1)
  return {
    start: printf('%04d-%02d-%02d', first.year, first.month, first.day),
    end: printf('%04d-%02d-%02d', after.year, after.month, after.day),
  }
enddef

# ─── Render helpers ──────────────────────────────────────────────────────────

def MonthName(month: number): string
  return backend.month_num_to_str[printf('%02d', month)]
enddef

def WeekSepLine(join_char: string, n_days: number): string
  return repeat('─', WEEK_TIME_COL) .. join_char ..
    join(range(n_days)->mapnew((_, _) => repeat('─', week_day_col)), join_char)
enddef

# Cut text down to at most `width` screen cells.
def TruncateToWidth(text: string, width: number): string
  if width <= 0
    return ''
  endif
  var out = text
  while !empty(out) && strdisplaywidth(out) > width
    out = strcharpart(out, 0, strcharlen(out) - 1)
  endwhile
  return out
enddef

# Pad/truncate a cell to exactly `width` screen cells.  printf()'s field width
# counts bytes, so it silently shrinks cells containing non-ASCII text and
# misaligns the whole grid; cell geometry must be measured in screen cells.
def FitCell(text: string, width: number): string
  var out = TruncateToWidth(text, width)
  return out .. repeat(' ', width - strdisplaywidth(out))
enddef

def WeekDataRow(time_cell: string, day_cells: list<string>): string
  var tc = FitCell(time_cell, WEEK_TIME_COL)
  return tc .. '│' .. join(day_cells->mapnew(
    (_, c) => FitCell(c, week_day_col)), '│')
enddef

def CellText(text: string): string
  var max_len = week_day_col - 1
  var content = strdisplaywidth(text) > max_len
    ? TruncateToWidth(text, max_len - 3) .. '...'
    : text
  return $' {content}'
enddef

# Shorten text to `width` cells, marking the cut with '...'.
def Ellipsis(text: string, width: number): string
  if width <= 3
    return TruncateToWidth(text, width)
  endif
  return TruncateToWidth(text, width - 3) .. '...'
enddef

# Shorten only when the text does not already fit.
def FitOrEllipsis(text: string, width: number): string
  return strdisplaywidth(text) <= width ? text : Ellipsis(text, width)
enddef

# Convert 'HH:MM' to the index of the half-hour row that contains it.
def TimeToRow(hhmm: string): number
  var parts = split(hhmm, ':')
  if len(parts) < 2
    return 0
  endif
  return str2nr(parts[0]) * ROWS_PER_HOUR + (str2nr(parts[1]) >= 30 ? 1 : 0)
enddef

# Convert 'HH:MM' to the first row *after* the event, rounding a partial half
# hour up so a 09:00–10:15 event still covers the 10:00 row.
def TimeToEndRow(hhmm: string): number
  var parts = split(hhmm, ':')
  if len(parts) < 2
    return 0
  endif
  var minutes = str2nr(parts[0]) * 60 + str2nr(parts[1])
  return (minutes + 29) / 30
enddef

# Return [start_row, span] for an event, clamped to the visible day.
# Events that end on a later day (or carry a malformed end) run to midnight.
def EventRows(ev: dict<any>): list<number>
  var start_row = TimeToRow(get(ev, 'start', '00:00'))
  var end_row   = TimeToEndRow(get(ev, 'end', ''))
  var same_day  = empty(get(ev, 'end_date', ''))
    || get(ev, 'end_date', '') ==# strpart(get(ev, 'provider_start', ''), 0, 10)
  if !same_day || end_row <= start_row
    end_row = TOTAL_ROWS
  endif
  return [start_row, max([1, min([end_row, TOTAL_ROWS]) - start_row])]
enddef

# Place a day's events into lanes so conflicting events sit side by side.
# Greedy interval colouring: an event reuses the leftmost lane that is already
# free at its start row, so non-overlapping events share a lane.
# Returns a list of {event, row, span, lane}.
def AssignLanes(evs: list<dict<any>>): list<dict<any>>
  var ordered = SortedByRows(evs)
  var placed: list<dict<any>> = []
  var lane_free: list<number> = []
  for ev in ordered
    var rows = EventRows(ev)
    var lane = -1
    for i in range(len(lane_free))
      if lane_free[i] <= rows[0]
        lane = i
        break
      endif
    endfor
    if lane < 0
      lane_free->add(0)
      lane = len(lane_free) - 1
    endif
    lane_free[lane] = rows[0] + rows[1]
    placed->add({event: ev, row: rows[0], span: rows[1], lane: lane})
  endfor
  return placed
enddef

# Order events by start row, longest first — the order lane assignment and
# cluster detection both need.
def SortedByRows(evs: list<dict<any>>): list<dict<any>>
  var ordered = copy(evs)
  sort(ordered, (a, b) => {
    var ra = EventRows(a)
    var rb = EventRows(b)
    return ra[0] != rb[0] ? ra[0] - rb[0] : rb[1] - ra[1]
  })
  return ordered
enddef

# Group a day's events into conflict clusters: maximal runs of events whose
# row ranges overlap, directly or through a common neighbour.  Lanes are a
# property of the cluster and not of the day, so an event that conflicts with
# nothing keeps the full width of its column.
# Returns a list of {start, end, events} with end exclusive.
def ConflictClusters(evs: list<dict<any>>): list<dict<any>>
  var clusters: list<dict<any>> = []
  for ev in SortedByRows(evs)
    var rows = EventRows(ev)
    var ev_end = rows[0] + rows[1]
    if !empty(clusters) && rows[0] < clusters[-1].end
      clusters[-1].events->add(ev)
      clusters[-1].end = max([clusters[-1].end, ev_end])
    else
      clusters->add({start: rows[0], end: ev_end, events: [ev]})
    endif
  endfor
  return clusters
enddef

# Split a day cell of `total` cells into `n` lane widths, allowing for the
# LANE_SEP characters between them.  Leftover cells go to the leftmost lanes.
def LaneWidths(total: number, n: number): list<number>
  var usable = total - (n - 1)
  var base   = usable / n
  var extra  = usable % n
  var widths: list<number> = []
  for i in range(n)
    widths->add(base + (i < extra ? 1 : 0))
  endfor
  return widths
enddef

# Word-wrap `text` into exactly `max_lines` lines of at most `width` cells.
# When text is left over the last line is ellipsised, so the '...' always
# falls in the title and never in the '(organizer)' line below it.
def WrapTitle(text: string, width: number, max_lines: number): list<string>
  var lines: list<string> = []
  if max_lines <= 0 || width <= 0
    return lines
  endif
  var words = split(text, '\s\+')
  var cur = ''
  var i = 0
  while i < len(words) && len(lines) < max_lines
    var candidate = empty(cur) ? words[i] : $'{cur} {words[i]}'
    if strdisplaywidth(candidate) <= width
      cur = candidate
      i += 1
    elseif empty(cur)
      # A single word wider than the lane: hard-break it.
      var head = TruncateToWidth(words[i], width)
      words[i] = strcharpart(words[i], strcharlen(head))
      lines->add(head)
    else
      lines->add(cur)
      cur = ''
    endif
  endwhile
  if len(lines) < max_lines && !empty(cur)
    lines->add(cur)
    cur = ''
  endif
  if (!empty(cur) || i < len(words)) && !empty(lines)
    lines[-1] = Ellipsis(lines[-1], width)
  endif
  while len(lines) < max_lines
    lines->add('')
  endwhile
  return lines
enddef

# Render one event as exactly `span` cell strings: the wrapped title, then
# '(organizer)' on the last line.  A single-row event shows the title only —
# there is no line left for the organizer.
def EventCellLines(ev: dict<any>, span: number, width: number): list<string>
  var text_width = width - 1
  var organizer  = get(ev, 'organizer', '')
  var with_org   = span > 1 && !empty(organizer)
  var title_rows = with_org ? span - 1 : span
  var cells: list<string> = []
  for line in WrapTitle(get(ev, 'subject', ''), text_width, title_rows)
    cells->add(empty(line) ? '' : $' {line}')
  endfor
  if with_org
    cells->add($' {FitOrEllipsis($"({organizer})", text_width)}')
  endif
  return cells
enddef

# Join one row of lane texts into a full day cell of exactly week_day_col
# cells.  Rows outside a conflict cluster arrive as a single full-width lane,
# so no lane rule is drawn where there is nothing to separate.
def DayCellStr(texts: list<string>, widths: list<number>): string
  var parts: list<string> = []
  for i in range(len(texts))
    parts->add(FitCell(texts[i], widths[i]))
  endfor
  return join(parts, LANE_SEP)
enddef

def WeekHeaderStr(wdays: list<dict<any>>, week_num: number): string
  # Format "DD Mon - DD Mon YYYY (week N)" or "DD - DD Mon YYYY" when same month.
  var first = wdays[0]
  var last  = wdays[-1]
  if first.month == last.month
    return printf('%d - %d %s %d (week %d)',
      first.day, last.day, MonthName(first.month), first.year, week_num)
  endif
  return printf('%d %s - %d %s %d (week %d)',
    first.day, MonthName(first.month)[: 2],
    last.day,  MonthName(last.month)[: 2],
    last.year, week_num)
enddef

# Render banner rows for all-day events above the hour grid.
# One row per event; each row spans its start→end columns with dashes.
# Outlook all-day end is exclusive (next-day midnight), so end_date is
# already adjusted by 1 day before being stored.
# wdays must already be in display order (output of DisplayWdays).
def AllDayRows(events: dict<any>, wdays: list<dict<any>>): list<string>
  allday_line_map = {}
  var allday = get(events, 'allday', [])
  if empty(allday)
    return []
  endif

  var n_days     = len(wdays)
  var week_start = printf('%04d-%02d-%02d', wdays[0].year,    wdays[0].month,    wdays[0].day)
  var week_end   = printf('%04d-%02d-%02d', wdays[-1].year,   wdays[-1].month,   wdays[-1].day)

  var date_to_col: dict<number> = {}
  for i in range(n_days)
    var d = wdays[i]
    date_to_col[printf('%04d-%02d-%02d', d.year, d.month, d.day)] = i
  endfor

  var lines: list<string> = []
  for ev in allday
    var ev_start = get(ev, 'start_date', week_start)
    var ev_end   = get(ev, 'end_date',   week_end)

    if ev_end < week_start || ev_start > week_end
      continue
    endif

    var start_col = has_key(date_to_col, ev_start) ? date_to_col[ev_start] : 0
    var end_col   = has_key(date_to_col, ev_end)   ? date_to_col[ev_end]   : n_days - 1

    var left_pad   = repeat(' ', WEEK_TIME_COL + 1 + start_col * (week_day_col + 1))
    var cell_width = (end_col - start_col + 1) * (week_day_col + 1) - 1
    var subj = get(ev, 'subject', '')
    var org  = get(ev, 'organizer', '')
    var label = $'{subj} ({org}) '
    var fill_len = cell_width - strcharlen(label)
    var content = fill_len > 0
      ? label .. repeat('-', fill_len)
      : strcharpart(label, 0, cell_width)
    lines->add($'{left_pad}{content}|')
    var first_col = strlen(left_pad) + 1
    allday_line_map[string(len(lines))] = {
      event: ev,
      first_col: first_col,
      last_col: strlen(left_pad .. content),
    }
  endfor
  return lines
enddef

# ─── Public API ──────────────────────────────────────────────────────────────

# Set up two stacked buffers in the window currently holding tabnew_bufnr:
#   __WeekHeader__  (top, fixed height)  — all-day banner, day labels (no statusline)
#   __WeekView__    (bottom, scrollable) — hour grid (week title in statusline)
# Returns true on success.
export def OpenWeekViewWindow(tabnew_bufnr: number): bool
  var winnr = bufwinnr(tabnew_bufnr)
  if winnr <= 0
    return false
  endif
  win_gotoid(win_getid(winnr))

  # Top window — header (no statusline; fixed height)
  var header_buf = bufnr(WEEK_HDR_BUF_NAME)
  if header_buf > 0
    execute $'buffer {header_buf}'
  else
    execute $'file {WEEK_HDR_BUF_NAME}'
  endif
  setlocal buftype=nofile bufhidden=delete noswapfile nowrap nobuflisted nomodified nomodifiable
  setlocal textwidth=0 colorcolumn=0 fdc=0 nonu winfixheight
  if has('+relativenumber') || exists('+relativenumber')
    setlocal nornu
  endif
  if exists('+winfixbuf')
    setlocal winfixbuf
  endif
  if exists('+winhighlight')
    setlocal winhighlight=StatusLine:Normal,StatusLineNC:Normal
  endif
  WeekHeaderBuildKeymap()

  # Bottom window — body (scrollable; week title shown in statusline)
  var body_buf = bufnr(WEEK_BUF_NAME)
  if body_buf > 0
    execute $'belowright sbuffer {body_buf}'
  else
    belowright split
    enew
    execute $'file {WEEK_BUF_NAME}'
  endif
  setlocal buftype=nofile bufhidden=delete noswapfile nowrap nobuflisted nomodified nomodifiable
  setlocal textwidth=0 colorcolumn=0 fdc=0 nonu
  if has('+relativenumber') || exists('+relativenumber')
    setlocal nornu
  endif
  if exists('+winfixbuf')
    setlocal winfixbuf
  endif

  WeekViewBuildKeymap()
  return true
enddef

# Render (or re-render) the week view for the week containing (year, month, day).
# events is keyed 'YYYY-MM-DD' → list of event dicts, plus 'allday' → list.
# Header buffer receives: title, all-day banner rows, separator, day labels, separator.
# Body buffer receives: the scrollable hour grid.
export def RenderWeekView(year: number, month: number, day: number, events: dict<any>)
  var hdr_buf  = bufnr(WEEK_HDR_BUF_NAME)
  var body_buf = bufnr(WEEK_BUF_NAME)
  if hdr_buf <= 0 || body_buf <= 0
    return
  endif

  t:cal_week_key = WeekCacheKey(year, month, day)
  var wdays         = backend.WeekDays(year, month, day)
  var display_wdays = DisplayWdays(year, month, day, wdays)
  var n_days        = len(display_wdays)
  var week_num      = backend.ISOWeekNum(year, month, day)
  var day_labels_full = DayFullLabels()

  # ── Header ────────────────────────────────────────────────────────────────
  var title = WeekHeaderStr(display_wdays, week_num)
  var hdr_lines: list<string> = []

  var allday_rows = AllDayRows(events, display_wdays)
  for row in allday_rows
    hdr_lines->add(row)
  endfor

  hdr_lines->add(WeekSepLine('┬', n_days))
  var day_labels = display_wdays->mapnew(
    (i, d) => CellText(printf('%d, %s', d.day, day_labels_full[i])))
  var tz_raw = strftime('%z')  # e.g. '+0200' or '-0500'
  var tz_label = tz_raw =~# '^[+-]\d\{4}$'
    ? $'UTC{tz_raw[0 : 2]}:{tz_raw[3 : 4]}'
    : 'UTC'
  hdr_lines->add(WeekDataRow($' {tz_label}', day_labels))
  hdr_lines->add(WeekSepLine('┼', n_days))

  setbufvar(hdr_buf, '&modifiable', 1)
  deletebufline(hdr_buf, 1, '$')
  setbufline(hdr_buf, 1, hdr_lines)
  setbufvar(hdr_buf, '&modified', 0)
  setbufvar(hdr_buf, '&modifiable', 0)

  # Resize header and apply today-column highlight.
  var hdr_wins = win_findbuf(hdr_buf)
  if !empty(hdr_wins)
    win_execute(hdr_wins[0], $'resize {len(hdr_lines)}')
    var today_key = WeekCacheKey(str2nr(strftime('%Y')), str2nr(strftime('%m')), str2nr(strftime('%d')))
    highlights.WeekHeader(hdr_wins[0], today_key)
  endif

  # ── Body (hour grid) ──────────────────────────────────────────────────────
  var body_lines: list<string> = []
  appt_line_map = {}
  slot_line_time = {}
  displayed_dates = display_wdays->mapnew((_, d) =>
    printf('%04d-%02d-%02d', d.year, d.month, d.day))

  # Lay every day out first.  Lanes belong to a conflict cluster, so rows
  # inside a cluster share its geometry and stay aligned, while everything
  # else keeps the full width of the column.
  var cell_widths: list<list<list<number>>> = []
  var cell_text:  list<list<list<string>>> = []
  var cell_event: list<list<list<dict<any>>>> = []
  for date_key in displayed_dates
    var rows_width: list<list<number>> = []
    var rows_text:  list<list<string>> = []
    var rows_event: list<list<dict<any>>> = []
    for _ in range(TOTAL_ROWS)
      rows_width->add([week_day_col])
      rows_text->add([''])
      rows_event->add([{}])
    endfor

    for cluster in ConflictClusters(get(events, date_key, []))
      var placed = AssignLanes(cluster.events)
      var n_lanes = 1
      for p in placed
        if p.lane + 1 > n_lanes
          n_lanes = p.lane + 1
        endif
      endfor
      var widths = LaneWidths(week_day_col, n_lanes)

      # Give every row the cluster spans the same lanes, so an event keeps its
      # width from its first line to its last even where the conflict has ended.
      var last_row = min([cluster.end, TOTAL_ROWS]) - 1
      for r in range(cluster.start, last_row)
        var blank_text: list<string> = []
        var blank_event: list<dict<any>> = []
        for _l in range(n_lanes)
          blank_text->add('')
          blank_event->add({})
        endfor
        rows_width[r] = widths
        rows_text[r] = blank_text
        rows_event[r] = blank_event
      endfor

      for p in placed
        var lines = EventCellLines(p.event, p.span, widths[p.lane])
        for k in range(len(lines))
          var r = p.row + k
          if r < TOTAL_ROWS
            rows_text[r][p.lane] = lines[k]
            # Every row of the block resolves to the event, including rows whose
            # text is blank, so the cursor finds it anywhere inside the block.
            rows_event[r][p.lane] = p.event
          endif
        endfor
      endfor
    endfor

    cell_widths->add(rows_width)
    cell_text->add(rows_text)
    cell_event->add(rows_event)
  endfor

  var hour7_line = 1
  for h in range(0, 23)
    if h == 7
      hour7_line = len(body_lines) + 1 + &scrolloff
    endif
    for half in range(ROWS_PER_HOUR)
      var r = h * ROWS_PER_HOUR + half
      var day_cells: list<string> = []
      for di in range(n_days)
        day_cells->add(DayCellStr(cell_text[di][r], cell_widths[di][r]))
      endfor
      var lnum = len(body_lines) + 1
      body_lines->add(WeekDataRow(half == 0 ? printf('%3d', h) : '', day_cells))
      slot_line_time[string(lnum)] = {hour: h, minute: half * 30}

      # Record the screen-column span of every event block on this line.
      var spans: list<dict<any>> = []
      for di in range(n_days)
        var lane_start = WEEK_TIME_COL + 2 + di * (week_day_col + 1)
        for l in range(len(cell_widths[di][r]))
          if !empty(cell_event[di][r][l])
            spans->add({
              first: lane_start,
              last: lane_start + cell_widths[di][r][l] - 1,
              event: cell_event[di][r][l],
            })
          endif
          lane_start += cell_widths[di][r][l] + 1
        endfor
      endfor
      if !empty(spans)
        appt_line_map[string(lnum)] = spans
      endif
    endfor
    body_lines->add(WeekSepLine('┼', n_days))
  endfor

  setbufvar(body_buf, '&modifiable', 1)
  deletebufline(body_buf, 1, '$')
  setbufline(body_buf, 1, body_lines)
  setbufvar(body_buf, '&modified', 0)
  setbufvar(body_buf, '&modifiable', 0)

  # Set the week title in the body window statusline and scroll to hour 7.
  var body_wins = win_findbuf(body_buf)
  if !empty(body_wins)
    win_execute(body_wins[0], $'&l:statusline = "{title}"')
    win_execute(body_wins[0], $'cursor({hour7_line}, 1) | normal! zt')
  endif
enddef

# Navigate the week view to the week containing (year, month, day).
# FetchEvents renders from the cache when the week is already known, so
# changing week only reaches the provider the first time it is displayed.
export def NavigateWeekView(year: number, month: number, day: number)
  var cache_key = WeekCacheKey(year, month, day)
  # Set t:cal_week_key before the hook fires so LoadAppointments caches correctly.
  t:cal_week_key = cache_key
  FetchEvents(year, month, day)
  if !appointments.Has(cache_key)
    RenderWeekView(year, month, day, {})
  endif
enddef

# Call the active diary's fetch_events hook for the displayed date range.
# The hook must return the path it wrote to on success, '' on failure.
# Cached weeks are re-rendered without calling the provider: opening or
# toggling the calendar must not pay for a fetch.  Pass force = true (only
# :CalendarRefresh does) to bypass the cache and pull fresh data.
export def FetchEvents(year: number = -1, month: number = -1,
    day: number = -1, force: bool = false)
  if empty(get(t:, 'cal_fetch_events_func', ''))
      || !exists($'*{t:cal_fetch_events_func}')
    return
  endif
  var stored_key = get(t:, 'cal_week_key', '')
  var use_stored = year <= 0 && month <= 0 && day <= 0
    && stored_key =~# '^\d\{4}-\d\{2}-\d\{2}$'
  var fy = year > 0
    ? year
    : use_stored ? str2nr(stored_key[0 : 3]) : str2nr(strftime('%Y'))
  var fm = month > 0
    ? month
    : use_stored ? str2nr(stored_key[5 : 6]) : str2nr(strftime('%m'))
  var fd = day > 0
    ? day
    : use_stored ? str2nr(stored_key[8 : 9]) : str2nr(strftime('%d'))
  t:cal_week_key = WeekCacheKey(fy, fm, fd)
  if !force && appointments.Has(t:cal_week_key)
    RenderWeekView(fy, fm, fd, appointments.Get(t:cal_week_key))
    return
  endif
  var path = function(t:cal_fetch_events_func)(FetchRange(fy, fm, fd))
  if !empty(path)
    LoadAppointments(path)
  endif
enddef

# Parse the JSON at path, cache events for the current week, and re-render.
# JSON format: list of {start, end, subject, organizer, location, body}.
def LoadAppointments(path: string)
  var loaded = appointments.LoadFile(path)
  if !loaded.ok
    return
  endif
  var events: dict<list<any>> = loaded.events

  var stored_key = get(t:, 'cal_week_key', '')
  var key = empty(stored_key)
    ? WeekCacheKey(str2nr(strftime('%Y')), str2nr(strftime('%m')), str2nr(strftime('%d')))
    : stored_key
  var ky = str2nr(key[0 : 3])
  var km = str2nr(key[5 : 6])
  var kd = str2nr(key[8 : 9])
  appointments.Put(key, events)
  RenderWeekView(ky, km, kd, events)
enddef

# Re-fetch appointments for the currently displayed week.
# Drops the whole cache so every week is pulled fresh from the provider the
# next time it is displayed; the visible week is refetched immediately.
export def CalendarRefresh()
  if empty(get(t:, 'cal_fetch_events_func', ''))
    return
  endif
  var stored_key = get(t:, 'cal_week_key', '')
  var key = empty(stored_key)
    ? WeekCacheKey(str2nr(strftime('%Y')), str2nr(strftime('%m')), str2nr(strftime('%d')))
    : stored_key
  appointments.Clear()
  var ky = str2nr(key[0 : 3])
  var km = str2nr(key[5 : 6])
  var kd = str2nr(key[8 : 9])
  FetchEvents(ky, km, kd, true)
  RescheduleReminders()
enddef

# Scan cached appointments for today's meetings and reschedule reminder timers.
# Called explicitly after every event fetch — the authoritative place to
# trigger reminders so the scheduling is always visible and not a buried
# side effect of LoadAppointments.
export def RescheduleReminders()
  var today_key = strftime('%Y-%m-%d')
  reminder.Schedule(today_key, appointments.EventsOn(today_key))
enddef

# Return the appointment dict under the cursor in the __WeekView__ buffer,
# or {} if the cursor is on a separator, the time column, or an empty cell.
# Resolution uses the screen-column spans recorded while rendering, so it is
# correct even where conflicting events split a day into narrow lanes.
export def GetEventAtCursor(): dict<any>
  if bufname('%') ==# WEEK_HDR_BUF_NAME
    var banner = get(allday_line_map, string(line('.')), {})
    return !empty(banner)
        && col('.') >= banner.first_col
        && col('.') <= banner.last_col
      ? banner.event
      : {}
  endif
  var spans = get(appt_line_map, string(line('.')), [])
  if empty(spans)
    return {}
  endif
  # Screen columns are used because '│' separators and event text may be
  # multibyte: byte columns would drift away from the rendered cell layout.
  var vcol = virtcol('.')
  for span in spans
    if vcol >= span.first && vcol <= span.last
      return span.event
    endif
  endfor
  return {}
enddef

# Return {date, hour, minute} for the half-hour cell under the cursor.
export def GetSlotAtCursor(): dict<any>
  var key = string(line('.'))
  if !has_key(slot_line_time, key) || virtcol('.') <= WEEK_TIME_COL + 1
    return {}
  endif
  var col_idx = (virtcol('.') - WEEK_TIME_COL - 2) / (week_day_col + 1)
  if col_idx < 0 || col_idx >= len(displayed_dates)
    return {}
  endif
  var slot = slot_line_time[key]
  return {date: displayed_dates[col_idx], hour: slot.hour, minute: slot.minute}
enddef

# Return [date, hour, minute] one hour after the given slot.
def SlotEnd(date_key: string, hour: number, minute: number): list<any>
  var minutes = hour * 60 + minute + 60
  if minutes < 24 * 60
    return [date_key, minutes / 60, minutes % 60]
  endif
  var parts = split(date_key, '-')
  var next = backend.JDNToDate(backend.DateToJDN(
    str2nr(parts[0]), str2nr(parts[1]), str2nr(parts[2])) + 1)
  minutes -= 24 * 60
  return [printf('%04d-%02d-%02d', next.year, next.month, next.day),
    minutes / 60, minutes % 60]
enddef

def ComposeAppointment()
  var slot = GetSlotAtCursor()
  if empty(slot)
    echo '[Calendar] Place the cursor inside a day/hour cell.'
    return
  endif
  if empty(manage_events_func) || !exists($'*{manage_events_func}')
    echoerr '[Calendar] No manage_events hook is configured.'
    return
  endif
  var end_slot = SlotEnd(slot.date, slot.hour, slot.minute)
  var start = $'{slot.date} {printf("%02d:%02d", slot.hour, slot.minute)}'
  var end = $'{end_slot[0]} {printf("%02d:%02d", end_slot[1], end_slot[2])}'
  var result = function(manage_events_func)({
    action: 'create',
    start: start,
    end: end,
  })
  if type(result) == v:t_bool && !result
    echoerr '[Calendar] Could not open the appointment editor.'
  endif
enddef

def EditAppointment()
  var event = GetEventAtCursor()
  if empty(event)
    echo '[Calendar] Place the cursor on an appointment.'
    return
  endif
  var event_id = get(event, 'id', '')
  if empty(event_id)
    echoerr '[Calendar] This appointment has no provider identifier.'
    return
  endif
  if empty(manage_events_func) || !exists($'*{manage_events_func}')
    echoerr '[Calendar] No manage_events hook is configured.'
    return
  endif
  var result = function(manage_events_func)({
    action: 'edit',
    id: event_id,
  })
  if type(result) == v:t_bool && !result
    echoerr '[Calendar] Could not open this appointment for editing.'
  endif
enddef

# Single entry point for the `m` mapping: edit the event under the cursor,
# or create a new one at the selected slot when there is none.
def ManageEventAtCursor()
  if empty(GetEventAtCursor())
    ComposeAppointment()
  else
    EditAppointment()
  endif
enddef

def EventAction(action: string)
  var event = GetEventAtCursor()
  if empty(event)
    echo '[Calendar] Place the cursor on an event.'
    return
  endif
  var event_id = get(event, 'id', '')
  if empty(event_id)
    echoerr '[Calendar] This event has no provider identifier.'
    return
  endif
  if empty(manage_events_func) || !exists($'*{manage_events_func}')
    echoerr '[Calendar] No manage_events hook is configured.'
    return
  endif
  var result = function(manage_events_func)({
    action: action,
    id: event_id,
    start: get(event, 'provider_start', ''),
  })
  if type(result) == v:t_bool && !result
    echoerr $'[Calendar] Could not {action} this event.'
  endif
enddef

# ─── Week view keymaps and popups ────────────────────────────────────────────

# Collapse consecutive blank lines into one, trim trailing whitespace per line,
# and strip leading/trailing blank lines.  Intentional single blank lines
# (paragraph separators) are preserved.
def CompactBody(body: string): list<string>
  var lines = split(body, "\n")
    ->mapnew((_, l) => substitute(l, '\s\+$', '', ''))
  var out: list<string> = []
  var prev_blank = false
  for l in lines
    var is_blank = l !~ '\S'
    if !(is_blank && prev_blank)
      out->add(l)
    endif
    prev_blank = is_blank
  endfor
  while !empty(out) && out[0]  !~ '\S' | remove(out, 0)   | endwhile
  while !empty(out) && out[-1] !~ '\S' | remove(out, -1)  | endwhile
  return out
enddef

# Truncate lines at the first line that looks like meeting-invite boilerplate:
# a rule line (5+ underscores / dashes / equals) or a conference join URL.
# Applied to popup previews only; the full split view keeps the entire body.
def StripBoilerplate(lines: list<string>): list<string>
  const pat = '^\s*[_\-=]\{5,}\s*$'
    .. '\|teams\.microsoft\.com'
    .. '\|zoom\.us/j/'
    .. '\|meet\.google\.com'
    .. '\|webex\.com/meet'
    .. '\|^\s*CAUTION:'
  for i in range(len(lines))
    if lines[i] =~# pat
      # Strip any trailing blank lines left after the cut.
      var result = lines[0 : i - 1]
      while !empty(result) && result[-1] !~ '\S'
        remove(result, -1)
      endwhile
      return result
    endif
  endfor
  return lines
enddef

# Any key closes the appointment detail popup.
def AppointmentDetailFilter(id: number, key: string): bool
  popup_close(id)
  return true
enddef

# Show a popup_atcursor with a brief preview of the event under the cursor.
# Body is limited to 10 non-empty lines.  Does nothing on empty cells.
def ShowAppointmentDetails()
  var appt = GetEventAtCursor()
  if empty(appt)
    return
  endif
  var lines: list<string> = []
  var start_t = get(appt, 'start',     '')
  var end_t   = get(appt, 'end',       '')
  var org     = get(appt, 'organizer', '')
  var loc     = get(appt, 'location',  '')
  var req     = get(appt, 'required_attendees', '')
  var opt     = get(appt, 'optional_attendees', '')
  var body    = get(appt, 'body',      '')

  if !empty(start_t) || !empty(end_t)
    lines->add($' {start_t} – {end_t}')
  endif
  if !empty(org)
    lines->add($' Organizer:  {org}')
  endif
  if !empty(loc)
    lines->add($' Location:   {loc}')
  endif
  if !empty(req)
    lines->add($' Required:   {req}')
  endif
  if !empty(opt)
    lines->add($' Optional:   {opt}')
  endif
  if !empty(body)
    var compact = StripBoilerplate(CompactBody(body))
    if !empty(compact)
      lines->add(' ')
      for bline in compact[: 9]
        lines->add($' {bline}')
      endfor
      if len(compact) > 10
        lines->add($' … ({len(compact) - 10} more lines)')
      endif
    endif
  endif

  popup_atcursor(lines, {
    title:        $' {get(appt, "subject", "")} ',
    border:       [1, 1, 1, 1],
    borderchars:  ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    filter:       AppointmentDetailFilter,
    mapping:      0,
  })
enddef

export const APPT_BUF_NAME = '__Appointment__'

# Open the full appointment content in a horizontal split below.
# Wipes any previous __Appointment__ buffer first.
# <Esc> or q closes the window.  Does nothing on empty cells.
def OpenAppointmentBody()
  var appt = GetEventAtCursor()
  if empty(appt)
    return
  endif

  var bn = bufnr(APPT_BUF_NAME)
  if bn > 0
    execute $'bwipeout! {bn}'
  endif

  var subj  = get(appt, 'subject',   '')
  var start_t = get(appt, 'start',   '')
  var end_t   = get(appt, 'end',     '')
  var org   = get(appt, 'organizer', '')
  var loc   = get(appt, 'location',  '')
  var req   = get(appt, 'required_attendees', '')
  var opt   = get(appt, 'optional_attendees', '')
  var body  = get(appt, 'body',      '')

  var lines: list<string> = []
  lines->add($'Subject:   {subj}')
  lines->add($'Time:      {start_t} – {end_t}')
  if !empty(org) | lines->add($'Organizer: {org}') | endif
  if !empty(loc) | lines->add($'Location:  {loc}') | endif
  if !empty(req) | lines->add($'Required Attendees: {req}') | endif
  if !empty(opt) | lines->add($'Optional Attendees: {opt}') | endif
  lines->add(repeat('─', 60))
  lines->add('')
  if !empty(body)
    extend(lines, CompactBody(body))
  else
    lines->add('(no body)')
  endif

  belowright split
  enew
  execute $'file {APPT_BUF_NAME}'
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nomodifiable textwidth=0 colorcolumn=0 fdc=0 nonu wrap
  if has('+relativenumber') || exists('+relativenumber')
    setlocal nornu
  endif
  setlocal modifiable
  setline(1, lines)
  setlocal nomodified nomodifiable

  nnoremap <silent> <buffer> q     <Cmd>bwipeout!<CR>
  nnoremap <silent> <buffer> <Esc> <Cmd>bwipeout!<CR>
enddef

# Set buffer-local keymaps for the __WeekView__ body buffer.
def WeekViewBuildKeymap()
  nnoremap <silent> <buffer> K         <ScriptCmd>ShowAppointmentDetails()<CR>
  nnoremap <silent> <buffer> <CR>      <ScriptCmd>OpenAppointmentBody()<CR>
  nnoremap <silent> <buffer> m         <ScriptCmd>ManageEventAtCursor()<CR>
  nnoremap <silent> <buffer> d         <ScriptCmd>EventAction('delete')<CR>
  nnoremap <silent> <buffer> a         <ScriptCmd>EventAction('accept')<CR>
  nnoremap <silent> <buffer> v         <ScriptCmd>EventAction('tentative')<CR>
  nnoremap <silent> <buffer> <C-Right> <ScriptCmd>frontend.WeekViewNavigate('next')<CR>
  nnoremap <silent> <buffer> <C-Left>  <ScriptCmd>frontend.WeekViewNavigate('prev')<CR>
  nnoremap <silent> <buffer> t         <ScriptCmd>frontend.WeekViewNavigate('today')<CR>
  nnoremap <silent> <buffer> <Tab>     <ScriptCmd>frontend.DiaryCycleNavigate('next')<cr>
  nnoremap <silent> <buffer> <S-Tab>   <ScriptCmd>frontend.DiaryCycleNavigate('prev')<cr>
  nnoremap <silent> <buffer> <F5>      <Cmd>CalendarRefresh<CR>
  nnoremap <silent> <buffer> ?         <ScriptCmd>help_popup.ShowWeek()<CR>
enddef

def WeekHeaderBuildKeymap()
  nnoremap <silent> <buffer> K         <ScriptCmd>ShowAppointmentDetails()<CR>
  nnoremap <silent> <buffer> <CR>      <ScriptCmd>OpenAppointmentBody()<CR>
  nnoremap <silent> <buffer> m         <ScriptCmd>ManageEventAtCursor()<CR>
  nnoremap <silent> <buffer> d         <ScriptCmd>EventAction('delete')<CR>
  nnoremap <silent> <buffer> a         <ScriptCmd>EventAction('accept')<CR>
  nnoremap <silent> <buffer> v         <ScriptCmd>EventAction('tentative')<CR>
  nnoremap <silent> <buffer> <Tab>     <Cmd>CalendarDiaryCycle next<CR>
  nnoremap <silent> <buffer> <S-Tab>   <Cmd>CalendarDiaryCycle prev<CR>
  nnoremap <silent> <buffer> <F5>      <Cmd>CalendarRefresh<CR>
  nnoremap <silent> <buffer> ?         <ScriptCmd>help_popup.ShowWeek()<CR>
enddef
