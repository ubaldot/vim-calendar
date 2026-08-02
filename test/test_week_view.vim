vim9script

import "./common.vim"
var WaitForAssert = common.WaitForAssert

packadd CalendarToggle
import autoload "../lib/week_view.vim"
import autoload "../lib/backend.vim"
import autoload "../lib/reminder.vim"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Fetch function used by tests: copies the fixture JSON to a temp file and
# returns its path (which LoadAppointments will consume and delete).
def g:TestFetchEvents(request: dict<any>): string
  g:last_fetch_events_request = request
  var src = 'fixtures/appointments.json'
  if !filereadable(src)
    return ''
  endif
  var tmp = tempname() .. '.json'
  writefile(readfile(src), tmp)
  return tmp
enddef

def ResetConfig()
  g:calendar_config = {
    position:      'left',
    cal_type:      'eu',
    show_week_number: true,
    number_of_months: 3,
    holidays:      {},
    search_grep:   'internal',
    diaries_dict:  {
      TestDiary: {
        path:    tempname(),
        fetch_events: 'g:TestFetchEvents',
      }
    },
    active_diary: 'TestDiary',
  }
enddef

def BufLines(name: string): list<string>
  return getbufline(bufnr(name), 1, '$')
enddef

def HasLine(lines: list<string>, pat: string): bool
  return !empty(filter(copy(lines), $'v:val =~ "{pat}"'))
enddef

# ── Tests ────────────────────────────────────────────────────────────────────

def g:Test_week_view_opens_three_windows()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  assert_true(bufnr(week_view.WEEK_BUF_NAME) > 0,
    '__WeekView__ buffer must exist')
  assert_true(bufnr(week_view.WEEK_HDR_BUF_NAME) > 0,
    '__WeekHeader__ buffer must exist')
  assert_equal(week_view.WEEK_BUF_NAME, bufname('%'),
    'Opening the calendar must focus the week-view body')
enddef

def g:Test_week_view_t_variables_initialized()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])
  assert_true(has_key(t:, 'cal_curr_week_num'),
    't:cal_curr_week_num must be set in calendar tab')
  assert_true(has_key(t:, 'cal_fetch_events_func'),
    't:cal_fetch_events_func must be set in calendar tab')
  assert_equal('g:TestFetchEvents', t:cal_fetch_events_func)
enddef

def g:Test_week_view_week_key_set_on_render()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])
  assert_true(has_key(t:, 'cal_week_key'),
    't:cal_week_key must be set after initial render')
  # Key must be a Monday date (YYYY-MM-DD)
  assert_match('^\d\{4}-\d\{2}-\d\{2}$', t:cal_week_key)
enddef

def g:Test_week_view_navigate_updates_week_key()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])
  week_view.NavigateWeekView(2026, 8, 3)   # first day of week 2026-W32
  assert_equal('2026-08-03', t:cal_week_key)
enddef

def g:Test_week_view_load_appointments_renders_events()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  # Navigate to the fixture week and trigger the fetch hook.
  t:cal_week_key = '2026-07-27'
  week_view.FetchEvents(2026, 7, 27)

  var lines = BufLines(week_view.WEEK_BUF_NAME)
  assert_true(HasLine(lines, 'Team Meeting'),
    'Expected "Team Meeting" in week view after loading appointments')
  assert_true(HasLine(lines, 'One-on-One'),
    'Expected "One-on-One" in week view after loading appointments')
enddef

def g:Test_week_view_overlapping_events_both_rendered()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  t:cal_week_key = '2026-07-27'
  week_view.FetchEvents(2026, 7, 27)

  # Mon Jul 27 has Team Meeting 09:00 and Overlapping Review 09:30 — both must appear.
  var lines = BufLines(week_view.WEEK_BUF_NAME)
  assert_true(HasLine(lines, 'Team Meeting'),    'First overlapping event missing')
  assert_true(HasLine(lines, 'Overlapping'),     'Second overlapping event missing')
enddef

