vim9script

import "./common.vim"
var WaitForAssert = common.WaitForAssert

packadd CalendarToggle
import autoload "../lib/calendar_view.vim"
import autoload "../lib/frontend.vim"
import autoload "../lib/local_provider.vim"
import autoload "../lib/diary.vim"


def ResetConfig()
  g:calendar_config = {
    position: 'left',
    cal_type: 'eu',
    show_week_number: false,
    number_of_months: 3,
    holidays: {},
    search_grep: 'internal',
    auto_create_diary_dirs: false,
    diaries_dict: {My_Diary: {
      path: '~/my_diary',
      resolution: 'day',
      events_file: tempname() .. '.json',
    }},
    active_diary: 'My_Diary',
  }
enddef

def CursorOnMonthDay(month_header: string, day: number)
  var header_line = search($'^\s*{month_header}\s*$', 'w')
  assert_true(header_line > 0, $'Missing month header: {month_header}')
  for lnum in range(header_line + 2, min([header_line + 8, line('$')]))
    var day_col = match(getline(lnum), '\<' .. string(day) .. '\>')
    if day_col >= 0
      cursor(lnum, day_col + 1)
      return
    endif
  endfor
  assert_true(false, $'Missing day {day} in {month_header}')
enddef

def FocusCalendar()
  var windows = win_findbuf(bufnr('__Calendar__'))
  if !empty(windows)
    win_gotoid(windows[0])
  endif
enddef

def g:Test_calendar_basic()
  ResetConfig()
  CalendarToggle 1998, 10
  WaitForAssert(() => assert_equal(3, winnr('$')))
  FocusCalendar()
  assert_equal('row', winlayout()[0])
  assert_equal('Hit "?" for help', getline(1))
  assert_match('October 1998', join(getline(1, '$'), "\n"))
  execute "normal q"
  assert_equal(1, winnr('$'))
enddef

def g:Test_calendar_reuses_stale_hidden_buffer()
  ResetConfig()
  if exists('+winfixbuf')
    setlocal nowinfixbuf
  endif
  enew
  file __Calendar__
  setlocal bufhidden=hide
  enew

  CalendarToggle 2026, 8
  WaitForAssert(() => assert_equal(3, winnr('$')))
  assert_equal(1, len(win_findbuf(bufnr('__Calendar__'))))
  assert_equal('__WeekView__', bufname('%'))

  CalendarWipe
enddef

def g:Test_calendar_arguments()
  ResetConfig()
  var current_month_name = strftime('%B')

  CalendarToggle 2031
  WaitForAssert(() => assert_equal(3, winnr('$')))
  FocusCalendar()
  assert_match($'{current_month_name}\s\+2031', join(getline(1, '$'), "\n"))
  execute "normal q"

  CalendarToggle 2032, 5
  WaitForAssert(() => assert_equal(3, winnr('$')))
  FocusCalendar()
  assert_match('May\s\+2032', join(getline(1, '$'), "\n"))
  execute "normal q"
  assert_equal(1, winnr('$'))
enddef

def g:Test_calendar_position_right()
  ResetConfig()
  g:calendar_config.position = 'right'
  CalendarToggle 2020, 2
  WaitForAssert(() => assert_equal(3, winnr('$')))
  FocusCalendar()
  assert_equal('row', winlayout()[0])
  assert_match('February 2020', join(getline(1, '$'), "\n"))
  :%bw!
  assert_equal(1, winnr('$'))
enddef

def g:Test_invalid_position_falls_back_to_left()
  ResetConfig()
  g:calendar_config.position = 'invalid'
  CalendarToggle 2020, 2
  WaitForAssert(() => assert_equal(3, winnr('$')))
  FocusCalendar()
  assert_equal('row', winlayout()[0])
  execute "normal q"
enddef

def g:Test_calendar_help_popup()
  ResetConfig()
  CalendarToggle 2020, 2
  WaitForAssert(() => assert_equal(3, winnr('$')))
  FocusCalendar()

  feedkeys('?', 'xt')
  WaitForAssert(() => assert_equal(1, len(popup_list())))
  popup_close(popup_list()[0])

  execute 'normal q'
enddef

