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
import autoload "../lib/week_view.vim"

command! -nargs=* CalendarToggle   frontend.CalendarToggle(<args>)
command! -nargs=0 CalendarRefresh  week_view.CalendarRefresh()
command! -nargs=* CalendarSearch   frontend.Search(<f-args>)
command! -nargs=0 CalendarWipe     frontend.CalendarWipe()
command! -nargs=1 CalendarWeekNav  frontend.WeekViewNavigate(<q-args>)

# Global wrapper required because &omnifunc must be a string name resolvable
# in legacy Vimscript context.
def g:CalendarAddressBookComplete(findstart: number, base: string): any
  return frontend.AddressBookComplete(findstart, base)
enddef
