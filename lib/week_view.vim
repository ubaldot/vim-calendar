vim9script

import autoload "./backend.vim"

# Week view panel — self-contained module.
# Owns: WEEK_BUF_NAME, week_cache, connect_func.
# Date math is delegated to backend.vim.

export const WEEK_BUF_NAME = '__WeekView__'
export const WEEK_HDR_BUF_NAME = '__WeekHeader__'
const WEEK_TIME_COL = 8
const WEEK_DAY_COL  = 16
const WEEK_DAY_FULL = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

var week_cache: dict<dict<list<any>>> = {}
var connect_func = ''

# Set the active diary's connect function and clear the week cache.
# Must be called whenever the active diary changes.
export def SetConnectFunc(name: string)
  connect_func = name
  week_cache = {}
enddef

export def HasConnectFunc(): bool
  return !empty(connect_func)
enddef

# Return the Monday date string ('YYYY-MM-DD') for the ISO week containing
# the given date.  Used as key in week_cache.
def WeekCacheKey(year: number, month: number, day: number): string
  var days = backend.WeekDays(year, month, day)
  return printf('%04d-%02d-%02d', days[0].year, days[0].month, days[0].day)
enddef

# ─── Render helpers ──────────────────────────────────────────────────────────

def MonthName(month: number): string
  return backend.month_num_to_str[printf('%02d', month)]
enddef

def WeekSepLine(join_char: string): string
  return repeat('─', WEEK_TIME_COL) .. join_char ..
    join(range(7)->mapnew((_, _) => repeat('─', WEEK_DAY_COL)), join_char)
enddef

def WeekDataRow(time_cell: string, day_cells: list<string>): string
  var tc = printf('%-*s', WEEK_TIME_COL, strcharpart(time_cell, 0, WEEK_TIME_COL))
  return tc .. '│' .. join(day_cells->mapnew(
    (_, c) => printf('%-*s', WEEK_DAY_COL, strcharpart(c, 0, WEEK_DAY_COL))), '│')
enddef

def CellText(text: string): string
  var max_len = WEEK_DAY_COL - 1
  var content = strcharlen(text) > max_len
    ? strcharpart(text, 0, max_len - 3) .. '...'
    : text
  return ' ' .. content
enddef

def FormatEventCells(subject: string, organizer: string): list<string>
  return [CellText(subject), CellText('(' .. organizer .. ')')]
enddef

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

def FindHourEvents(events: dict<any>, date_key: string, hour: number): list<dict<any>>
  return copy(get(events, date_key, []))->filter(
    (_, ev) => str2nr(split(get(ev, 'start', '00:00'), ':')[0]) == hour)
enddef

# Highlight today's cell in the header window using a simple day pattern.
def HighlightWeekHeader(win_id: number)
  win_execute(win_id, 'clearmatches()')
  var today_day = str2nr(strftime('%d'))
  win_execute(win_id, $"call matchadd('CalWeekToday', ' {today_day},[^│]*')")
enddef

