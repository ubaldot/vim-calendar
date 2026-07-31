vim9script

import autoload "./backend.vim"

# Parsed appointment storage keyed by displayed week start date.

var cache: dict<dict<list<any>>> = {}

export def Clear()
  cache = {}
enddef

export def Has(week_key: string): bool
  return has_key(cache, week_key)
enddef

export def Get(week_key: string): dict<list<any>>
  return get(cache, week_key, {})
enddef

export def Put(week_key: string, events: dict<list<any>>)
  cache[week_key] = events
enddef

export def Remove(week_key: string)
  if has_key(cache, week_key)
    remove(cache, week_key)
  endif
enddef

export def EventsOn(date_key: string): list<any>
  for events in values(cache)
    if has_key(events, date_key)
      return events[date_key]
    endif
  endfor
  return []
enddef

def StripCR(value: string): string
  return substitute(value, "\r", '', 'g')
enddef

# Consume an appointments JSON file and return normalized render data.
export def LoadFile(path: string): dict<any>
  if !filereadable(path)
    return {ok: false, events: {}}
  endif

  var items: list<any> = []
  try
    items = json_decode(readfile(path)->join("\n"))
  catch
    echomsg '[Calendar] Could not parse appointments file.'
    return {ok: false, events: {}}
  endtry
  delete(path)

  var events: dict<list<any>> = {}
  var allday: list<any> = []
  for item in items
    if type(item) != v:t_dict
      continue
    endif
    if get(item, 'allday', false)
      var end_str = strpart(get(item, 'end', ''), 0, 10)
      if end_str !~# '^\d\{4}-\d\{2}-\d\{2}$'
        continue
      endif
      var last = backend.JDNToDate(backend.DateToJDN(
        str2nr(end_str[0 : 3]), str2nr(end_str[5 : 6]),
        str2nr(end_str[8 : 9])) - 1)
      allday->add({
        start_date: strpart(get(item, 'start', ''), 0, 10),
        end_date: printf('%04d-%02d-%02d', last.year, last.month, last.day),
        subject: StripCR(get(item, 'subject', '')),
        organizer: StripCR(get(item, 'organizer', '')),
      })
      continue
    endif

    var date_key = strpart(get(item, 'start', ''), 0, 10)
    if date_key !~# '^\d\{4}-\d\{2}-\d\{2}$'
      continue
    endif
    if !has_key(events, date_key)
      events[date_key] = []
    endif
    events[date_key]->add({
      start: strpart(get(item, 'start', ''), 11, 5),
      end: strpart(get(item, 'end', ''), 11, 5),
      subject: StripCR(get(item, 'subject', '')),
      organizer: StripCR(get(item, 'organizer', '')),
      location: StripCR(get(item, 'location', '')),
      body: StripCR(get(item, 'body', '')),
      entryid: get(item, 'entryid', ''),
    })
  endfor
  events.allday = allday
  return {ok: true, events: events}
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
