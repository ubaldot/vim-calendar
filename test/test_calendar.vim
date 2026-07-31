vim9script

import "./common.vim"
var WaitForAssert = common.WaitForAssert

packadd CalendarToggle
import autoload "../lib/calendar_view.vim"
import autoload "../lib/frontend.vim"

def ResetConfig()
  g:calendar_config = {
    position: 'left',
    cal_type: 'eu',
    show_week_number: false,
    number_of_months: 3,
    holidays: {},
    search_grep: 'internal',
    auto_create_diary_dirs: false,
    diaries_dict: {My_Diary: {path: '~/my_diary', resolution: 'day'}},
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

  assert_equal(
    fnamemodify(tmp_root .. '/2026/July.md', ':p')->substitute('\\', '/', 'g'),
    expand('%:p')->substitute('\\', '/', 'g'),
    'Diary paths must survive spaces and Ex-special characters')

  bwipeout!
  delete(tmp_root, 'rf')
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