def g:Test_show_week_numbers_column()
  ResetConfig()
  g:calendar_config.show_week_number = true
  CalendarToggle 2026, 7
  WaitForAssert(() => assert_equal(3, winnr('$')))
  FocusCalendar()
  assert_match('^WK  ', getline(4))
  assert_match('^\s*\d\{2}\s', getline(5))
  :%bw!
  assert_equal(1, winnr('$'))
enddef

def g:Test_autocmd_before_show()
  ResetConfig()
  g:test_before_show = 0
  augroup CalendarTestAu
    autocmd!
    autocmd User CalendarBeforeShow g:test_before_show += 1
  augroup END

  CalendarToggle 2024, 1
  WaitForAssert(() => assert_equal(3, winnr('$')))
  FocusCalendar()
  assert_equal(1, g:test_before_show)
  execute "normal q"
  augroup CalendarTestAu
    autocmd!
  augroup END
  unlet g:test_before_show
enddef

def g:Test_diary_cycle_split_tab_keys()
  ResetConfig()
  g:calendar_config.diaries_dict = {
    Alpha: {path: '~/my_diary', resolution: 'month'},
    Beta: {path: '~/my_diary', resolution: 'day'},
  }
  g:calendar_config.active_diary = 'Alpha'

  CalendarToggle 2026, 7
  WaitForAssert(() => assert_equal(3, winnr('$')))
  FocusCalendar()

  feedkeys("\<Tab>", 'xt')
  WaitForAssert(() => assert_equal('Beta', g:calendar_config.active_diary))

  feedkeys("\<S-Tab>", 'xt')
  WaitForAssert(() => assert_equal('Alpha', g:calendar_config.active_diary))

  execute "normal q"
enddef

def g:Test_open_diary_auto_create_dirs_month_resolution()
  ResetConfig()
  var tmp_root = tempname() .. '_calendar_diary'
  delete(tmp_root, 'rf')

  g:calendar_config.diaries_dict = {
    My_Diary: {path: tmp_root, resolution: 'month'},
  }
  g:calendar_config.active_diary = 'My_Diary'
  g:calendar_config.auto_create_diary_dirs = true

  CalendarToggle 2026, 7
  WaitForAssert(() => assert_equal(3, winnr('$')))
  FocusCalendar()
  CursorOnMonthDay('July 2026', 1)
  execute "normal \<C-CR>"

  assert_true(isdirectory(tmp_root))
  assert_true(isdirectory(tmp_root .. '/2026'))
  # month resolution: no per-month subdir; diary file is YYYY/MonthName.md

  :%bw!
  delete(tmp_root, 'rf')
enddef

def g:Test_open_diary_auto_create_dirs_day_resolution()
  ResetConfig()
  var tmp_root = tempname() .. '_calendar_diary_day'
  delete(tmp_root, 'rf')

  g:calendar_config.diaries_dict = {
    My_Diary: {path: tmp_root, resolution: 'day'},
  }
  g:calendar_config.active_diary = 'My_Diary'
  g:calendar_config.auto_create_diary_dirs = true

  CalendarToggle 2026, 7
  WaitForAssert(() => assert_equal(3, winnr('$')))
  FocusCalendar()

  var path = calendar_view.DiaryFilePath(2026, 7, 15)
  assert_match('2026[/\\]July[/\\]15\.md$', path,
    'day resolution DiaryFilePath must return YYYY/MonthName/DD.md')

  :%bw!
  delete(tmp_root, 'rf')
enddef

def g:Test_open_diary_path_with_special_characters()
  ResetConfig()
  var tmp_root = tempname() .. '_calendar diary #1'
  var address_book = tempname() .. '.json'
  delete(tmp_root, 'rf')
  writefile(['[]'], address_book)

  g:calendar_config.diaries_dict = {
    My_Diary: {
      path: tmp_root,
      resolution: 'month',
      address_book: address_book,
    },
  }
  g:calendar_config.active_diary = 'My_Diary'
  g:calendar_config.auto_create_diary_dirs = true

  CalendarToggle 2026, 7
  WaitForAssert(() => assert_equal(3, winnr('$')))
  FocusCalendar()
  CursorOnMonthDay('July 2026', 1)
  execute "normal \<C-CR>"

  var opened = expand('%:p')
  assert_equal([
    fnamemodify(tmp_root, ':t'),
    '2026',
    'July.md',
  ], [
    fnamemodify(opened, ':h:h:t'),
    fnamemodify(opened, ':h:t'),
    fnamemodify(opened, ':t'),
  ], 'Diary paths must survive spaces and Ex-special characters')
  assert_notequal('CalendarAddressBookComplete', &l:omnifunc,
    'Opening a diary page must not install the event-form omnifunc')

  bwipeout!
  delete(tmp_root, 'rf')
  delete(address_book)
