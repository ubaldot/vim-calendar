vim9script

import autoload "./backend.vim"
import autoload "./highlights.vim"

# Week view panel — self-contained module.
# Owns: WEEK_BUF_NAME, week_cache.
# Shared state lives in t:cal_* (tab-local, single calendar tab enforced).
# Date math is delegated to backend.vim.

export const WEEK_BUF_NAME = '__WeekView__'
export const WEEK_HDR_BUF_NAME = '__WeekHeader__'
const WEEK_TIME_COL = 8
const WEEK_DAY_FULL = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

var week_day_col          = 16   # cell width; set via Configure()
var cfg_week_display_type = 'eu' # 'eu' | 'us' | 'work'; set via Configure()

var week_cache: dict<dict<list<any>>> = {}

# Maps body-buffer line number (as string) → 7-element list of appointment
# dicts, one per day column.  Empty dict means no appointment in that cell.
# Rebuilt on every RenderWeekView call.
var appt_line_map: dict<list<dict<any>>> = {}

# Set the active diary's connect function and clear the week cache.
# Must be called whenever the active diary changes.
export def SetConnectFunc(name: string)
  t:cal_connect_func = name
  week_cache = {}
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

# Return wdays reordered for the configured display type.
# backend.WeekDays always returns [Mon..Sun] (indices 0-6).
def DisplayWdays(wdays: list<dict<any>>): list<dict<any>>
  if cfg_week_display_type ==# 'work'
    return wdays[0 : 4]                      # Mon–Fri
  elseif cfg_week_display_type ==# 'us'
    return [wdays[6]] + wdays[0 : 5]         # Sun–Sat
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

# Return the Monday date string ('YYYY-MM-DD') for the ISO week containing
# the given date.  Used as key in week_cache.
def WeekCacheKey(year: number, month: number, day: number): string
  var days = backend.WeekDays(year, month, day)
  return printf('%04d-%02d-%02d', days[0].year, days[0].month, days[0].day)
enddef

# ─── Render helpers ──────────────────────────────────────────────────────────

# Strip carriage returns (\r) left by Windows line endings in JSON fields.
def StripCR(s: string): string
  return substitute(s, "\r", '', 'g')
enddef

def MonthName(month: number): string
  return backend.month_num_to_str[printf('%02d', month)]
enddef

def WeekSepLine(join_char: string, n_days: number): string
  return repeat('─', WEEK_TIME_COL) .. join_char ..
    join(range(n_days)->mapnew((_, _) => repeat('─', week_day_col)), join_char)
enddef

def WeekDataRow(time_cell: string, day_cells: list<string>): string
  var tc = printf('%-*s', WEEK_TIME_COL, strcharpart(time_cell, 0, WEEK_TIME_COL))
  return tc .. '│' .. join(day_cells->mapnew(
    (_, c) => printf('%-*s', week_day_col, strcharpart(c, 0, week_day_col))), '│')
enddef

def CellText(text: string): string
  var max_len = week_day_col - 1
  var content = strcharlen(text) > max_len
    ? strcharpart(text, 0, max_len - 3) .. '...'
    : text
  return $' {content}'
enddef

def FormatEventCells(subject: string, organizer: string): list<string>
  return [CellText(subject), CellText($'({organizer})')]
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

# Return events from the events dict that start in the given hour slot.
def FindHourEvents(events: dict<any>, date_key: string, hour: number): list<dict<any>>
  return copy(get(events, date_key, []))->filter(
    (_, ev) => str2nr(split(get(ev, 'start', '00:00'), ':')[0]) == hour)
enddef

# Render banner rows for all-day events above the hour grid.
# One row per event; each row spans its start→end columns with dashes.
# Outlook all-day end is exclusive (next-day midnight), so end_date is
# already adjusted by 1 day before being stored.
# wdays must already be in display order (output of DisplayWdays).
def AllDayRows(events: dict<any>, wdays: list<dict<any>>): list<string>
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
  var display_wdays = DisplayWdays(wdays)
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
  hdr_lines->add(WeekDataRow(' UTC+2', day_labels))
  hdr_lines->add(WeekSepLine('┼', n_days))

  setbufvar(hdr_buf, '&modifiable', 1)
  deletebufline(hdr_buf, 1, '$')
  setbufline(hdr_buf, 1, hdr_lines)
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
  var hour7_line = 1
  for h in range(0, 23)
    if h == 7
      hour7_line = len(body_lines) + 1 + &scrolloff
    endif
    var day_evs: list<list<dict<any>>> = []
    for d in display_wdays
      day_evs->add(FindHourEvents(events,
        printf('%04d-%02d-%02d', d.year, d.month, d.day), h))
    endfor

    var slots = max([1] + day_evs->mapnew((_, evs) => len(evs)))
    for k in range(slots)
      var row1: list<string> = []
      var row2: list<string> = []
      var appt_row: list<dict<any>> = []
      for evs in day_evs
        if k < len(evs)
          var [l1, l2] = FormatEventCells(get(evs[k], 'subject', ''),
                                          get(evs[k], 'organizer', ''))
          row1->add(l1)
          row2->add(l2)
          appt_row->add(evs[k])
        else
          row1->add('')
          row2->add('')
          appt_row->add({})
        endif
      endfor
      var subj_lnum = len(body_lines) + 1
      body_lines->add(WeekDataRow(k == 0 ? printf('%3d', h) : '', row1))
      var org_lnum  = len(body_lines) + 1
      body_lines->add(WeekDataRow('', row2))
      # Both subject and organizer lines resolve to the same appointment row.
      if !empty(filter(copy(appt_row), (_, v) => !empty(v)))
        appt_line_map[string(subj_lnum)] = appt_row
        appt_line_map[string(org_lnum)]  = appt_row
      endif
    endfor
    body_lines->add(WeekSepLine('┼', n_days))
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
    # Set t:cal_week_key before the hook fires so LoadAppointments caches correctly.
    t:cal_week_key = cache_key
    CallConnectHook(year, month, day)
    if !has_key(week_cache, cache_key)
      RenderWeekView(year, month, day, {})
    endif
  endif
