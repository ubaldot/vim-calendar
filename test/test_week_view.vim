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
  win_gotoid(win_findbuf(bufnr('__Calendar'))[0])
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

# vim: shiftwidth=2 softtabstop=2 noexpandtab
