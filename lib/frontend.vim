vim9script

import autoload "./backend.vim"
import autoload "./calendar_view.vim"
import autoload "./highlights.vim"
import autoload "./reminder.vim"
import autoload "./week_view.vim"

const cal_bufname = '__Calendar__'

var cfg_position = 'left'
var cfg_cal_type = 'eu'
var cfg_show_week_number = false
var cfg_number_of_months = 3
var cfg_holidays: dict<any> = {}
var cfg_search_grep = 'internal'
var cfg_diaries: dict<any> = {My_Diary: {path: '~/my_diary', resolution: 'month'}}
var cfg_active_diary = 'My_Diary'
var cfg_diary_path = '~/my_diary'
var cfg_diary_resolution = 'month'
var cfg_address_book_path = ''
var cfg_auto_create_diary_dirs = false
var cfg_action = 'OpenDiaryPage'
var cfg_connect = ''
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
  cfg_connect = get(active, 'connect', '')
  cfg_address_book_path = get(active, 'address_book', '')
  cfg_diary_resolution = get(active, 'resolution', 'month')

  var c = get(cfg, 'connect', {})
  if !empty(c)
    echomsg "[Calendar] 'connect' at top level is ignored; set it per-diary in diaries_dict."
  endif

  calendar_view.Configure({
    cal_type:          cfg_cal_type,
    show_week_number:  cfg_show_week_number,
    number_of_months:  cfg_number_of_months,
    position:          cfg_position,
    holidays:          cfg_holidays,
    diaries:           cfg_diaries,
    active_diary:      cfg_active_diary,
    diary_path:        cfg_diary_path,
    diary_resolution:  cfg_diary_resolution,
  })

  week_view.Configure(
    get(cfg, 'week_display_type', 'eu'),
    max([8, get(cfg, 'week_cell_width', 16)])
  )
  reminder.SetSoundEnabled(!!get(cfg, 'reminder_sound', true))

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

  if cfg_position ==# 'left'
    topleft vnew
  elseif cfg_position ==# 'right'
    botright vnew
  else
    topleft vnew
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

def ApplyPopupHighlights(winid: number, view: dict<any>)
  highlights.ApplyPopup(winid, view, calendar_view.WeekNumberEnabled())
enddef

# Move the popup selection cursor to a day cell by index.
# Removes the previous CalPopupSelection match, adds one for the new cell,
# and repositions the popup cursor.  Index is clamped to valid range.
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

# Cycle through configured diaries by step (+1 / -1), activate the next one,
# re-render, and update the week view if it is open.
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

  # Update week view: fetch if new diary has a connect hook, else clear it.
  if bufnr(week_view.WEEK_BUF_NAME) > 0
    if !empty(get(t:, 'cal_connect_func', ''))
      week_view.CallConnectHook()
    else
      var ty = str2nr(strftime('%Y'))
      var tm = str2nr(strftime('%m'))
      var td = str2nr(strftime('%d'))
      week_view.RenderWeekView(ty, tm, td, {})
    endif
  endif

  return true
enddef

# Open the diary page for the currently selected popup day via cfg_action.
def PopupOpenSelectedDay(): bool
  if popup_day_index < 0 || popup_day_index >= len(popup_day_cells)
    return false
  endif
  var day = popup_day_cells[popup_day_index].day
  var week = backend.WeekdayForDate(popup_year, popup_month, day)
  var action_name = 'OpenDiaryPage'
  if type(cfg_action) == v:t_string && !empty(cfg_action) && exists($'*{cfg_action}')
    action_name = cfg_action
  endif
  function(action_name)(day, popup_month, popup_year, week)
  return true
enddef
# Build and display the view for (base_year, base_month).
# In popup mode: (re-)creates the popup window.
# In split mode: writes to the __Calendar__ buffer, resizes the window,
# sets keymaps and highlights, and positions the cursor on today.
def RenderView(base_year: number, base_month: number)

  var view = calendar_view.BuildView(base_year, base_month)

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
  week_view.SetConnectFunc(get(d, 'connect', ''))   # clears week_cache for new diary
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
  week_view.CallConnectHook()
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