enddef

def g:Test_calendar_search_path_with_special_characters()
  ResetConfig()
  var tmp_root = tempname() .. '_calendar search #1'
  var year_dir = tmp_root .. '/2026'
  mkdir(year_dir, 'p')
  writefile(['project needle', 'literal | marker'], year_dir .. '/July notes.md')

  g:calendar_config.diaries_dict = {
    My_Diary: {path: tmp_root, resolution: 'month'},
  }
  g:calendar_config.active_diary = 'My_Diary'

  execute 'CalendarSearch project\ needle 2026'
  var results = getqflist()
  assert_equal(1, len(results))
  assert_equal('project needle', results[0].text)

  frontend.Search('literal | marker', '2026')
  results = getqflist()
  assert_equal(1, len(results))
  assert_equal('literal | marker', results[0].text)

  cclose
  delete(tmp_root, 'rf')
enddef

def g:Test_local_json_provider_fetches_disposable_snapshot()
  var persistent = tempname() .. '.json'
  local_provider.Configure('Local', persistent)
  writefile([json_encode([{
    id: 'LOCAL-1',
    start: '2026-08-03T09:00:00',
    end: '2026-08-03T10:00:00',
    subject: 'Local test',
  }])], persistent)

  var snapshot = local_provider.FetchEvents({
    start: '2026-08-03',
    end: '2026-08-08',
  })
  assert_notequal(persistent, snapshot,
    'The provider must not expose its persistent file for deletion')
  var events = json_decode(readfile(snapshot)->join("\n"))
  assert_equal('Local test', events[0].subject)
  assert_true(filereadable(persistent))

  delete(snapshot)
  delete(persistent)
enddef

def g:Test_hookless_diary_uses_local_provider()
  ResetConfig()
  var persistent = tempname() .. '.json'
  g:calendar_config.diaries_dict.My_Diary.events_file = persistent

  CalendarToggle 2026, 8
  WaitForAssert(() => assert_equal(3, winnr('$')))
  assert_equal('g:CalendarLocalFetchEvents', t:cal_fetch_events_func)
  assert_equal(fnamemodify(persistent, ':p'),
    fnamemodify(local_provider.EventsPath(), ':p'))

  CalendarWipe
  delete(persistent)
enddef

def g:Test_local_provider_default_path_uses_data_directory()
  local_provider.Configure('Work Notes')
  assert_match('[/\\]vim-calendar[/\\]Work_Notes-events\.json$',
    local_provider.EventsPath())
enddef

