vim9script

# Meeting reminders via one-shot timers — no periodic polling.
#
# For each today meeting a timer fires at (start − 15 min).
# Popup shows subject, time, organizer, and room.
#
#   Esc  – snooze: a new one-shot timer fires in 5 minutes
#   d    – dismiss: no further timer for this meeting today
#
# Sound: PowerShell SystemAsterisk on win32; afplay on mac; silent elsewhere.
#
# Integration:
#   week_view.LoadAppointments calls Schedule(today_key, meetings)
#   frontend.CalendarWipe      calls CancelAll()
#   frontend.InitVariables     calls SetSoundEnabled(bool)

var scheduled:    dict<number> = {}   # day-scoped key → timer_id
var dismissed:    dict<bool>   = {}   # day-scoped key → true
var sound_enabled = true

# Stable, day-scoped key for a meeting.
# Uses entryid when available; falls back to start|subject.
def MeetingKey(date_key: string, meeting: dict<any>): string
  var eid = get(meeting, 'entryid', '')
  return date_key .. '|' ..
    (!empty(eid) ? eid : get(meeting, 'start', '') .. '|' .. get(meeting, 'subject', ''))
enddef

export def SetSoundEnabled(v: bool)
  sound_enabled = v
enddef

# Cancel all pending reminder timers and clear the schedule.
export def CancelAll()
  for [_, tid] in items(scheduled)
    timer_stop(tid)
  endfor
  scheduled = {}
enddef

# Number of pending timers — exported for tests.
export def PendingCount(): number
  return len(scheduled)
enddef

# Schedule one-shot reminder timers for today's meetings.
# Accepts list<any> so it can be called directly from the week_cache
# without a type-cast (cache stores list<any> per date key).
# Meetings already past the 15-min mark but not yet started get a 500 ms
# timer so the popup fires almost immediately.
# Resets dismissed state — new schedule means fresh day data.
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
    var key      = MeetingKey(date_key, m)

    var delay_ms = (meet_min - 15 - now_min) * 60000 - now_sec * 1000

    if delay_ms <= 0
      # Past the 15-min mark — still show if meeting hasn't started yet.
      if meet_min > now_min
        scheduled[key] = timer_start(500, function(FireReminder, [date_key, key, m]))
      endif
      continue
    endif

    scheduled[key] = timer_start(delay_ms, function(FireReminder, [date_key, key, m]))
  endfor
enddef

def FireReminder(date_key: string, key: string, meeting: dict<any>, _timer: number)
  if has_key(scheduled, key)
    remove(scheduled, key)
  endif
  if get(dismissed, key, false)
    return
  endif

  var now_min  = str2nr(strftime('%H')) * 60 + str2nr(strftime('%M'))
  var parts    = split(get(meeting, 'start', '00:00'), ':')
  var meet_min = str2nr(parts[0]) * 60 + str2nr(parts[1])

  PlaySound()
  ShowReminderPopup(date_key, key, meeting, max([0, meet_min - now_min]))
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

def ShowReminderPopup(date_key: string, key: string, meeting: dict<any>, minutes_left: number)
  var subj  = get(meeting, 'subject',   '(no title)')
  var start = get(meeting, 'start',     '')
  var end_  = get(meeting, 'end',       '')
  var org   = get(meeting, 'organizer', '')
  var loc   = get(meeting, 'location',  '')

  var when_str = minutes_left == 0 ? 'now' : $'in {minutes_left} min'

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

  popup_create(lines, {
    title:       ' 🔔 Starting ' .. when_str .. ' ',
    border:      [1, 1, 1, 1],
    borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    pos:         'center',
    zindex:      200,
    filter:      function(ReminderFilter, [date_key, key, meeting]),
    mapping:     0,
  })
enddef

def ReminderFilter(date_key: string, key: string, meeting: dict<any>, id: number, pressed: string): bool
  if pressed ==# 'd'
    dismissed[key] = true
    popup_close(id)
    return true
  elseif pressed ==# "\<Esc>"
    popup_close(id)
    var m = copy(meeting)
    scheduled[key] = timer_start(300000, function(FireReminder, [date_key, key, m]))
    return true
  endif
  return false
enddef