# Central dispatcher for all key-mapped actions.
# With arg: delegates to HandleNavigation (month/year jumps, today, diary cycle).
# Without arg (<CR>): switches diary if on the selector section, otherwise
# navigates the week view (split) or opens the diary page (popup).
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
  var week = backend.WeekdayForDate(year, month, day)

  # When the week view is open, <CR> navigates it — don't open a diary page.
  if bufnr(week_view.WEEK_BUF_NAME) > 0
    week_view.NavigateWeekView(year, month, day)
    t:cal_curr_week_num = backend.ISOWeekNum(year, month, day)
    if calendar_view.WeekNumberEnabled()
      UpdateCurrWeekHighlight()
    endif
    return
  endif

  # No week view (popup mode) — open diary page as usual.
  var action_name = 'OpenDiaryPage'
  if type(cfg_action) == v:t_string && !empty(cfg_action) && exists($'*{cfg_action}')
    action_name = cfg_action
  endif
  function(action_name)(day, month, year, week)
enddef

# Close the popup or, in split mode, close the calendar tab (or wipe buffers
# when it is the only tab).
def Close()
  if popup_id > 0
    popup_close(popup_id)
    popup_id = -1
  else
    if tabpagenr('$') > 1
      tabclose!
    else
      for bname in [cal_bufname, week_view.WEEK_HDR_BUF_NAME, week_view.WEEK_BUF_NAME]
        var bn = bufnr(bname)
        if bn > 0
          execute $'bwipeout! {bn}'
        endif
      endfor
    endif
  endif
enddef

# Ensure path exists, creating it if cfg_auto_create_diary_dirs is set.
# Prompts the user to create it manually when auto-creation is off.
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
  if cfg_diary_resolution ==# 'day'
    var month_dir = calendar_view.DiaryMonthDir(year, month)
    if !EnsureDiaryDir(month_dir)
      return
    endif
  endif

  var file = substitute(calendar_view.DiaryFilePath(year, month, day), ' ', '\\ ', 'g')
  silent! wincmd p
  if exists('+winfixbuf') && &l:winfixbuf
    setlocal nowinfixbuf
  endif
  execute $"edit {file}"
  ApplyAddressBook()
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

  var diary_root = expand(cfg_diary_path)
  if !EnsureDiaryDir(diary_root)
    return
  endif
  var year_dir = $"{diary_root}/{printf('%04d', year)}"
  if !EnsureDiaryDir(year_dir)
    return
  endif
  if cfg_diary_resolution ==# 'day'
    var month_dir = calendar_view.DiaryMonthDir(year, month)
    if !EnsureDiaryDir(month_dir)
      return
    endif
  endif

  var file = substitute(calendar_view.DiaryFilePath(year, month, day), ' ', '\\ ', 'g')

  # Close the calendar (tab or buffers) before opening the file so the edit
  # lands in the window that becomes current after the tab closes.
  cal_tab_winid = -1
  Close()
  execute $"edit {file}"
  ApplyAddressBook()
enddef

# If cfg_address_book_path points to a readable JSON file, set omnifunc on
# the current buffer to the calendar address-book completion function.
def ApplyAddressBook()
  if empty(cfg_address_book_path)
    return
  endif
  var path = expand(cfg_address_book_path)
  if !filereadable(path)
    return
  endif
  setlocal omnifunc=CalendarAddressBookComplete
enddef

# Load the address book JSON and return it as a list of {name, email} dicts.
# Returns [] when the file is absent or malformed.
def LoadAddressBook(): list<any>
  var path = expand(cfg_address_book_path)
  if !filereadable(path)
    return []
  endif
  try
    return readfile(path)->join("\n")->json_decode()
  catch
    return []
  endtry
enddef