def g:Test_local_provider_creates_and_edits_events()
  var persistent = tempname() .. '.json'
  local_provider.Configure('Local', persistent)
  g:test_event_created = 0
  g:test_event_modified = 0
  augroup CalendarEventTestAu
    autocmd!
    autocmd User CalendarEventCreated g:test_event_created += 1
    autocmd User CalendarEventModified g:test_event_modified += 1
  augroup END

  assert_true(local_provider.ManageEvents({
    action: 'create',
    start: '2026-08-03 09:00',
    end: '2026-08-03 10:00',
  }))
  assert_equal(local_provider.FORM_BUF_NAME, bufname('%'))
  assert_equal('CalendarAddressBookComplete', &l:omnifunc)
  execute 'normal ?'
  assert_equal(1, len(popup_list()))
  assert_match('AllDay',
    join(getbufline(winbufnr(popup_list()[0]), 1, '$'), "\n"))
  popup_close(popup_list()[0])
  setline(1, [
    'Title: Created event',
    'Start: 2026-08-03 09:00',
    'End: 2026-08-03 10:00',
    'Required Attendees: Alice <alice@example.com>',
    'Optional Attendees: Carol <carol@example.com>',
    'Organizer: Alice',
    'Location: Room A',
    'AllDay: false',
    'Body: First line',
    'Second line',
  ])
  execute 'normal W'
  assert_equal(-1, bufwinnr(local_provider.FORM_BUF_NAME))

  var events = json_decode(readfile(persistent)->join("\n"))
  assert_equal(1, len(events))
  assert_equal('Created event', events[0].subject)
  assert_equal('Alice <alice@example.com>', events[0].required_attendees)
  assert_equal('Carol <carol@example.com>', events[0].optional_attendees)
  assert_equal('Alice', events[0].organizer)
  assert_equal('Room A', events[0].location)
  assert_false(events[0].allday)
  assert_equal("First line\nSecond line", events[0].body)
  assert_equal(1, g:test_event_created)
  assert_equal(0, g:test_event_modified)
  assert_equal('Created event', g:calendar_event.subject)

  assert_true(local_provider.ManageEvents({
    action: 'edit',
    id: events[0].id,
  }))
  assert_equal(local_provider.FORM_BUF_NAME, bufname('%'))
  assert_equal('Title: Created event', getline(1))
  setline(1, [
    'Title: Updated event',
    'Start: 2026-08-03 10:00',
    'End: 2026-08-03 11:00',
    'Required Attendees: Bob <bob@example.com>',
    'Optional Attendees: ',
    'Organizer: Bob',
    'Location: Room B',
    'AllDay: true',
    'Body: Updated body',
  ])
  deletebufline('%', 10, '$')
  write

  events = json_decode(readfile(persistent)->join("\n"))
  assert_equal(1, len(events))
  assert_equal('Updated event', events[0].subject)
  assert_equal('Bob <bob@example.com>', events[0].required_attendees)
  assert_equal('', events[0].optional_attendees)
  assert_equal('2026-08-03T00:00', events[0].start)
  assert_equal('2026-08-04T00:00', events[0].end)
  assert_equal('Bob', events[0].organizer)
  assert_equal('Room B', events[0].location)
  assert_true(events[0].allday)
  assert_equal('Updated body', events[0].body)
  assert_equal(1, g:test_event_created)
  assert_equal(1, g:test_event_modified)
  assert_equal('Updated event', g:calendar_event.subject)

  augroup CalendarEventTestAu
    autocmd!
  augroup END
  unlet g:test_event_created
  unlet g:test_event_modified
  delete(persistent)
enddef

def g:Test_event_form_address_book_completion()
  var address_book = tempname() .. '.json'
  writefile([json_encode([
    {name: 'Alice Smith', email: 'alice@example.com'},
    {name: 'Bob Jones', email: 'bob@example.com'},
  ])], address_book)
  diary.Configure('~/my_diary', 'day', address_book, false)
  local_provider.Configure('Local', tempname() .. '.json', address_book)

  assert_true(local_provider.ManageEvents({
    action: 'create',
    start: '2026-08-03 09:00',
    end: '2026-08-03 10:00',
  }))
  setline(4, 'Required Attendees: Alice')
  cursor(4, strlen(getline(4)) + 1)
  assert_true(g:CalendarAddressBookComplete(1, '') >= 0)
  var matches = g:CalendarAddressBookComplete(0, 'Alice')
  assert_equal(['Alice Smith <alice@example.com>'],
    matches->mapnew((_, match) => match.word))

  var other_address_book = tempname() .. '.json'
  writefile([json_encode([
    {name: 'Carol White', email: 'carol@example.com'},
  ])], other_address_book)
  diary.Configure('~/other_diary', 'day', other_address_book, false)
  matches = g:CalendarAddressBookComplete(0, 'Alice')
  assert_equal(['Alice Smith <alice@example.com>'],
    matches->mapnew((_, match) => match.word),
    'An open form must retain its originating address book')

  setline(1, 'Title: Alice')
  cursor(1, strlen(getline(1)) + 1)
  assert_equal(-2, g:CalendarAddressBookComplete(1, ''))

  execute 'normal Q'
  delete(address_book)
  delete(other_address_book)
enddef

def g:CalendarTestSwitchBuffer()
  enew
  file __CalendarCallbackBuffer__
  setline(1, 'Unsaved callback work')
enddef

def g:Test_event_form_callback_cannot_wipe_other_buffer()
  var persistent = tempname() .. '.json'
  local_provider.Configure('Local', persistent)
  augroup CalendarEventBufferTestAu
    autocmd!
    autocmd User CalendarEventCreated g:CalendarTestSwitchBuffer()
  augroup END

  assert_true(local_provider.ManageEvents({
    action: 'create',
    start: '2026-08-03 09:00',
    end: '2026-08-03 10:00',
  }))
  setline(1, 'Title: Callback event')
  execute 'normal W'

  assert_equal('__CalendarCallbackBuffer__', bufname('%'))
  assert_equal('Unsaved callback work', getline(1))
  assert_true(&modified)
  assert_equal(-1, bufnr(local_provider.FORM_BUF_NAME))

  augroup CalendarEventBufferTestAu
    autocmd!
  augroup END
  bwipeout!
  delete(persistent)