def g:Test_week_view_allday_events_in_header()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))

  t:cal_week_key = '2026-07-27'
  week_view.FetchEvents(2026, 7, 27)

  var hdr_lines = BufLines(week_view.WEEK_HDR_BUF_NAME)
  assert_true(HasLine(hdr_lines, 'Sprint Planning') || HasLine(hdr_lines, 'Company Offsite'),
    'Expected all-day events in __WeekHeader__ buffer')
enddef

def g:Test_week_view_navigate_different_week_no_events()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  # Navigate to a week with no fixture data — buffer should render but be event-free.
  week_view.NavigateWeekView(2025, 1, 6)
  var lines = BufLines(week_view.WEEK_BUF_NAME)
  assert_false(HasLine(lines, 'Team Meeting'),
    '"Team Meeting" should not appear for a different week')
enddef

def g:Test_today_key_resets_after_t_navigation()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  # Simulate navigating away to a different week.
  week_view.NavigateWeekView(2025, 1, 6)
  assert_equal('2025-01-06', t:cal_week_key)

  # Switch focus to calendar window and press 't' (Today).
  # Simulate by calling Action directly via the exported CalendarToggle path.
  win_gotoid(win_findbuf(bufnr('__Calendar__'))[0])
  feedkeys('t', 'x')   # triggers Action('Today') via buffer keymap

  # Week key must now reflect today's week.
  var monday = backend.WeekDays(
    str2nr(strftime('%Y')),
    str2nr(strftime('%m')),
    str2nr(strftime('%d')))[0]
  assert_equal(printf('%04d-%02d-%02d',
    monday.year, monday.month, monday.day), t:cal_week_key)
  assert_equal(str2nr(strftime('%V')), t:cal_curr_week_num)
enddef

def g:Test_get_event_at_cursor()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))

  # Load fixture appointments for week 2026-07-27.
  t:cal_week_key = '2026-07-27'
  week_view.FetchEvents(2026, 7, 27)

  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  # Hours 0-8: 9 empty hours × 3 lines (1 slot × 2 rows + separator) = 27 lines.
  # Hour 9 has 2 overlapping events on Monday (col 0):
  #   slot 0 subject  → line 28  (Team Meeting)
  #   slot 0 organizer → line 29
  #   slot 1 subject  → line 30  (Overlapping Review)
  # Col 15 is safely within the Monday cell (cols 10-25, WEEK_TIME_COL=8, WEEK_DAY_COL=16).
  cursor(28, 15)
  var appt = week_view.GetEventAtCursor()
  assert_equal('Team Meeting', get(appt, 'subject', ''),
    'Line 28 col 15 should resolve to Team Meeting')

  cursor(30, 15)
  appt = week_view.GetEventAtCursor()
  assert_equal('Overlapping Review', get(appt, 'subject', ''),
    'Line 30 col 15 should resolve to Overlapping Review')

  # Organizer line of slot 0 must also resolve (same appt_row).
  cursor(29, 15)
  appt = week_view.GetEventAtCursor()
  assert_equal('Team Meeting', get(appt, 'subject', ''),
    'Organizer line (29) should resolve to same appointment as subject line')

  # Separator lines and empty-slot rows must return {}.
  cursor(1, 15)
  assert_equal({}, week_view.GetEventAtCursor(),
    'Hour-0 slot row (no events) should return {}')

  # Time column (col < WEEK_TIME_COL + 2) must return {}.
  cursor(28, 3)
  assert_equal({}, week_view.GetEventAtCursor(),
    'Cursor on time column should return {}')
enddef

def g:Test_get_creation_slot_at_cursor()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  week_view.NavigateWeekView(2026, 7, 27)
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  # Empty hour 8 uses lines 25-26; Monday is the first day cell.
  cursor(25, 15)
  assert_equal({date: '2026-07-27', hour: 8},
    week_view.GetSlotAtCursor())

  # Tuesday is the second day cell.
  cursor(25, 31)
  assert_equal({date: '2026-07-28', hour: 8},
    week_view.GetSlotAtCursor())

  cursor(25, 3)
  assert_equal({}, week_view.GetSlotAtCursor(),
    'The time-label column is not an appointment slot')
enddef