# Render banner rows for all-day events above the hour grid.
# One row per event; each row spans its start→end columns with dashes.
# Outlook all-day end is exclusive (next-day midnight), so end_date is
# already adjusted by 1 day before being stored.
def AllDayRows(events: dict<any>, wdays: list<dict<any>>): list<string>
  var allday = get(events, 'allday', [])
  if empty(allday)
    return []
  endif

  var week_start = printf('%04d-%02d-%02d', wdays[0].year, wdays[0].month, wdays[0].day)
  var week_end   = printf('%04d-%02d-%02d', wdays[6].year, wdays[6].month, wdays[6].day)

  var date_to_col: dict<number> = {}
  for i in range(7)
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
    var end_col   = has_key(date_to_col, ev_end)   ? date_to_col[ev_end]   : 6

    var left_pad   = repeat(' ', WEEK_TIME_COL + 1 + start_col * (WEEK_DAY_COL + 1))
    var cell_width = (end_col - start_col + 1) * (WEEK_DAY_COL + 1) - 1
    var label = get(ev, 'subject', '') .. ' (' .. get(ev, 'organizer', '') .. ') '
    var fill_len = cell_width - strcharlen(label)
    var content = fill_len > 0
      ? label .. repeat('-', fill_len)
      : strcharpart(label, 0, cell_width)
    lines->add(left_pad .. content .. '|')
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
  execute $'file {WEEK_HDR_BUF_NAME}'
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

  # Bottom window — body (scrollable; week title shown in statusline)
  belowright split
  enew
  execute $'file {WEEK_BUF_NAME}'
  setlocal buftype=nofile bufhidden=delete noswapfile nowrap nobuflisted nomodified nomodifiable
  setlocal textwidth=0 colorcolumn=0 fdc=0 nonu
  if has('+relativenumber') || exists('+relativenumber')
    setlocal nornu
  endif
  if exists('+winfixbuf')
    setlocal winfixbuf
  endif

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

  setbufvar(body_buf, 'week_key', WeekCacheKey(year, month, day))
  var wdays    = backend.WeekDays(year, month, day)
  var week_num = backend.ISOWeekNum(year, month, day)

  # ── Header ────────────────────────────────────────────────────────────────
  var title = WeekHeaderStr(wdays, week_num)
  var hdr_lines: list<string> = []

  var allday_rows = AllDayRows(events, wdays)
  for row in allday_rows
    hdr_lines->add(row)
  endfor

  hdr_lines->add(WeekSepLine('┬'))
  var day_labels = wdays->mapnew(
    (i, d) => CellText(printf('%d, %s', d.day, WEEK_DAY_FULL[i])))
  hdr_lines->add(WeekDataRow(' UTC+2', day_labels))
  hdr_lines->add(WeekSepLine('┼'))

  setbufvar(hdr_buf, '&modifiable', 1)
  deletebufline(hdr_buf, 1, '$')
  setbufline(hdr_buf, 1, hdr_lines)
  setbufvar(hdr_buf, '&modifiable', 0)

  # Resize header and apply today-column highlight.
  var hdr_wins = win_findbuf(hdr_buf)
  if !empty(hdr_wins)
    win_execute(hdr_wins[0], $'resize {len(hdr_lines)}')
    HighlightWeekHeader(hdr_wins[0])
  endif

  # ── Body (hour grid) ──────────────────────────────────────────────────────
  var body_lines: list<string> = []
  var hour7_line = 1
  for h in range(0, 23)
    if h == 7
      hour7_line = len(body_lines) + 1
    endif
    var day_evs: list<list<dict<any>>> = []
    for d in wdays
      day_evs->add(FindHourEvents(events,
        printf('%04d-%02d-%02d', d.year, d.month, d.day), h))
    endfor

    var slots = max([1] + day_evs->mapnew((_, evs) => len(evs)))
    for k in range(slots)
      var row1: list<string> = []
      var row2: list<string> = []
      for evs in day_evs
        if k < len(evs)
          var [l1, l2] = FormatEventCells(get(evs[k], 'subject', ''),
                                          get(evs[k], 'organizer', ''))
          row1->add(l1)
          row2->add(l2)
        else
          row1->add('')
          row2->add('')
        endif
      endfor
      body_lines->add(WeekDataRow(k == 0 ? printf('%3d', h) : '', row1))
      body_lines->add(WeekDataRow('', row2))
    endfor
    body_lines->add(WeekSepLine('┼'))
  endfor

  setbufvar(body_buf, '&modifiable', 1)
  deletebufline(body_buf, 1, '$')
  setbufline(body_buf, 1, body_lines)
  setbufvar(body_buf, '&modifiable', 0)

  # Set the week title in the body window statusline and scroll to hour 7.
  var body_wins = win_findbuf(body_buf)
  if !empty(body_wins)
    win_execute(body_wins[0], $'&l:statusline = "{title}"')
    win_execute(body_wins[0], $'cursor({hour7_line}, 1) | normal! zt')
  endif