enddef

def g:Test_local_provider_form_keeps_originating_events_file()
  var first = tempname() .. '.json'
  var second = tempname() .. '.json'
  local_provider.Configure('First', first)

  assert_true(local_provider.ManageEvents({
    action: 'create',
    start: '2026-08-03 09:00',
    end: '2026-08-03 10:00',
  }))
  local_provider.Configure('Second', second)
  setline(1, [
    'Title: First diary event',
    'Start: 2026-08-03 09:00',
    'End: 2026-08-03 10:00',
    'Required Attendees: ',
    'Optional Attendees: ',
    'Organizer: ',
    'Location: Room A',
    'AllDay: false',
    'Body: ',
  ])
  write

  assert_true(filereadable(first))
  assert_false(filereadable(second))
  var events = json_decode(readfile(first)->join("\n"))
  assert_equal('First diary event', events[0].subject)

  delete(first)
  delete(second)
enddef

def g:Test_local_provider_form_normalizes_timestamp_seconds()
  var persistent = tempname() .. '.json'
  writefile([json_encode([{
    id: 'with-seconds',
    start: '2026-08-03T09:00:00',
    end: '2026-08-03T10:00:00',
    subject: 'Existing event',
    location: '',
  }])], persistent)
  local_provider.Configure('Local', persistent)

  assert_true(local_provider.ManageEvents({
    action: 'edit',
    id: 'with-seconds',
  }))
  assert_equal('Start: 2026-08-03 09:00', getline(2))
  assert_equal('End: 2026-08-03 10:00', getline(3))
  write

  var events = json_decode(readfile(persistent)->join("\n"))
  assert_equal('Existing event', events[0].subject)
  delete(persistent)
enddef

def g:Test_local_provider_preserves_modified_form()
  var persistent = tempname() .. '.json'
  local_provider.Configure('Local', persistent)

  assert_true(local_provider.ManageEvents({
    action: 'create',
    start: '2026-08-03 09:00',
    end: '2026-08-03 10:00',
  }))
  setline(1, 'Title: Unsaved event')
  assert_true(&modified)

  assert_false(local_provider.ManageEvents({
    action: 'create',
    start: '2026-08-04 09:00',
    end: '2026-08-04 10:00',
  }))
  assert_equal(local_provider.FORM_BUF_NAME, bufname('%'))
  assert_equal('Title: Unsaved event', getline(1))

  execute 'normal Q'
  assert_equal(-1, bufwinnr(local_provider.FORM_BUF_NAME))
  assert_false(filereadable(persistent))
  delete(persistent)
enddef

def g:Test_local_provider_deletes_event()
  var persistent = tempname() .. '.json'
  writefile([json_encode([
    {
      id: 'keep',
      start: '2026-08-03T09:00',
      end: '2026-08-03T10:00',
      subject: 'Keep',
    },
    {
      id: 'delete',
      start: '2026-08-04T09:00',
      end: '2026-08-04T10:00',
      subject: 'Delete',
    },
  ])], persistent)
  local_provider.Configure('Local', persistent)

  assert_true(local_provider.ManageEvents({
    action: 'delete',
    id: 'delete',
  }))
  var events = json_decode(readfile(persistent)->join("\n"))
  assert_equal(['keep'], events->mapnew((_, event) => event.id))

  delete(persistent)
enddef

def g:Test_local_provider_does_not_overwrite_invalid_json()
  var persistent = tempname() .. '.json'
  writefile(['{"not": "a list"}'], persistent)
  local_provider.Configure('Local', persistent)

  assert_true(local_provider.ManageEvents({
    action: 'create',
    start: '2026-08-03 09:00',
    end: '2026-08-03 10:00',
  }))
  setline(1, 'Title: Must not be written')
  execute 'normal W'

  assert_equal(local_provider.FORM_BUF_NAME, bufname('%'))
  assert_equal(['{"not": "a list"}'], readfile(persistent))

  execute 'normal Q'
  delete(persistent)
enddef
