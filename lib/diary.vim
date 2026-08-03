vim9script

import autoload "./calendar_view.vim"

# Diary file preparation and event-attendee completion.

var cfg_path = '~/my_diary'
var cfg_resolution = 'month'
var cfg_address_book = ''
var cfg_auto_create_dirs = false

export def Configure(path: string, resolution: string,
                     address_book: string, auto_create_dirs: bool)
  cfg_path = path
  cfg_resolution = resolution
  cfg_address_book = address_book
  cfg_auto_create_dirs = auto_create_dirs
enddef

def EnsureDir(path: string): bool
  if isdirectory(path)
    return true
  endif
  if cfg_auto_create_dirs
    mkdir(path, 'p')
    if isdirectory(path)
      return true
    endif
    confirm($"failed to create diary directory: {path}", 'OK')
    return false
  endif
  confirm($"please create diary directory: {path}", 'OK')
  return false
enddef

# Ensure the directory hierarchy exists and return an escaped diary filename.
export def PrepareFile(year: number, month: number, day: number): string
  var root = expand(cfg_path)
  if !EnsureDir(root)
    return ''
  endif
  if !EnsureDir($"{root}/{printf('%04d', year)}")
    return ''
  endif
  if cfg_resolution ==# 'day'
    if !EnsureDir(calendar_view.DiaryMonthDir(year, month))
      return ''
    endif
  endif
  return fnameescape(calendar_view.DiaryFilePath(year, month, day))
enddef

def LoadAddressBook(address_book: string = ''): list<any>
  var path = expand(empty(address_book) ? cfg_address_book : address_book)
  if !filereadable(path)
    return []
  endif
  try
    var decoded = readfile(path)->join("\n")->json_decode()
    return type(decoded) == v:t_list ? decoded : []
  catch
    return []
  endtry
enddef

# Omnifunc for address-book entries shaped as {name, email}.
export def Complete(findstart: number, base: string,
                    address_book: string = ''): any
  if findstart
    var line = getline('.')
    if line !~# '^\%(Required\|Optional\) Attendees:'
      return -2
    endif
    var c = col('.') - 1
    while c > 0 && line[c - 1] !~ '[:,;]'
      c -= 1
    endwhile
    while c < col('.') - 1 && line[c] =~# '\s'
      c += 1
    endwhile
    return c
  endif

  var prefix = tolower(base)
  return LoadAddressBook(address_book)
    ->filter((_, entry) =>
        type(entry) == v:t_dict
        && (empty(prefix)
          || stridx(tolower(get(entry, 'name', '')), prefix) >= 0
          || stridx(tolower(get(entry, 'email', '')), prefix) >= 0))
    ->mapnew((_, entry) => ({
      word: $'{get(entry, "name", "")} <{get(entry, "email", "")}>',
      abbr: get(entry, 'name', ''),
      menu: get(entry, 'email', ''),
    }))
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
