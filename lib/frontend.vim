vim9script

import autoload "./backend.vim"
import autoload "./calendar_view.vim"
import autoload "./config.vim"
import autoload "./diary.vim"
import autoload "./diary_search.vim"
import autoload "./help_popup.vim"
import autoload "./highlights.vim"
import autoload "./local_provider.vim"
import autoload "./reminder.vim"
import autoload "./week_view.vim"

const cal_bufname = '__Calendar__'

var cfg_position = 'left'
var cfg_cal_type = 'eu'
var cfg_search_grep = 'internal'
var cfg_diaries: dict<any> = {My_Diary: {path: '~/my_diary', resolution: 'month'}}
var cfg_active_diary = 'My_Diary'
var cfg_diary_path = '~/my_diary'
var cfg_diary_resolution = 'month'
var cfg_address_book_path = ''
var cfg_auto_create_diary_dirs = false
var state_base_year = 0
var state_base_month = 0
var state_blocks: list<dict<any>> = []
var state_diary_rows: dict<string> = {}

def ConfigureProvider(name: string, diary_config: dict<any>)
  var fetch_func = get(diary_config, 'fetch_events', '')
  var manage_func = get(diary_config, 'manage_events', '')
  if empty(fetch_func) && empty(manage_func)
    local_provider.Configure(name, get(diary_config, 'events_file', ''),
      get(diary_config, 'address_book', ''))
    week_view.SetProviderFuncs(
      'g:CalendarLocalFetchEvents',
      'g:CalendarLocalManageEvents'
    )
    return
  endif
  week_view.SetProviderFuncs(fetch_func, manage_func)
enddef

# Initialize script-local runtime state from g:calendar_config.
def InitVariables(): bool
  var cfg = config.Load()
  if !get(cfg, 'ok', false)
    return false
  endif

  cfg_position = cfg.position
  cfg_cal_type = cfg.cal_type
  cfg_search_grep = cfg.search_grep
  cfg_auto_create_diary_dirs = cfg.auto_create_diary_dirs
  cfg_diaries = cfg.diaries
  cfg_active_diary = cfg.active_diary
  cfg_diary_path = cfg.diary_path
  cfg_address_book_path = cfg.address_book_path
  cfg_diary_resolution = cfg.diary_resolution

  calendar_view.Configure({
    cal_type:          cfg_cal_type,
    show_week_number:  cfg.show_week_number,
    number_of_months:  cfg.number_of_months,
    position:          cfg_position,
    holidays:          cfg.holidays,
    diaries:           cfg_diaries,
    active_diary:      cfg_active_diary,
    diary_path:        cfg_diary_path,
    diary_resolution:  cfg_diary_resolution,
  })
  diary.Configure(cfg_diary_path, cfg_diary_resolution,
    cfg_address_book_path, cfg_auto_create_diary_dirs)
  week_view.Configure(
    cfg.week_display_type,
    cfg.week_cell_width
  )
  ConfigureProvider(cfg_active_diary, cfg_diaries[cfg_active_diary])
  reminder.SetSoundEnabled(cfg.reminder_sound)

  return true

enddef

# Open or reuse calendar buffer window according to target position.
def OpenCalendarWindow(): number

  var bw = bufnr(cal_bufname)
  var ww = bw > 0 ? bufwinnr(bw) : -1
  if ww > 0
    execute $":{ww}wincmd w"
    return win_getid()
  endif

  if bw > 0
    if cfg_position ==# 'left'
      execute $'topleft vertical sbuffer {bw}'
    else
      execute $'botright vertical sbuffer {bw}'
    endif
    return win_getid()
  endif

  if cfg_position ==# 'left'
    topleft vnew
  else
    botright vnew
  endif

  execute $"file {cal_bufname}"
  setlocal buftype=nofile bufhidden=delete noswapfile nowrap nobuflisted nomodified nomodifiable
  if exists('+winfixbuf')
    setlocal winfixbuf
  endif
  setlocal fdc=0 nonu
  if has('+relativenumber') || exists('+relativenumber')
    setlocal nornu
  endif

  return win_getid()
