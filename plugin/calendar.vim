vim9script

# Vim 9.0 ported and refactored version of vim-calendar originally written by
# Yasuhiro Matsumoto <mattn.jp@gmail.com>
# Author: Ubaldo Tiberi
# License: BSD-3

if !has('vim9script') ||  v:version < 900
  # Needs Vim version 9.0 and above
  finish
endif

g:loaded_calendar = true

import autoload "../lib/frontend.vim"
import autoload "../lib/local_provider.vim"
import autoload "../lib/week_view.vim"

def Diaries(A: string, L: string, P: number): list<string>
  return g:calendar_config.diaries_dict->keys()
enddef

command! -nargs=* CalendarToggle   frontend.CalendarToggle(<args>)
command! -nargs=0 CalendarRefresh  week_view.CalendarRefresh()
command! -nargs=* CalendarSearch   frontend.Search(<f-args>)
command! -nargs=0 CalendarWipe     frontend.CalendarWipe()
command! -nargs=1 -complete=customlist,Diaries CalendarActivate frontend.InitVariables() | frontend.ActivateDiary(<f-args>)
command! -nargs=0 CalendarActive     echo g:calendar_config.active_diary

# Global wrapper required because &omnifunc must be a string name resolvable
# in legacy Vimscript context.
def g:CalendarAddressBookComplete(findstart: number, base: string): any
  return frontend.AddressBookComplete(findstart, base)
enddef

def g:CalendarLocalFetchEvents(request: dict<any>): string
  return local_provider.FetchEvents(request)
enddef

def g:CalendarLocalManageEvents(request: dict<any>): bool
  return local_provider.ManageEvents(request)
enddef

# Diaries with secret
def SetDiaryKey()
  if !exists('g:calendar_config')
    return
  elseif !has_key(g:calendar_config, 'active_diary')
    return
  endif

  const active_diary = g:calendar_config.active_diary
  if !has_key(g:calendar_config.diaries_dict[active_diary], 'path')
    return
  endif

  const active_diary_path_normalized =  g:calendar_config.diaries_dict[active_diary].path
    ->fnamemodify(':p')
    ->substitute('\\', '/', 'g')
  const current_filepath_normalized = expand('%:p')->substitute('\\', '/', 'g')

  # echom "A: " .. active_diary_path_normalized
  # echom "B: " .. current_filepath_normalized

  # Check if the file being opened belong to a diary
  if current_filepath_normalized =~# active_diary_path_normalized
    if empty(&key) && has_key(g:calendar_config.diaries_dict[active_diary], 'secret')
      &key = inputsecret($"Insert key for diary '{active_diary}': ")
    endif
  else
    &key = ''
  endif
enddef

augroup DIARY_KEY_SET
  autocmd!
  autocmd BufReadPre * SetDiaryKey()
augroup END
