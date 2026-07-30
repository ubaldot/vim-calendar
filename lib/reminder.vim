vim9script

# Meeting reminders via one-shot timers — no periodic polling.
#
# Two popups per meeting:
#   1. 15 min before start  → "Starting in 15 min"
#   2. At start time        → "Starting NOW!"
#
# Popup shows subject, time, organizer, room.
# Keys in the popup:
#   Esc  – snooze 5 min (new timer; dismissed check still blocks it if 'd' was hit)
#   d    – dismiss: cancels both remaining timers for this meeting today
#
# Sound: PowerShell SystemAsterisk on win32; afplay on mac; silent elsewhere.
#
# Integration:
#   week_view.RescheduleReminders calls Schedule(today_key, meetings)
#   frontend.CalendarWipe         calls CancelAll()
#   frontend.InitVariables        calls SetSoundEnabled(bool)

var scheduled:   dict<number> = {}  # timer_key → timer_id
var dismissed:   dict<bool>   = {}  # base_key  → true (blocks all timers for that meeting)
var sound_enabled = true
var popup_zindex  = 200             # incremented per popup so simultaneous ones stack visibly

# Stable, day-scoped identity key for a meeting.
# Uses entryid when available; falls back to start|subject.
def MeetingKey(date_key: string, meeting: dict<any>): string
  var eid = get(meeting, 'entryid', '')
  return date_key .. '|' ..
    (!empty(eid) ? eid : get(meeting, 'start', '') .. '|' .. get(meeting, 'subject', ''))
enddef

export def SetSoundEnabled(v: bool)
  sound_enabled = v
enddef

# Cancel all pending reminder timers.
export def CancelAll()
  for [_, tid] in items(scheduled)
    timer_stop(tid)
  endfor
  scheduled = {}
enddef

# Number of pending timers (2 per meeting normally) — exported for tests.
export def PendingCount(): number
  return len(scheduled)
enddef

# Schedule two timers per meeting: one at (start − 15 min), one at start.
# Timer keys: base_key|pre and base_key|now.
# dismissed uses base_key so pressing 'd' on either popup cancels both.
# Accepts list<any> to match the week_cache value type (list<any> per date key).
export def Schedule(date_key: string, meetings: list<any>)
  CancelAll()
  dismissed = {}

  var now_min = str2nr(strftime('%H')) * 60 + str2nr(strftime('%M'))
  var now_sec = str2nr(strftime('%S'))

  for meeting in meetings
    if type(meeting) != v:t_dict
      continue
    endif
    var m: dict<any> = meeting
    var start = get(m, 'start', '')
    if empty(start)
      continue
    endif
    var parts = split(start, ':')
    if len(parts) < 2
      continue
    endif

    var meet_min = str2nr(parts[0]) * 60 + str2nr(parts[1])

    # Skip meetings that have already started.
    if meet_min <= now_min
      continue
    endif

    var base_key  = MeetingKey(date_key, m)
    var key_pre   = base_key .. '|pre'
    var key_now   = base_key .. '|now'

    var delay_pre = (meet_min - 15 - now_min) * 60000 - now_sec * 1000
    var delay_now = (meet_min      - now_min) * 60000 - now_sec * 1000

    # |pre timer: fires 15 min before start (or immediately if already inside window).
    if delay_pre > 0
      scheduled[key_pre] = timer_start(delay_pre,
        function(FireReminder, [date_key, base_key, key_pre, m]))
    else
      scheduled[key_pre] = timer_start(500,
        function(FireReminder, [date_key, base_key, key_pre, m]))
    endif

    # |now timer: fires exactly at start time.
    scheduled[key_now] = timer_start(max([500, delay_now]),
      function(FireReminder, [date_key, base_key, key_now, m]))
  endfor
enddef

def FireReminder(date_key: string, base_key: string, timer_key: string,
                 meeting: dict<any>, _timer: number)
  if has_key(scheduled, timer_key)
    remove(scheduled, timer_key)
  endif
  if get(dismissed, base_key, false)
    return
  endif

  var now_min  = str2nr(strftime('%H')) * 60 + str2nr(strftime('%M'))
  var parts    = split(get(meeting, 'start', '00:00'), ':')
  var meet_min = str2nr(parts[0]) * 60 + str2nr(parts[1])
  var mins_left = max([0, meet_min - now_min])

  PlaySound()
  ShowReminderPopup(date_key, base_key, meeting, mins_left)
enddef

def PlaySound()
  if !sound_enabled
    return
  endif
  if has('win32')
    job_start(['powershell', '-NoProfile', '-WindowStyle', 'Hidden',
               '-Command', '[System.Media.SystemSounds]::Asterisk.Play()'],
              {out_io: 'null', err_io: 'null'})
  elseif has('mac')
    job_start(['afplay', '/System/Library/Sounds/Glass.aiff'],
              {out_io: 'null', err_io: 'null'})
  endif
enddef

def ShowReminderPopup(date_key: string, base_key: string,
                      meeting: dict<any>, minutes_left: number)
  var subj  = get(meeting, 'subject',   '(no title)')
  var start = get(meeting, 'start',     '')
  var end_  = get(meeting, 'end',       '')
  var org   = get(meeting, 'organizer', '')
  var loc   = get(meeting, 'location',  '')

  var when_str = minutes_left == 0 ? 'NOW!' : $'in {minutes_left} min'

  var lines: list<string> = ['']
  lines->add('  ' .. subj)
  if !empty(start)
    lines->add('  ' .. start .. (!empty(end_) ? ' – ' .. end_ : ''))
  endif
  if !empty(org)
    lines->add('  ' .. org)
  endif
  if !empty(loc)
    lines->add('  ' .. loc)
  endif
  lines->add('')
  lines->add('  Esc: snooze 5 min   d: dismiss')
  lines->add('')

  popup_zindex += 1
  popup_create(lines, {
    title:       ' 🔔 Starting ' .. when_str .. ' ',
    border:      [1, 1, 1, 1],
    borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    pos:         'center',
    zindex:      popup_zindex,
    filter:      function(ReminderFilter, [date_key, base_key, meeting]),
    mapping:     0,
  })
enddef

def ReminderFilter(date_key: string, base_key: string, meeting: dict<any>,
                   id: number, pressed: string): bool
  if pressed ==# 'd'
    # Dismiss: cancel any still-pending timer for this meeting and suppress future ones.
    dismissed[base_key] = true
    for suffix in ['|pre', '|now']
      var k = base_key .. suffix
      if has_key(scheduled, k)
        timer_stop(scheduled[k])
        remove(scheduled, k)
      endif
    endfor
    popup_close(id)
    return true
  elseif pressed ==# "\<Esc>"
    # Snooze: reopen in 5 min with a unique key so it doesn't collide.
    popup_close(id)
    var snooze_key = base_key .. '|snooze_' .. localtime()
    var m = copy(meeting)
    scheduled[snooze_key] = timer_start(300000,
      function(FireReminder, [date_key, base_key, snooze_key, m]))
    return true
  endif
  return false
enddef