def g:Test_manage_events_hook_requests()
  def g:TestManageEvents(request: dict<any>): bool
    g:manage_events_request = request
    return true
  enddef

  ResetConfig()
  g:calendar_config.diaries_dict.TestDiary.manage_events = 'g:TestManageEvents'
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  week_view.NavigateWeekView(2026, 7, 27)
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  cursor(25, 15)
  execute 'normal m'
  assert_equal({
    action: 'create',
    start: '2026-07-27 08:00',
    end: '2026-07-27 09:00',
  }, g:manage_events_request)

  t:cal_week_key = '2026-07-27'
  week_view.FetchEvents(2026, 7, 27)
  cursor(28, 15)
  execute 'normal m'
  assert_equal({action: 'edit', id: 'ENTRY-1'}, g:manage_events_request)

  execute 'normal d'
  assert_equal({
    action: 'delete',
    id: 'ENTRY-1',
    start: '2026-07-27T09:00:00',
  }, g:manage_events_request)

  execute 'normal a'
  assert_equal({
    action: 'accept',
    id: 'ENTRY-1',
    start: '2026-07-27T09:00:00',
  }, g:manage_events_request)

  execute 'normal v'
  assert_equal({
    action: 'tentative',
    id: 'ENTRY-1',
    start: '2026-07-27T09:00:00',
  }, g:manage_events_request)

  unlet g:manage_events_request
enddef

def g:Test_week_view_help_mapping()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  execute 'normal ?'
  WaitForAssert(() => assert_equal(1, len(popup_list())))
  assert_match('Week view key bindings',
    join(getbufline(winbufnr(popup_list()[0]), 1, '$'), "\n"))
  popup_close(popup_list()[0])
enddef

def g:Test_week_view_diary_cycle_tab_keys()
  ResetConfig()
  g:calendar_config.diaries_dict = {
    Alpha: {path: tempname(), fetch_events: 'g:TestFetchEvents'},
    Beta: {path: tempname(), fetch_events: 'g:TestFetchEvents'},
  }
  g:calendar_config.active_diary = 'Alpha'

  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  feedkeys("\<Tab>", 'xt')
  WaitForAssert(() => assert_equal('Beta', g:calendar_config.active_diary))
  assert_equal(week_view.WEEK_BUF_NAME, bufname('%'),
    'Cycling diaries from the week view must not move focus away from it')

  feedkeys("\<S-Tab>", 'xt')
  WaitForAssert(() => assert_equal('Alpha', g:calendar_config.active_diary))
  assert_equal(week_view.WEEK_BUF_NAME, bufname('%'))
enddef

# ── Configure / display-type / cell-width tests ──────────────────────────────

# Count the number of join characters ('┬' or '┼') in a separator line.
# Each join marks a column boundary; the count equals the number of day columns.
def CountJoins(line: string): number
  return len(split(line, '┬', 1)) - 1
enddef

# Return the first header line that contains '┬' (the top separator row).
def HeaderSepLine(hdr_lines: list<string>): string
  var hits = filter(copy(hdr_lines), 'v:val =~# "┬"')
  return empty(hits) ? '' : hits[0]
enddef

def g:Test_configure_work_display_type()
  ResetConfig()
  g:calendar_config.week_display_type = 'work'
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  t:cal_week_key = '2026-07-27'
  week_view.FetchEvents(2026, 7, 27)

  var hdr = BufLines(week_view.WEEK_HDR_BUF_NAME)

  # Header separator must have exactly 5 column joins (Mon–Fri).
  var sep = HeaderSepLine(hdr)
  assert_notequal('', sep, 'Header must have a ┬ separator line')
  assert_equal(5, CountJoins(sep), 'work mode must render exactly 5 day columns')

  # Day-label row must list weekdays but not weekend days.
  assert_true(HasLine(hdr, 'Friday'),   'Friday must appear in work-mode header')
  assert_false(HasLine(hdr, 'Saturday'), 'Saturday must not appear in work-mode header')
  assert_false(HasLine(hdr, 'Sunday'),   'Sunday must not appear in work-mode header')
enddef

