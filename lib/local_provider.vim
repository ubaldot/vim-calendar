vim9script

# Built-in JSON event provider used when a diary defines no provider hooks.

import autoload "./backend.vim"

var events_path = ''
var address_book_path = ''

def DefaultDataDir(): string
  if has('win32') && !empty($LOCALAPPDATA)
    return $'{$LOCALAPPDATA}/vim-calendar'
  endif
  if !empty($XDG_DATA_HOME)
    return $'{$XDG_DATA_HOME}/vim-calendar'
  endif
  return expand('~/.local/share/vim-calendar')
enddef

export def Configure(diary_name: string, configured_path: string = '',
                     configured_address_book: string = '')
  address_book_path = configured_address_book
  if !empty(configured_path)
    events_path = expand(configured_path)
    return
  endif
  var safe_name = substitute(diary_name, '[^A-Za-z0-9_.-]', '_', 'g')
  events_path = DefaultDataDir() .. $'/{safe_name}-events.json'
enddef

export def EventsPath(): string
  return events_path
enddef

def ReadEvents(path: string = ''): dict<any>
  var source = empty(path) ? events_path : path
  if empty(source) || !filereadable(source)
    return {ok: true, events: []}
  endif
  try
    var decoded = json_decode(readfile(source)->join("\n"))
    if type(decoded) != v:t_list
      echomsg '[Calendar] Local events file must contain a JSON list.'
      return {ok: false, events: []}
    endif
    return {ok: true, events: decoded}
  catch
    echomsg $'[Calendar] Could not read local events: {v:exception}'
    return {ok: false, events: []}
  endtry
enddef

def WriteEvents(events: list<any>, path: string = ''): bool
  var destination = empty(path) ? events_path : path
  var parent = fnamemodify(destination, ':h')
  var temporary = destination .. $'.tmp-{localtime()}-{rand()}'
  var backup = destination .. $'.bak-{localtime()}-{rand()}'
  try
    if !isdirectory(parent)
      mkdir(parent, 'p')
    endif
    writefile([json_encode(events)], temporary)
    if rename(temporary, destination) != 0
      if filereadable(destination) && rename(destination, backup) != 0
        throw 'could not preserve the existing events file'
      endif
      if rename(temporary, destination) != 0
        if filereadable(backup)
          rename(backup, destination)
        endif
        throw 'could not replace the events file'
      endif
      delete(backup)
    endif
    return true
  catch
    delete(temporary)
    if !filereadable(destination) && filereadable(backup)
      rename(backup, destination)
    endif
    echoerr $'[Calendar] Could not write local events: {v:exception}'
    return false
  endtry
enddef

def FindIndexById(events: list<any>, target: string): number
  for i in range(len(events))
    if type(events[i]) == v:t_dict && get(events[i], 'id', '') ==# target
      return i
    endif
  endfor
  return -1
enddef

# Return a disposable snapshot because vim-calendar deletes fetched files.
export def FetchEvents(_request: dict<any>): string
  var result = ReadEvents()
  if !result.ok
    return ''
  endif
  var snapshot = tempname() .. '.json'
  writefile([json_encode(result.events)], snapshot)
  return snapshot
enddef

# ─── Create/edit form ───────────────────────────────────────────────────────
#
# Instead of prompting field-by-field on the command line, create/edit opens
# a small split buffer prefilled with the event's fields. The user edits the
# fields as plain text and saves with `:w`; a BufWriteCmd autocmd parses the
# buffer, validates it, and persists the event to the local JSON file.

export const FORM_BUF_NAME = '__CalendarEventForm__'

var form_existing: dict<any> = {}
var form_events_path = ''

def ParseFormLines(lines: list<string>): dict<string>
  var fields: dict<string> = {}
  for i in range(len(lines))
    var line = lines[i]
    var idx = stridx(line, ':')
    if idx <= 0
      continue
    endif
    var name = trim(line[0 : idx - 1])
    if name ==# 'Body'
      fields.Body = trim(line[idx + 1 :])
      if i + 1 < len(lines)
        fields.Body ..= "\n" .. join(lines[i + 1 :], "\n")
      endif
      break
    endif
    if index(['Title', 'Start', 'End', 'Required Attendees',
        'Optional Attendees', 'Organizer', 'Location', 'AllDay'], name) >= 0
      fields[name] = trim(line[idx + 1 :])
    endif
  endfor
  return fields