enddef

# Navigate the week view to the week containing (year, month, day).
# Uses the cache if available; otherwise fires the connect hook and renders
# an empty grid (the hook will fill it in synchronously via LoadAppointments).
export def NavigateWeekView(year: number, month: number, day: number)
  var cache_key = WeekCacheKey(year, month, day)
  if has_key(week_cache, cache_key)
    RenderWeekView(year, month, day, week_cache[cache_key])
  else
    # Set b:week_key before the hook fires so LoadAppointments caches correctly.
    var body_buf = bufnr(WEEK_BUF_NAME)
    if body_buf > 0
      setbufvar(body_buf, 'week_key', cache_key)
    endif
    CallConnectHook(year, month, day)
    if !has_key(week_cache, cache_key)
      RenderWeekView(year, month, day, {})
    endif
  endif
enddef

# Call the active diary's connect hook for the given week date.
# The hook must return the path it wrote to on success, '' on failure.
export def CallConnectHook(year: number = -1, month: number = -1, day: number = -1)
  if empty(connect_func) || !exists('*' .. connect_func)
    return
  endif
  var fy = year  > 0 ? year  : str2nr(strftime('%Y'))
  var fm = month > 0 ? month : str2nr(strftime('%m'))
  var fd = day   > 0 ? day   : str2nr(strftime('%d'))
  var path = call(function(connect_func), [fy, fm, fd])
  if !empty(path)
    LoadAppointments(path)
  endif
enddef

# Parse the JSON at path, cache events for the current week, and re-render.
# JSON format: list of {start, end, subject, organizer, location, body}.
def LoadAppointments(path: string)
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
  delete(path)   # consumed — no longer needed on disk

  var events: dict<list<any>> = {}
  var allday: list<any> = []

  for item in items
    if get(item, 'allday', false)
      # Outlook all-day end is exclusive (next-day midnight) — subtract 1 day.
      var end_str = strpart(get(item, 'end', ''), 0, 10)
      var ey = str2nr(end_str[0 : 3])
      var em = str2nr(end_str[5 : 6])
      var ed = str2nr(end_str[8 : 9])
      var last = backend.JDNToDate(backend.DateToJDN(ey, em, ed) - 1)
      allday->add({
        start_date: strpart(get(item, 'start', ''), 0, 10),
        end_date:   printf('%04d-%02d-%02d', last.year, last.month, last.day),
        subject:    get(item, 'subject',   ''),
        organizer:  get(item, 'organizer', ''),
      })
    else
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
    endif
  endfor

  events['allday'] = allday

  var body_buf = bufnr(WEEK_BUF_NAME)
  var stored_key = body_buf > 0 ? getbufvar(body_buf, 'week_key', '') : ''
  var key = empty(stored_key)
    ? WeekCacheKey(str2nr(strftime('%Y')), str2nr(strftime('%m')), str2nr(strftime('%d')))
    : stored_key
  var ky = str2nr(key[0 : 3])
  var km = str2nr(key[5 : 6])
  var kd = str2nr(key[8 : 9])
  week_cache[key] = events
  RenderWeekView(ky, km, kd, events)
enddef

# Re-fetch appointments for the currently displayed week.
# Invalidates the cache entry so fresh data is pulled from the connect hook.
export def CalendarRefresh()
  if !HasConnectFunc()
    return
  endif
  var body_buf = bufnr(WEEK_BUF_NAME)
  var stored_key = body_buf > 0 ? getbufvar(body_buf, 'week_key', '') : ''
  var key = empty(stored_key)
    ? WeekCacheKey(str2nr(strftime('%Y')), str2nr(strftime('%m')), str2nr(strftime('%d')))
    : stored_key
  if has_key(week_cache, key)
    remove(week_cache, key)
  endif
  var ky = str2nr(key[0 : 3])
  var km = str2nr(key[5 : 6])
  var kd = str2nr(key[8 : 9])
  CallConnectHook(ky, km, kd)
enddef
