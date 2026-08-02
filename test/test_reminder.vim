vim9script

import autoload '../lib/reminder.vim'

const TODAY = strftime('%Y-%m-%d')

# Meeting starting `offset_hours` from now (always beyond the 15-min window).
# Returns {} when the meeting would fall past midnight — tests skip in that case.
def g:FutureMeeting(offset_hours: number = 3, event_id: string = 'ID1'): dict<any>
  var h = str2nr(strftime('%H')) + offset_hours
  if h >= 24
    return {}
  endif
  return {
    start:     printf('%02d:00', h),
    end:       printf('%02d:30', h),
    subject:   'Test Meeting',
    organizer: 'Org Person',
    location:  'Room A',
    id:        event_id,
  }
enddef

# Meeting that ended one hour ago.
def g:PastMeeting(): dict<any>
  var h = max([0, str2nr(strftime('%H')) - 1])
  return {start: printf('%02d:00', h), end: printf('%02d:30', h),
          subject: 'Past', id: 'PAST1'}
enddef

# ── Tests ─────────────────────────────────────────────────────────────────────

def g:Test_reminder_schedule_creates_timer_for_future_meeting()
  var m = g:FutureMeeting()
  if empty(m) | return | endif
  reminder.Schedule(TODAY, [m])
  assert_equal(2, reminder.PendingCount())  # |pre and |now
  reminder.CancelAll()
enddef

def g:Test_reminder_schedule_skips_past_meeting()
  reminder.Schedule(TODAY, [g:PastMeeting()])
  assert_equal(0, reminder.PendingCount())
enddef

def g:Test_reminder_schedule_multiple_meetings()
  var m1 = g:FutureMeeting(2, 'EID_A')
  var m2 = g:FutureMeeting(4, 'EID_B')
  if empty(m1) || empty(m2) | return | endif
  reminder.Schedule(TODAY, [m1, m2])
  assert_equal(4, reminder.PendingCount())  # 2 timers × 2 meetings
  reminder.CancelAll()
enddef

def g:Test_reminder_cancel_all_clears_pending()
  var m = g:FutureMeeting()
  if empty(m) | return | endif
  reminder.Schedule(TODAY, [m])
  reminder.CancelAll()
  assert_equal(0, reminder.PendingCount())
enddef

def g:Test_reminder_reschedule_cancels_previous_timers()
  var m = g:FutureMeeting()
  if empty(m) | return | endif
  reminder.Schedule(TODAY, [m])
  reminder.Schedule(TODAY, [m])   # reschedule same meeting
  assert_equal(2, reminder.PendingCount())  # not 4
  reminder.CancelAll()
enddef

def g:Test_reminder_empty_meeting_list_no_timers()
  reminder.Schedule(TODAY, [])
  assert_equal(0, reminder.PendingCount())
enddef

def g:Test_reminder_meeting_missing_start_is_skipped()
  reminder.Schedule(TODAY, [{subject: 'No time', id: 'X'}])
  assert_equal(0, reminder.PendingCount())
enddef

def g:Test_reminder_set_sound_enabled_does_not_crash()
  reminder.SetSoundEnabled(false)
  reminder.SetSoundEnabled(true)
enddef

def g:Test_reminder_within_15min_window_fires_immediately()
  # A meeting starting in 10 min is inside the 15-min window: |pre fires 500ms,
  # |now fires at the exact remaining delay. Both timers must be pending.
  var now_h = str2nr(strftime('%H'))
  var now_m = str2nr(strftime('%M'))
  var meet_min = now_h * 60 + now_m + 10
  if meet_min >= 24 * 60 | return | endif
  var m = {
    start:   printf('%02d:%02d', meet_min / 60, meet_min % 60),
    end:     printf('%02d:%02d', (meet_min + 30) / 60, (meet_min + 30) % 60),
    subject: 'Soon',
    id: 'SOON1',
  }
  reminder.Schedule(TODAY, [m])
  assert_equal(2, reminder.PendingCount())
  reminder.CancelAll()
enddef

def g:Test_reminder_reschedule_does_not_repeat_fired_warning()
  reminder.SetSoundEnabled(false)
  var now_min = str2nr(strftime('%H')) * 60 + str2nr(strftime('%M'))
  var meet_min = now_min + 10
  if meet_min >= 24 * 60 | return | endif
  var meeting = {
    start: printf('%02d:%02d', meet_min / 60, meet_min % 60),
    end: printf('%02d:%02d', (meet_min + 30) / 60, (meet_min + 30) % 60),
    subject: 'Deduplicated warning',
    id: 'DEDUPE_WARNING',
  }

  reminder.Schedule(TODAY, [meeting])
  sleep 700m
  assert_equal(1, len(popup_list()),
    'The first pre-start warning must create one popup')

  reminder.Schedule(TODAY, [meeting])
  assert_equal(1, reminder.PendingCount(),
    'Only the unfired start-time timer should remain after rescheduling')
  sleep 700m
  assert_equal(1, len(popup_list()),
    'Rescheduling must not create another pre-start popup')

  reminder.CancelAll()
  reminder.SetSoundEnabled(true)
enddef