# Omnifunc for address-book completion in diary buffers.
# Format: [{name: "Alice Smith", email: "alice@corp.com"}, ...]
# Completion trigger: any partial name or email fragment.
export def AddressBookComplete(findstart: number, base: string): any
  if findstart
    # Find start of the current token (stop at whitespace, colon, comma, semicolon).
    var c = col('.') - 1
    var line = getline('.')
    while c > 0 && line[c - 1] !~ '[ \t:,;]'
      c -= 1
    endwhile
    return c
  else
    var prefix = tolower(base)
    return LoadAddressBook()
      ->filter((_, e) =>
          empty(prefix)
          || tolower(get(e, 'name',  '')) =~# prefix
          || tolower(get(e, 'email', '')) =~# prefix)
      ->mapnew((_, e) => ({
          word: $'{e.name} <{e.email}>',
          abbr: get(e, 'name',  ''),
          menu: get(e, 'email', ''),
        }))
  endif
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
  nnoremap <silent> <buffer> <CR> <ScriptCmd>Action()<CR>
  nnoremap <silent> <buffer> <C-Down> <ScriptCmd>Action('NextMonth')<CR>
  nnoremap <silent> <buffer> <C-Up> <ScriptCmd>Action('PrevMonth')<CR>
  nnoremap <silent> <buffer> <C-Right> <ScriptCmd>Action('NextYear')<CR>
  nnoremap <silent> <buffer> <C-Left> <ScriptCmd>Action('PrevYear')<CR>
  nnoremap <silent> <buffer> t <ScriptCmd>Action('Today')<CR>
  nnoremap <silent> <buffer> <Tab> <ScriptCmd>Action('NextDiary')<CR>
  nnoremap <silent> <buffer> <S-Tab> <ScriptCmd>Action('PrevDiary')<CR>
  nnoremap <silent> <buffer> ? <ScriptCmd>CalendarHelp()<CR>
  nnoremap <silent> <buffer> <C-CR> <ScriptCmd>ActionOpenDiaryAndClose()<CR>
  nnoremap <silent> <buffer> <S-CR> <ScriptCmd>ActionOpenDiaryAndClose()<CR>
  nnoremap <silent> <buffer> <F5> <Cmd>CalendarRefresh<CR>

enddef

# Key filter for the calendar popup window.
# Handles navigation (arrows, t), day selection (hjkl, <CR>), diary cycling
# (Tab/S-Tab), help (?), and close (q/<Esc>).  Must return true for handled
# keys so Vim suppresses default popup behaviour.
def PopupFilter(id: number, key: string): bool
  if key ==# 'q' || key ==# "\<Esc>"
    popup_close(id)
    popup_id = -1
    return true
  elseif key ==# "\<Down>"
    var ym = calendar_view.AddMonths(popup_year, popup_month, 1)
    popup_year = ym[0] | popup_month = ym[1]
    RenderView(popup_year, popup_month)
    return true
  elseif key ==# "\<Up>"
    var ym = calendar_view.AddMonths(popup_year, popup_month, -1)
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

# Toggle the calendar tab: jump to it if open elsewhere, close if current,
# open fresh if not yet open.
var cal_tab_winid = -1

# Navigate the week view to the next week, previous week, or today, and
# synchronise the left calendar pane by positioning the cursor on the target
# Monday and firing Action() — which handles NavigateWeekView, week-number
# highlight, and all other side effects.
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

  # Place cursor precisely on day d using column arithmetic, then call
  # Action() which handles NavigateWeekView, t:cal_curr_week_num, highlights.
  for block in state_blocks
    if block.year == y && block.month == m
      var first_wd = backend.WeekdayForDate(y, m, 1)  # 0=Mon..6=Sun
      var day_wd   = backend.WeekdayForDate(y, m, d)
      cursor(block.line_start + (d - 1 + first_wd) / 7,
             block.day_col_start + day_wd * 3)
      Action()
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
      win_gotoid(cal_tab_winid)
    endif
    return
  endif

  Show(year, month)
  cal_tab_winid = win_getid()
  week_view.CallConnectHook()
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
      execute $'silent! bwipeout! {bn}'
    endif
  endfor
enddef

# Main entrypoint called by :Calendar.
# In split mode: opens a new tab with the calendar pane and (if configured)
# the week view pane side by side.  In popup mode: creates a centred popup.
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
  # Initialize tab-local state now that we're in the calendar tab.
  t:cal_curr_week_num = str2nr(strftime('%V'))
  week_view.SetConnectFunc(cfg_connect)
  RenderView(y, m)
  var cal_winid = win_getid()

  if week_view.OpenWeekViewWindow(tabnew_bufnr)
    week_view.RenderWeekView(y, m, str2nr(strftime('%d')), {})
  endif

  win_gotoid(cal_winid)
  return ''
enddef

# Search a keyword across diary markdown files using vimgrep or external grep
# depending on cfg_search_grep.  Results land in the quickfix list.
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

# vim: shiftwidth=2 softtabstop=2 noexpandtab
