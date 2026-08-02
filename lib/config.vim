vim9script

# Normalize g:calendar_config into the runtime shape consumed by frontend.

const DEFAULT_DIARIES: dict<any> = {
  My_Diary: {path: '~/my_diary', resolution: 'month'},
}

def Choice(value: any, allowed: list<string>, fallback: string): string
  var normalized = type(value) == v:t_string ? tolower(value) : fallback
  return index(allowed, normalized) >= 0 ? normalized : fallback
enddef

export def Load(): dict<any>
  if !exists('g:calendar_config')
    g:calendar_config = {}
  elseif type(g:calendar_config) != v:t_dict
    echoerr "'g:calendar_config' must be a dict"
    return {ok: false}
  endif

  var raw = g:calendar_config
  var diaries_value = get(raw, 'diaries_dict', {})
  var diaries = type(diaries_value) == v:t_dict && !empty(diaries_value)
    ? diaries_value
    : deepcopy(DEFAULT_DIARIES)
  var active_diary = get(raw, 'active_diary', '')
  if type(active_diary) != v:t_string
      || empty(active_diary)
      || !has_key(diaries, active_diary)
    active_diary = keys(diaries)[0]
    g:calendar_config.active_diary = active_diary
  endif

  var active = diaries[active_diary]
  var search_engine = Choice(get(raw, 'search_grep', 'internal'),
    ['internal', 'external'], 'internal')
  if !empty(get(raw, 'fetch_events', {}))
    echomsg "[Calendar] 'fetch_events' at top level is ignored; set it per-diary in diaries_dict."
  endif

  return {
    ok: true,
    position: Choice(get(raw, 'position', 'left'),
      ['left', 'right'], 'left'),
    cal_type: Choice(get(raw, 'cal_type', 'eu'),
      ['eu', 'us', 'work'], 'eu'),
    show_week_number: !!get(raw, 'show_week_number', false),
    number_of_months: max([1, get(raw, 'number_of_months', 3)]),
    holidays: type(get(raw, 'holidays', {})) == v:t_dict
      ? get(raw, 'holidays', {})
      : {},
    search_grep: search_engine,
    auto_create_diary_dirs: !!get(raw, 'auto_create_diary_dirs', false),
    diaries: diaries,
    active_diary: active_diary,
    diary_path: get(active, 'path', '~/my_diary'),
    diary_resolution: get(active, 'resolution', 'month'),
    address_book_path: get(active, 'address_book', ''),
    events_file: get(active, 'events_file', ''),
    fetch_events: get(active, 'fetch_events', ''),
    manage_events: get(active, 'manage_events', ''),
    week_display_type: Choice(get(raw, 'week_display_type', 'eu'),
      ['eu', 'us', 'work'], 'eu'),
    week_cell_width: max([8, get(raw, 'week_cell_width', 16)]),
    reminder_sound: !!get(raw, 'reminder_sound', true),
  }
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