def g:Test_configure_us_display_type()
  ResetConfig()
  g:calendar_config.week_display_type = 'us'
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  week_view.NavigateWeekView(2026, 7, 27)

  var hdr = BufLines(week_view.WEEK_HDR_BUF_NAME)

  # Still 7 columns, but Sunday leads.
  var sep = HeaderSepLine(hdr)
  assert_notequal('', sep, 'Header must have a ┬ separator line')
  assert_equal(7, CountJoins(sep), 'us mode must render 7 day columns')

  assert_true(HasLine(hdr, 'Sunday'),  'Sunday must appear in us-mode header')
  assert_true(HasLine(hdr, 'Monday'),  'Monday must appear in us-mode header')

  # Sunday cell must be leftmost — appears before Monday in the label row.
  var label_lines = filter(copy(hdr), 'v:val =~# "Sunday"')
  assert_false(empty(label_lines), 'Day-label row must contain Sunday')
  var sun_col = stridx(label_lines[0], 'Sunday')
  var mon_col = stridx(label_lines[0], 'Monday')
  assert_true(sun_col < mon_col, 'Sunday column must precede Monday in us mode')
enddef

def g:Test_us_display_uses_chronological_sunday_week()
  ResetConfig()
  g:calendar_config.week_display_type = 'us'
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))

  week_view.NavigateWeekView(2026, 7, 27)
  week_view.FetchEvents(2026, 7, 27)

  var hdr = BufLines(week_view.WEEK_HDR_BUF_NAME)
  var label_lines = filter(copy(hdr), 'v:val =~# "Sunday"')
  assert_false(empty(label_lines), 'US header must contain Sunday')
  assert_match('26, Sunday', label_lines[0],
    'US week containing Monday 27 July must start on Sunday 26 July')
  assert_match('27, Monday', label_lines[0],
    'Monday must follow the preceding Sunday')
  assert_true(HasLine(hdr, 'Company Offsite'),
    'All-day events must render in chronological US weeks')
  assert_equal('2026-07-26', t:cal_week_key,
    'US cache keys must use the displayed Sunday')
enddef

def g:Test_fetch_events_hook_uses_visible_range()
  ResetConfig()
  CalendarToggle 2020, 2
  WaitForAssert(() => assert_equal(3, winnr('$')))

  assert_equal({
    start: '2020-01-27',
    end: '2020-02-03',
  }, g:last_fetch_events_request)
  assert_equal('2020-01-27', t:cal_week_key,
    'Hook results must be cached under the requested range start')
enddef

def g:Test_fetch_events_ranges_follow_display_layout()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))

  week_view.Configure('us', 16)
  week_view.SetProviderFuncs('g:TestFetchEvents', '')
  week_view.FetchEvents(2026, 8, 5)
  assert_equal({
    start: '2026-08-02',
    end: '2026-08-09',
  }, g:last_fetch_events_request)

  week_view.Configure('work', 16)
  week_view.FetchEvents(2026, 8, 5)
  assert_equal({
    start: '2026-08-03',
    end: '2026-08-08',
  }, g:last_fetch_events_request)

  week_view.Configure('eu', 16)
  week_view.FetchEvents(2026, 12, 31)
  assert_equal({
    start: '2026-12-28',
    end: '2027-01-04',
  }, g:last_fetch_events_request)
enddef

def g:Test_configure_invalid_type_defaults_to_eu()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))

  # Reconfigure with an invalid type — must silently fall back to 'eu'.
  week_view.Configure('bogus', 16)
  week_view.NavigateWeekView(2026, 7, 27)

  var hdr = BufLines(week_view.WEEK_HDR_BUF_NAME)
  var sep = HeaderSepLine(hdr)
  assert_notequal('', sep, 'Header must have a ┬ separator line')
  assert_equal(7, CountJoins(sep), 'Invalid display type must fall back to eu (7 columns)')
enddef