enddef

def BuildEventFromForm(fields: dict<string>): dict<any>
  var subject = get(fields, 'Title', '')
  if empty(trim(subject))
    echoerr '[Calendar] Title is required.'
    return {}
  endif
  var start = get(fields, 'Start', '')
  var end = get(fields, 'End', '')
  if start !~# '^\d\{4}-\d\{2}-\d\{2} \d\{2}:\d\{2}$'
      || end !~# '^\d\{4}-\d\{2}-\d\{2} \d\{2}:\d\{2}$'
    echoerr '[Calendar] Start and end must use YYYY-MM-DD HH:MM.'
    return {}
  endif
  var allday = tolower(get(fields, 'AllDay',
    string(get(form_existing, 'allday', false))))
  if allday !=# 'true' && allday !=# 'false'
    echoerr '[Calendar] AllDay must be true or false.'
    return {}
  endif
  var is_allday = allday ==# 'true'
  if is_allday
    var start_date = start[0 : 9]
    var end_date = end[0 : 9]
    if end_date < start_date
      echoerr '[Calendar] All-day end date must not precede its start date.'
      return {}
    endif
    if end_date ==# start_date
      var parts = split(start_date, '-')
      var next = backend.JDNToDate(backend.DateToJDN(
        str2nr(parts[0]), str2nr(parts[1]), str2nr(parts[2])) + 1)
      end_date = printf('%04d-%02d-%02d', next.year, next.month, next.day)
    endif
    start = start_date .. ' 00:00'
    end = end_date .. ' 00:00'
  elseif end <=# start
    echoerr '[Calendar] End must be after start.'
    return {}
  endif
  return {
    id: get(form_existing, 'id', $'local-{localtime()}-{rand()}'),
    start: substitute(start, ' ', 'T', ''),
    end: substitute(end, ' ', 'T', ''),
    subject: subject,
    required_attendees: get(fields, 'Required Attendees',
      get(form_existing, 'required_attendees', '')),
    optional_attendees: get(fields, 'Optional Attendees',
      get(form_existing, 'optional_attendees', '')),
    organizer: get(fields, 'Organizer',
      get(form_existing, 'organizer', '')),
    location: get(fields, 'Location', ''),
    body: get(fields, 'Body', get(form_existing, 'body', '')),
    allday: is_allday,
  }
enddef

def FormDateTime(value: string): string
  return strpart(substitute(value, 'T', ' ', ''), 0, 16)
enddef

def FormLines(existing: dict<any>): list<string>
  var body = split(get(existing, 'body', ''), "\n", true)
  var lines = [
    $'Title: {get(existing, "subject", "")}',
    $'Start: {FormDateTime(get(existing, "start", ""))}',
    $'End: {FormDateTime(get(existing, "end", ""))}',
    $'Required Attendees: {get(existing, "required_attendees", "")}',
    $'Optional Attendees: {get(existing, "optional_attendees", "")}',
    $'Organizer: {get(existing, "organizer", "")}',
    $'Location: {get(existing, "location", "")}',
    $'AllDay: {string(get(existing, "allday", false))}',
    $'Body: {empty(body) ? "" : body[0]}',
  ]
  if len(body) > 1
    lines->extend(body[1 :])
  endif
  return lines
enddef

def FormHelpFilter(id: number, key: string): bool
  if key ==# 'q' || key ==# "\<Esc>" || key ==# '?'
    popup_close(id)
    return true
  endif
  return false
enddef

def ShowFormHelp()
  popup_create([
    'Calendar event form',
    '',
    'Title       required',
    'Start       required, YYYY-MM-DD HH:MM',
    'End         required, YYYY-MM-DD HH:MM',
    'Required Attendees  optional; CTRL-X CTRL-O completes entries',
    'Optional Attendees  optional; CTRL-X CTRL-O completes entries',
    'Organizer   optional',
    'Location    optional',
    'AllDay      true or false; times are ignored',
    'Body        optional; continuation lines are supported',
    '',
    'The event ID is generated and preserved automatically.',
    'W saves; Q discards; ? or q closes this help.',
  ], {
    title: ' Event Form Help ',
    border: [1, 1, 1, 1],
    borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    filter: FormHelpFilter,
    mapping: 0,
  })
