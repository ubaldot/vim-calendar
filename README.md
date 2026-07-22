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

    :Calendar 1991, 11

Fast mappings are provided:

- <kbd>&lt;LocalLeader&gt;cal</kbd>: Vertically-split calendar

## Configuration (`g:calendar_config`)

All runtime options are configured through one dictionary:

```vim
g:calendar_config = {
  position: 'left',
  cal_type: 'eu',
  show_week_number: false,
  number_of_months: 3,
  holidays: {},
  search_grep: 'internal',
  action: 'Diary',
  diaries_dict: {Diary: {path: '~/diary', resolution: 'day'}},
  active_diary: 'Diary',
}
```

Supported top-level keys:

- `position`: `left`, `right`, `popup`
- `cal_type`: `eu`, `us`, `work`
- `show_week_number`: `true` or `false`
- `number_of_months`: integer `>= 1`
- `holidays`: dict keyed by `YYYY-MM-DD` (rendered with `!`)
- `search_grep`: `internal` (`:vimgrep`) or `external` (`:grep`)
- `action`: function name to call on `<CR>` (defaults to `Diary`)
- `diaries_dict`: dict of diaries (`{name: {path, resolution}}`)
- `active_diary`: key from `diaries_dict`

Built-in key bindings are fixed:

- `<CR>` open action, `q`/`<Esc>` close
- `<Up>/<Down>` previous/next month
- `<Left>/<Right>` previous/next year
- `h/j/k/l` move cursor, `t` today, `?` help

For full documentation, install the plugin and run `:help calendar` from
within Vim.

<!-- DO NOT REMOVE vim-markdown-extras references DO NOT REMOVE-->

[1]: https://github.com/mattn/calendar-vim