def g:Test_configure_minimum_cell_width()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))

  # Width 3 is below the minimum of 8 — must be clamped.
  week_view.Configure('eu', 3)
  week_view.NavigateWeekView(2026, 7, 27)

  var hdr = BufLines(week_view.WEEK_HDR_BUF_NAME)
  var sep = HeaderSepLine(hdr)
  assert_notequal('', sep, 'Header must have a ┬ separator line')
  # First day cell is the second segment after splitting on '┬'.
  var first_day_cell = split(sep, '┬', 1)[1]
  assert_equal(8, strcharlen(first_day_cell),
    'Cell width must be clamped to 8 when a value below the minimum is given')
enddef

def g:Test_configure_custom_cell_width()
  ResetConfig()
  g:calendar_config.week_cell_width = 20
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  week_view.NavigateWeekView(2026, 7, 27)

  var hdr = BufLines(week_view.WEEK_HDR_BUF_NAME)
  var sep = HeaderSepLine(hdr)
  assert_notequal('', sep, 'Header must have a ┬ separator line')
  var first_day_cell = split(sep, '┬', 1)[1]
  assert_equal(20, strcharlen(first_day_cell),
    'Cell width must be 20 when week_cell_width = 20')
enddef

def g:Test_allday_events_work_mode()
  def g:TestAllDayManageEvents(request: dict<any>): bool
    g:allday_manage_request = request
    return true
  enddef

  ResetConfig()
  g:calendar_config.week_display_type = 'work'
  g:calendar_config.diaries_dict.TestDiary.manage_events =
    'g:TestAllDayManageEvents'
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  t:cal_week_key = '2026-07-27'
  week_view.FetchEvents(2026, 7, 27)

  var hdr = BufLines(week_view.WEEK_HDR_BUF_NAME)
  # Sprint Planning (Tue) and Company Offsite (Mon–Wed) both fall within Mon–Fri.
  assert_true(HasLine(hdr, 'Sprint Planning'), 'Sprint Planning must appear in work-mode header')
  assert_true(HasLine(hdr, 'Company Offsite'), 'Company Offsite must appear in work-mode header')
  # No weekend day labels in work mode.
  assert_false(HasLine(hdr, 'Saturday'), 'Saturday must not appear in work-mode header')
  assert_false(HasLine(hdr, 'Sunday'),   'Sunday must not appear in work-mode header')

  win_gotoid(win_findbuf(bufnr(week_view.WEEK_HDR_BUF_NAME))[0])
  cursor(search('Sprint Planning'), 1)
  assert_equal('ALLDAY-1', get(week_view.GetEventAtCursor(), 'id', ''))
  execute 'normal d'
  assert_equal({
    action: 'delete',
    id: 'ALLDAY-1',
    start: '2026-07-28T00:00:00',
  }, g:allday_manage_request)
  unlet g:allday_manage_request
enddef

def g:Test_calendar_wipe()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))

  CalendarWipe

  assert_equal(-1, bufnr('__Calendar__'),
    '__Calendar__ buffer must not exist after CalendarWipe')
  assert_equal(-1, bufnr(week_view.WEEK_BUF_NAME),
    '__WeekView__ buffer must not exist after CalendarWipe')
  assert_equal(-1, bufnr(week_view.WEEK_HDR_BUF_NAME),
    '__WeekHeader__ buffer must not exist after CalendarWipe')
enddef

def g:Test_week_view_next_prev_week_navigation()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  # Start on a known Monday.
  week_view.NavigateWeekView(2026, 7, 27)
  assert_equal('2026-07-27', t:cal_week_key)

  # Next week: 2026-08-03.
  CalendarWeekNav next
  assert_equal('2026-08-03', t:cal_week_key,
    '<C-Right> must advance to the next Monday')

  # Previous week twice: back to 2026-07-27.
  CalendarWeekNav prev
  CalendarWeekNav prev
  assert_equal('2026-07-20', t:cal_week_key,
    'Two prev navigations from 2026-08-03 must reach 2026-07-20')
enddef

def g:Test_week_view_today_navigation()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  # Navigate away, then go to today.
  week_view.NavigateWeekView(2020, 1, 6)
  assert_equal('2020-01-06', t:cal_week_key)

  CalendarWeekNav today
  var ty = str2nr(strftime('%Y'))
  var tm = str2nr(strftime('%m'))
  var td = str2nr(strftime('%d'))
  var mon = backend.WeekDays(ty, tm, td)[0]
  var expected_key = printf('%04d-%02d-%02d', mon.year, mon.month, mon.day)
  assert_equal(expected_key, t:cal_week_key,
    't in week view must navigate to today''s week')
  assert_equal(str2nr(strftime('%V')), t:cal_curr_week_num,
    't:cal_curr_week_num must reflect today''s ISO week number')