enddef

# BufWriteCmd handler for the event form buffer. Keeps the buffer open (and
# modified) when validation fails, so the user can fix the offending field.
def SaveForm()
  var form_bufnr = bufnr()
  var event = BuildEventFromForm(ParseFormLines(getline(1, '$')))
  if empty(event)
    return
  endif

  var read_result = ReadEvents(form_events_path)
  if !read_result.ok
    return
  endif
  var events = read_result.events
  var existing_id = get(form_existing, 'id', '')
  if !empty(existing_id)
    var index = FindIndexById(events, existing_id)
    if index < 0
      echoerr $'[Calendar] Local event not found: {existing_id}'
      return
    endif
    events[index] = event
  else
    events->add(event)
  endif

  if !WriteEvents(events, form_events_path)
    return
  endif

  setbufvar(form_bufnr, '&modified', 0)
  g:calendar_event = deepcopy(event)
  execute empty(existing_id)
    ? 'silent! doautocmd User CalendarEventCreated'
    : 'silent! doautocmd User CalendarEventModified'
  echo empty(existing_id)
    ? '[Calendar] Local event created.'
    : '[Calendar] Local event updated.'
  if exists(':CalendarRefresh') == 2
    execute 'CalendarRefresh'
  endif
  if bufexists(form_bufnr)
    execute $'bwipeout! {form_bufnr}'
  endif
enddef

def OpenForm(existing: dict<any>): bool
  var bn = bufnr(FORM_BUF_NAME)
  if bn > 0
    if getbufvar(bn, '&modified')
      var windows = win_findbuf(bn)
      if !empty(windows)
        win_gotoid(windows[0])
      endif
      echo '[Calendar] Save or discard the open event form first.'
      return false
    endif
    execute $'bwipeout! {bn}'
  endif

  form_existing = existing
  form_events_path = events_path

  belowright split
  enew
  execute $'file {FORM_BUF_NAME}'
  setlocal buftype=acwrite bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber
  setlocal omnifunc=CalendarAddressBookComplete
  b:calendar_address_book_path = address_book_path

  setline(1, FormLines(existing))
  setlocal nomodified

  augroup CalendarEventForm
    autocmd! * <buffer>
    autocmd BufWriteCmd <buffer> SaveForm()
  augroup END

  nnoremap <silent> <buffer> W <ScriptCmd>SaveForm()<CR>
  nnoremap <silent> <buffer> Q <Cmd>bwipeout!<CR>
  nnoremap <silent> <buffer> ? <ScriptCmd>ShowFormHelp()<CR>
  echo '[Calendar] Edit fields, press W to save, Q to discard, or ? for help.'
  return true
enddef

export def ManageEvents(request: dict<any>): bool
  var action = get(request, 'action', '')
  if action ==# 'create'
    return OpenForm({
      start: get(request, 'start', ''),
      end: get(request, 'end', ''),
    })
  elseif action ==# 'edit'
    var target = get(request, 'id', '')
    var read_result = ReadEvents()
    if !read_result.ok
      return false
    endif
    var events = read_result.events
    var index = FindIndexById(events, target)
    if index < 0
      echoerr $'[Calendar] Local event not found: {target}'
      return false
    endif
    return OpenForm(events[index])
  elseif action ==# 'delete'
    var target = get(request, 'id', '')
    var read_result = ReadEvents()
    if !read_result.ok
      return false
    endif
    var events = read_result.events
    var index = FindIndexById(events, target)
    if index < 0
      echoerr $'[Calendar] Local event not found: {target}'
      return false
    endif
    remove(events, index)
    if !WriteEvents(events)
      return false
    endif
    if exists(':CalendarRefresh') == 2
      execute 'CalendarRefresh'
    endif
    echo '[Calendar] Local event deleted.'
    return true
  elseif action ==# 'accept' || action ==# 'tentative'
    echo $'[Calendar] The local provider does not support {action} responses.'
    return false
  else
    echoerr $'[Calendar] Unknown event action: {action}'
    return false
  endif
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