enddef

# Call the active diary's connect hook for the given week date.
# The hook must return the path it wrote to on success, '' on failure.
export def CallConnectHook(year: number = -1, month: number = -1, day: number = -1)
  if empty(get(t:, 'cal_connect_func', '')) || !exists($'*{t:cal_connect_func}')
    return
  endif
  var fy = year  > 0 ? year  : str2nr(strftime('%Y'))
  var fm = month > 0 ? month : str2nr(strftime('%m'))
  var fd = day   > 0 ? day   : str2nr(strftime('%d'))
  var path = function(t:cal_connect_func)(fy, fm, fd)
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
        subject:    StripCR(get(item, 'subject',   '')),
        organizer:  StripCR(get(item, 'organizer', '')),
      })
    else
      var date_key = strpart(get(item, 'start', ''), 0, 10)
      if !has_key(events, date_key)
        events[date_key] = []
      endif
      events[date_key]->add({
        start:     strpart(get(item, 'start', ''), 11, 5),
        end:       strpart(get(item, 'end',   ''), 11, 5),
        subject:   StripCR(get(item, 'subject',   '')),
        organizer: StripCR(get(item, 'organizer', '')),
        location:  StripCR(get(item, 'location',  '')),
        body:      StripCR(get(item, 'body',      '')),
        entryid:   get(item, 'entryid', ''),
      })
    endif
  endfor

  events['allday'] = allday

  var stored_key = get(t:, 'cal_week_key', '')
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
  if empty(get(t:, 'cal_connect_func', ''))
    return
  endif
  var stored_key = get(t:, 'cal_week_key', '')
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

# Return the appointment dict under the cursor in the __WeekView__ buffer,
# or {} if the cursor is on a separator, time column, or empty cell.
# col_idx (0-6) is derived from the fixed column widths:
#   WEEK_TIME_COL chars + '│' then each day = WEEK_DAY_COL chars + '│'
export def GetAppointmentAtCursor(): dict<any>
  var row = get(appt_line_map, string(line('.')), [])
  if empty(row)
    return {}
  endif
  # Time column occupies cols 1..WEEK_TIME_COL, then col WEEK_TIME_COL+1 is '│'.
  if col('.') <= WEEK_TIME_COL + 1
    return {}
  endif
  var col_idx = (col('.') - WEEK_TIME_COL - 2) / (week_day_col + 1)
  if col_idx < 0 || col_idx >= len(row)
    return {}
  endif
  return row[col_idx]
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

# Show a popup_atcursor with a brief preview of the appointment under the cursor.
# Body is limited to 10 non-empty lines.  Does nothing on empty cells.
def ShowAppointmentDetails()
  var appt = GetAppointmentAtCursor()
  if empty(appt)
    return
  endif
  var lines: list<string> = []
  var start_t = get(appt, 'start',     '')
  var end_t   = get(appt, 'end',       '')
  var org     = get(appt, 'organizer', '')
  var loc     = get(appt, 'location',  '')
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
  var appt = GetAppointmentAtCursor()
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
  var body  = get(appt, 'body',      '')

  var lines: list<string> = []
  lines->add($'Subject:   {subj}')
  lines->add($'Time:      {start_t} – {end_t}')
  if !empty(org) | lines->add($'Organizer: {org}') | endif
  if !empty(loc) | lines->add($'Location:  {loc}') | endif
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
  setlocal nomodifiable

  nnoremap <silent> <buffer> q     <Cmd>bwipeout!<CR>
  nnoremap <silent> <buffer> <Esc> <Cmd>bwipeout!<CR>
enddef

# Set buffer-local keymaps for the __WeekView__ body buffer.
def WeekViewBuildKeymap()
  nnoremap <silent> <buffer> K  <ScriptCmd>ShowAppointmentDetails()<CR>
  nnoremap <silent> <buffer> <CR> <ScriptCmd>OpenAppointmentBody()<CR>
  nnoremap <silent> <buffer> W  <Cmd>CalendarToggle<CR>
enddef