enddef

def g:Test_week_view_navigation_syncs_left_pane()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  # Navigate to a week far from today so the left pane must update.
  week_view.NavigateWeekView(2026, 7, 27)

  CalendarWeekNav next   # → 2026-08-03

  # Left pane must now show August 2026.
  var cal_lines = BufLines('__Calendar__')
  assert_true(HasLine(cal_lines, 'August'),
    'Left pane must show August after navigating to 2026-08-03')
enddef

def g:Test_reschedule_reminders_uses_cache()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  # RescheduleReminders must not throw even when cache has no today entry.
  week_view.RescheduleReminders()
enddef

def g:Test_reschedule_reminders_schedules_todays_meetings()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  # Inject a future meeting directly into the week cache via the fetch hook,
  # but point cal_week_key at today's week so RescheduleReminders finds it.
  var ty = str2nr(strftime('%Y'))
  var tm = str2nr(strftime('%m'))
  var td = str2nr(strftime('%d'))
  var mon = backend.WeekDays(ty, tm, td)[0]
  var today_key = strftime('%Y-%m-%d')
  var future_h = str2nr(strftime('%H')) + 3
  if future_h >= 24 | return | endif  # skip near midnight

  # Write a temp JSON with a meeting 3 hours from now and load it.
  var meeting_start = printf('%s T%02d:00:00', today_key, future_h)->substitute(' ', '', 'g')
  var meeting_end   = printf('%s T%02d:30:00', today_key, future_h)->substitute(' ', '', 'g')
  var appt_json = json_encode([{
    start:     meeting_start,
    end:       meeting_end,
    subject:   'Future Meeting',
    organizer: 'Test',
    location:  '',
    body:      '',
    id:        'FUTURE_EID',
    allday:    false,
  }])
  var tmp = tempname() .. '.json'
  writefile([appt_json], tmp)
  t:cal_fetch_events_func = 'g:TestFetchEvents'
  t:cal_week_key = printf('%04d-%02d-%02d', mon.year, mon.month, mon.day)
  # Use LoadAppointments indirectly via the fetch hook by overwriting the fixture.
  # Simpler: call RescheduleReminders after manually populating the cache via
  # the public LoadAppointments path (FetchEvents reads the fixture file).
  # Direct injection: write our JSON to the temp path and call the hook.
  week_view.SetProviderFuncs('g:TestFetchEvents', '')

  # Produce a temp file with our single-meeting JSON and read it as the hook output.
  writefile([appt_json], tmp)
  def g:TmpFetchEvents(_request: dict<any>): string
    return tmp
  enddef
  week_view.SetProviderFuncs('g:TmpFetchEvents', '')
  week_view.FetchEvents(ty, tm, td)
  week_view.RescheduleReminders()

  assert_true(reminder.PendingCount() >= 1,
    'RescheduleReminders must create a timer for a future meeting today')
  reminder.CancelAll()
enddef

def g:Test_reschedule_reminders_cancels_stale_timers()
  var future_min = str2nr(strftime('%H')) * 60
    + str2nr(strftime('%M')) + 30
  if future_min >= 24 * 60 | return | endif

  reminder.Schedule(strftime('%Y-%m-%d'), [{
    start: printf('%02d:%02d', future_min / 60, future_min % 60),
    end: printf('%02d:%02d', (future_min + 30) / 60,
      (future_min + 30) % 60),
    subject: 'Removed Meeting',
    id: 'REMOVED_EID',
  }])
  assert_equal(2, reminder.PendingCount())

  week_view.SetProviderFuncs('g:TestFetchEvents', '')
  week_view.RescheduleReminders()
  assert_equal(0, reminder.PendingCount(),
    'Refreshing to an empty cache must cancel obsolete reminders')
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
