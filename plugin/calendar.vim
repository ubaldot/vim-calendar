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

import autoload "../autoload/frontend.vim"

command! -nargs=* Calendar  frontend.Show(<args>)
command! -nargs=* CalendarSearch frontend.Search("<args>")
