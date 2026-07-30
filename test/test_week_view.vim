vim9script

import "./common.vim"
var WaitForAssert = common.WaitForAssert

packadd CalendarToggle
import autoload "../lib/week_view.vim"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Connect function used by tests: copies the fixture JSON to a temp file and
# returns its path (which LoadAppointments will consume and delete).
def g:TestWeekConnect(year: number, month: number, day: number): string
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
        connect: 'g:TestWeekConnect',
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
enddef

def g:Test_week_view_t_variables_initialized()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])
  assert_true(has_key(t:, 'cal_curr_week_num'),
    't:cal_curr_week_num must be set in calendar tab')
  assert_true(has_key(t:, 'cal_connect_func'),
    't:cal_connect_func must be set in calendar tab')
  assert_equal('g:TestWeekConnect', t:cal_connect_func)
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

  # Navigate to the fixture week and trigger the connect hook.
  t:cal_week_key = '2026-07-27'
  week_view.CallConnectHook(2026, 7, 27)

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
  week_view.CallConnectHook(2026, 7, 27)

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
  week_view.CallConnectHook(2026, 7, 27)

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
  var today_key_prefix = strftime('%Y-%m-')
  assert_match($'^{today_key_prefix}', t:cal_week_key)
  assert_equal(str2nr(strftime('%V')), t:cal_curr_week_num)
enddef

def g:Test_get_appointment_at_cursor()
  ResetConfig()
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))

  # Load fixture appointments for week 2026-07-27.
  t:cal_week_key = '2026-07-27'
  week_view.CallConnectHook(2026, 7, 27)

  win_gotoid(win_findbuf(bufnr(week_view.WEEK_BUF_NAME))[0])

  # Hours 0-8: 9 empty hours × 3 lines (1 slot × 2 rows + separator) = 27 lines.
  # Hour 9 has 2 overlapping events on Monday (col 0):
  #   slot 0 subject  → line 28  (Team Meeting)
  #   slot 0 organizer → line 29
  #   slot 1 subject  → line 30  (Overlapping Review)
  # Col 15 is safely within the Monday cell (cols 10-25, WEEK_TIME_COL=8, WEEK_DAY_COL=16).
  cursor(28, 15)
  var appt = week_view.GetAppointmentAtCursor()
  assert_equal('Team Meeting', get(appt, 'subject', ''),
    'Line 28 col 15 should resolve to Team Meeting')

  cursor(30, 15)
  appt = week_view.GetAppointmentAtCursor()
  assert_equal('Overlapping Review', get(appt, 'subject', ''),
    'Line 30 col 15 should resolve to Overlapping Review')

  # Organizer line of slot 0 must also resolve (same appt_row).
  cursor(29, 15)
  appt = week_view.GetAppointmentAtCursor()
  assert_equal('Team Meeting', get(appt, 'subject', ''),
    'Organizer line (29) should resolve to same appointment as subject line')

  # Separator lines and empty-slot rows must return {}.
  cursor(1, 15)
  assert_equal({}, week_view.GetAppointmentAtCursor(),
    'Hour-0 slot row (no events) should return {}')

  # Time column (col < WEEK_TIME_COL + 2) must return {}.
  cursor(28, 3)
  assert_equal({}, week_view.GetAppointmentAtCursor(),
    'Cursor on time column should return {}')
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
  week_view.CallConnectHook(2026, 7, 27)

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
  ResetConfig()
  g:calendar_config.week_display_type = 'work'
  CalendarToggle
  WaitForAssert(() => assert_equal(3, winnr('$')))
  t:cal_week_key = '2026-07-27'
  week_view.CallConnectHook(2026, 7, 27)

  var hdr = BufLines(week_view.WEEK_HDR_BUF_NAME)
  # Sprint Planning (Tue) and Company Offsite (Mon–Wed) both fall within Mon–Fri.
  assert_true(HasLine(hdr, 'Sprint Planning'), 'Sprint Planning must appear in work-mode header')
  assert_true(HasLine(hdr, 'Company Offsite'), 'Company Offsite must appear in work-mode header')
  # No weekend day labels in work mode.
  assert_false(HasLine(hdr, 'Saturday'), 'Saturday must not appear in work-mode header')
  assert_false(HasLine(hdr, 'Sunday'),   'Sunday must not appear in work-mode header')
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

# vim: shiftwidth=2 softtabstop=2 noexpandtab