enddef

# Update only the CalCurrWeek match in the current window.
def UpdateCurrWeekHighlight()
  highlights.UpdateCurrWeek()
enddef

# Apply match highlights to the current calendar buffer.
def ApplyHighlights(view: dict<any>)
  highlights.Apply(view, calendar_view.WeekNumberEnabled())
enddef

# Cycle through configured diaries by step (+1 / -1), activate the next one,
# re-render, and update the week view if it is open.
def CycleDiary(step: number): bool
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
  RenderView(state_base_year, state_base_month)

  # Update week view: fetch if the new diary has a provider, else clear it.
  if bufnr(week_view.WEEK_BUF_NAME) > 0
    if !empty(get(t:, 'cal_fetch_events_func', ''))
      week_view.FetchEvents()
    else
      var ty = str2nr(strftime('%Y'))
      var tm = str2nr(strftime('%m'))
      var td = str2nr(strftime('%d'))
      week_view.RenderWeekView(ty, tm, td, {})
    endif
  endif
  week_view.RescheduleReminders()

  return true
enddef

# Command-facing wrapper for diary cycling from the week-view buffer.
# Restores focus to the calling window afterward, since CycleDiary's
# RenderView() switches focus to the calendar window as a side effect.
export def DiaryCycleNavigate(direction: string)
  var save_win = win_getid()
  CycleDiary(direction ==# 'next' ? 1 : -1)
  if win_id2win(save_win) > 0
    win_gotoid(save_win)
  endif
enddef

# Build and display the view for (base_year, base_month).
# Writes to the __Calendar__ buffer, resizes the window, sets keymaps and
# highlights, and positions the cursor on today.
def RenderView(base_year: number, base_month: number)

  var view = calendar_view.BuildView(base_year, base_month)

  silent! doautocmd User CalendarBeforeShow
  var winid = OpenCalendarWindow()

  setlocal modifiable
  deletebufline('%', 1, '$')
  append(0, view.lines)
  deletebufline('%', len(view.lines) + 1)
  setlocal nomodifiable

  var width = max(view.lines->mapnew((_, s) => len(s))) + 2
  execute $"vertical resize {min([max([20, width]), &columns - 5])}"

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

# Switch active diary, update cfg_* and calendar_view state, and clear the
# week cache so the next render fetches fresh data.
def ActivateDiary(name: string): bool
  if !has_key(cfg_diaries, name)
    return false
  endif
  g:calendar_config.active_diary = name
  cfg_active_diary = name
  var d = cfg_diaries[name]
  cfg_diary_path = has_key(d, 'path') ? d.path : cfg_diary_path
  cfg_diary_resolution = get(d, 'resolution', 'month')
  cfg_address_book_path = get(d, 'address_book', '')
  calendar_view.SetActiveDiary(cfg_active_diary, cfg_diary_path, cfg_diary_resolution)
  diary.Configure(cfg_diary_path, cfg_diary_resolution,
    cfg_address_book_path, cfg_auto_create_diary_dirs)
  ConfigureProvider(name, d)
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
  week_view.FetchEvents()
  week_view.RescheduleReminders()
  return true
enddef

# Translate a navigation keyword into a year/month change and re-render.
# Returns true if the arg was a known navigation action (consumed).
def HandleNavigation(arg: string): bool
  var y = state_base_year
  var m = state_base_month

  if arg ==# 'NextMonth'
    var ym = calendar_view.AddMonths(y, m, 1)
    y = ym[0] | m = ym[1]
  elseif arg ==# 'PrevMonth'
    var ym = calendar_view.AddMonths(y, m, -1)
    y = ym[0] | m = ym[1]
  elseif arg ==# 'NextYear'
    y += 1
  elseif arg ==# 'PrevYear'
    y -= 1
  elseif arg ==# 'Today'
    y = str2nr(strftime('%Y'))
    m = str2nr(strftime('%m'))
  elseif arg ==# 'NextDiary'
    CycleDiary(1)
    return true
  elseif arg ==# 'PrevDiary'
    CycleDiary(-1)
    return true
  else
    return false
  endif

  var curp = getpos('.')

  RenderView(y, m)

  setpos('.', curp)
  return true
enddef

# Central dispatcher for all key-mapped actions.
# With arg: delegates to HandleNavigation (month/year jumps, today, diary cycle).
# Without arg (<CR>): switches diary if on the selector section, otherwise
# navigates the week view.
def Action(arg: string = '')

  if !empty(arg) && HandleNavigation(arg)
    # 'Today': also snap the week view to today and reset the week highlight.
    if arg ==# 'Today' && bufnr(week_view.WEEK_BUF_NAME) > 0
      var ty = str2nr(strftime('%Y'))
      var tm = str2nr(strftime('%m'))
      var td = str2nr(strftime('%d'))
      week_view.NavigateWeekView(ty, tm, td)
      t:cal_curr_week_num = str2nr(strftime('%V'))
      if calendar_view.WeekNumberEnabled()
        UpdateCurrWeekHighlight()
      endif
    endif
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

  var day = str2nr(day_string)

  var block = FindBlockAtCursor()

  # Guard that the cursor is not on any weird place
  if empty(block) || col('.') < block.day_col_start || col('.') > block.day_col_end
    return
  endif

  var month = block.month
  var year = block.year
  if bufnr(week_view.WEEK_BUF_NAME) <= 0
    return
  endif

  week_view.NavigateWeekView(year, month, day)
  t:cal_curr_week_num = backend.ISOWeekNum(year, month, day)
  if calendar_view.WeekNumberEnabled()
    UpdateCurrWeekHighlight()
  endif
enddef

# Close the calendar tab, or wipe buffers when it is the only tab.
def Close()
  if tabpagenr('$') > 1
    tabclose!
  else
    for bname in [cal_bufname, week_view.WEEK_HDR_BUF_NAME,
                  week_view.WEEK_BUF_NAME]
      var bn = bufnr(bname)
      if bn > 0
        if exists('+winfixbuf')
          for winid in win_findbuf(bn)
            win_execute(winid, 'setlocal nowinfixbuf')
          endfor
        endif
        execute $'bwipeout! {bn}'
      endif
    endfor
  endif
enddef

# Default action: open/create markdown diary file for selected date.
def OpenDiaryPage(day: number, month: number, year: number, week: number)
  var file = diary.PrepareFile(year, month, day)
  if empty(file)
    return
  endif
  silent! wincmd p
  if exists('+winfixbuf') && &l:winfixbuf
    setlocal nowinfixbuf
  endif
  execute $"edit {file}"
enddef

# Close the calendar tab and open the diary entry for the day (or month when
# the cursor is not on a specific day number) under the cursor.
# Bound to <C-CR> / <S-CR> in the left pane.
def ActionOpenDiaryAndClose()
  var block = FindBlockAtCursor()
  if empty(block)
    return
  endif

  var month = block.month
  var year  = block.year

  # Use the day under cursor if it is a valid day number; otherwise fall back
  # to day 1 (opens the month-level or first-day entry).
  var day_str = matchstr(expand('<cword>'), '^\d\{1,2}$')
  var day = !empty(day_str)
      && col('.') >= block.day_col_start
      && col('.') <= block.day_col_end
    ? str2nr(day_str)
    : 1

  var file = diary.PrepareFile(year, month, day)
  if empty(file)
    return
  endif

  # Close the calendar (tab or buffers) before opening the file so the edit
  # lands in the window that becomes current after the tab closes.
  cal_tab_winid = -1
  Close()
  if exists('+winfixbuf') && &l:winfixbuf
    setlocal nowinfixbuf
  endif
  execute $"edit {file}"
enddef

# Public bridge used by the global omnifunc wrapper in plugin/calendar.vim.
export def AddressBookComplete(findstart: number, base: string): any
  return diary.Complete(findstart, base,
    get(b:, 'calendar_address_book_path', cfg_address_book_path))
enddef

# Build buffer-local key mappings for calendar interactions.
def CalendarBuildKeymap()

  nnoremap <silent> <buffer> q <ScriptCmd>Close()<CR>
  nnoremap <silent> <buffer> <CR> <ScriptCmd>Action()<CR>
  nnoremap <silent> <buffer> <C-Down> <ScriptCmd>Action('NextMonth')<CR>
  nnoremap <silent> <buffer> <C-Up> <ScriptCmd>Action('PrevMonth')<CR>
  nnoremap <silent> <buffer> <C-Right> <ScriptCmd>Action('NextYear')<CR>
  nnoremap <silent> <buffer> <C-Left> <ScriptCmd>Action('PrevYear')<CR>
  nnoremap <silent> <buffer> t <ScriptCmd>Action('Today')<CR>
  nnoremap <silent> <buffer> <Tab> <ScriptCmd>Action('NextDiary')<CR>
  nnoremap <silent> <buffer> <S-Tab> <ScriptCmd>Action('PrevDiary')<CR>
  nnoremap <silent> <buffer> ? <ScriptCmd>help_popup.Show()<CR>
  nnoremap <silent> <buffer> <C-CR> <ScriptCmd>ActionOpenDiaryAndClose()<CR>
  nnoremap <silent> <buffer> <S-CR> <ScriptCmd>ActionOpenDiaryAndClose()<CR>
  nnoremap <silent> <buffer> <F5> <Cmd>CalendarRefresh<CR>

enddef

# Toggle the calendar tab: jump to it if open elsewhere, close if current,
# open fresh if not yet open.
var cal_tab_winid = -1

# Navigate the week view to the next week, previous week, or today, and
# synchronise the left calendar pane by positioning the cursor on the target
# date when that date is visible in the configured calendar layout.
# direction: 'next' | 'prev' | 'today'
export def WeekViewNavigate(direction: string)
  var y: number
  var m: number
  var d: number

  if direction ==# 'today'
    y = str2nr(strftime('%Y'))
    m = str2nr(strftime('%m'))
    d = str2nr(strftime('%d'))
  else
    var key = get(t:, 'cal_week_key', strftime('%Y-%m-%d'))
    var parts = split(key, '-')
    if len(parts) != 3
      return
    endif
    var jdn = backend.DateToJDN(
      str2nr(parts[0]), str2nr(parts[1]), str2nr(parts[2]))
    var target = backend.JDNToDate(jdn + (direction ==# 'next' ? 7 : -7))
    y = target.year
    m = target.month
    d = target.day
  endif

  var cal_buf = bufnr(cal_bufname)
  if cal_buf <= 0 || empty(win_findbuf(cal_buf))
    week_view.NavigateWeekView(y, m, d)
    return
  endif

  var save_win = win_getid()
  win_gotoid(win_findbuf(cal_buf)[0])

  # m is already the month that contains the target Monday — render it directly.
  # No year loops, no month loops, no searching needed.
  RenderView(y, m)

  # Keep the week view authoritative even when the target day is hidden in a
  # work-week calendar, then place the left-pane cursor when that day is shown.
  week_view.NavigateWeekView(y, m, d)
  t:cal_curr_week_num = backend.ISOWeekNum(y, m, d)
  if calendar_view.WeekNumberEnabled()
    UpdateCurrWeekHighlight()
  endif

  for block in state_blocks
    if block.year == y && block.month == m
      var first_wd = backend.WeekdayForDate(y, m, 1)  # 1=Mon..7=Sun
      var day_wd   = backend.WeekdayForDate(y, m, d)
      var col_idx = cfg_cal_type ==# 'us' ? day_wd % 7 : day_wd - 1
      if cfg_cal_type ==# 'work' && col_idx >= 5
        break
      endif
      var leading = cfg_cal_type ==# 'us' ? first_wd % 7 : first_wd - 1
      cursor(block.line_start + (d - 1 + leading) / 7,
             block.day_col_start + col_idx * 3 + 1)
      break
    endif
  endfor

  win_gotoid(save_win)
enddef

export def CalendarToggle(year: number = -1, month: number = -1)
  if !InitVariables()
    return
  endif

  if win_id2win(cal_tab_winid) > 0
      && bufname(winbufnr(cal_tab_winid)) ==# cal_bufname
    var [tabnr, _] = win_id2tabwin(cal_tab_winid)
    if tabpagenr() == tabnr
      cal_tab_winid = -1
      if tabpagenr('$') > 1
        tabclose
      else
        Close()
      endif
    else
      execute $'tabnext {tabnr}'
      var week_windows = win_findbuf(bufnr(week_view.WEEK_BUF_NAME))
      win_gotoid(empty(week_windows) ? cal_tab_winid : week_windows[0])
    endif
    return
  endif

  Show(year, month)
  var calendar_windows = win_findbuf(bufnr(cal_bufname))
  cal_tab_winid = empty(calendar_windows) ? -1 : calendar_windows[0]
  week_view.FetchEvents()
  week_view.RescheduleReminders()
enddef

# Wipe all calendar-related buffers and close the calendar tab if open.
# Called by :CalendarWipe.
export def CalendarWipe()
  reminder.CancelAll()
  if win_id2win(cal_tab_winid) > 0
    var [tabnr, _] = win_id2tabwin(cal_tab_winid)
    cal_tab_winid = -1
    if tabpagenr('$') > 1
      execute $'tabclose {tabnr}'
    endif
  endif
  for bname in [cal_bufname,
                week_view.WEEK_BUF_NAME,
                week_view.WEEK_HDR_BUF_NAME,
                week_view.APPT_BUF_NAME]
    var bn = bufnr(bname)
    if bn > 0
      if exists('+winfixbuf')
        for winid in win_findbuf(bn)
          win_execute(winid, 'setlocal nowinfixbuf')
        endfor
      endif
      execute $'silent! bwipeout! {bn}'
    endif
  endfor
enddef

# Main entrypoint: opens a tab with calendar and week-view panes side by side.
export def Show(year: number = -1, month: number = -1): string

  if !InitVariables()
    return ''
  endif

  var y = year == -1 ? str2nr(strftime('%Y')) : year
  var m = month == -1 ? str2nr(strftime('%m')) : month

  # Open a dedicated tab: calendar on one side, week view on the other.
  tabnew
  var tabnew_bufnr = bufnr('%')
  # Initialize tab-local state now that we're in the calendar tab.
  t:cal_curr_week_num = str2nr(strftime('%V'))
  var active = cfg_diaries[cfg_active_diary]
  ConfigureProvider(cfg_active_diary, active)
  RenderView(y, m)
  var cal_winid = win_getid()

  if week_view.OpenWeekViewWindow(tabnew_bufnr)
    var current_y = str2nr(strftime('%Y'))
    var current_m = str2nr(strftime('%m'))
    var selected_day = y == current_y && m == current_m
      ? str2nr(strftime('%d'))
      : 1
    week_view.RenderWeekView(y, m, selected_day, {})
  endif

  var week_windows = win_findbuf(bufnr(week_view.WEEK_BUF_NAME))
  win_gotoid(empty(week_windows) ? cal_winid : week_windows[0])
  return ''
enddef

# Search a keyword across diary markdown files using vimgrep or external grep
# depending on cfg_search_grep.  Results land in the quickfix list.
export def Search(keyword: string, year: string = '')

  if !InitVariables()
    return
  endif

  diary_search.Run(cfg_diary_path, cfg_search_grep, keyword,
    empty(year) ? strftime('%Y') : year)
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
