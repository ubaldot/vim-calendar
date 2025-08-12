# vim-calendar

Port of @mattn [calendar-vim][1] to Vim9!

`calendar.vim` creates a calendar window you can use within vim. It is useful
in its own right as a calendar-inside-vim. It also provides hooks to customise
its behaviour, making it a good basis for writing new plugins which require
calendar functionality (see `:help calendar-hooks` for more information).

## Installation

The easiest if to use any plugin manager (vim-plug, minpac, etc.)

## Usage

Bring up a calendar based on today's date in a vertically split window:

    :Calendar

Bring up a calendar showing November, 1991 (The month Vim was first released):

    :Calendar 1991 11

The above calendars can alternatively be displayed in a horizontally split
window:

    :CalendarH

Bring up a full-screen:

    :CalendarT

Fast mappings are provided:

- <kbd>&lt;LocalLeader&gt;cal</kbd>: Vertically-split calendar
- <kbd>&lt;LocalLeader&gt;caL</kbd>: Horizontally-split calendar

For full documentation, install the plugin and run `:help calendar` from
within Vim.

<!-- DO NOT REMOVE vim-markdown-extras references DO NOT REMOVE-->

[1]: https://github.com/mattn/calendar-vim
