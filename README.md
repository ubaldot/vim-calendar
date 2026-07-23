# vim-calendar

A Vim 9.0 ported and refactored version of [mattn/calendar-vim][1].

> Screencast: _coming soon_

## What it does

- Split window or popup display
- ISO and US style calendars
- Diary pages opened from calendar days
- Two diary resolutions:
  - *month*: `~/my_diary/2026/January.md`
  - *day*: `~/my_diary/2026/January/01.md`
- Configurable holidays (custom highlight group)
- Runtime behavior centralized in `g:calendar_config`

## Installation

Install with your preferred plugin manager (minpac, vim-plug, etc.).

## Commands

- `:Calendar` — open calendar for current month
- `:Calendar {year}, {month}` — open a specific month
- `:CalendarSearch {keyword}` — search in diary markdown files

Hit `?` once the calendar is opened to see the key bindings.

## Minimal configuration

```
g:calendar_config = {
  position: 'left',
  cal_type: 'eu',
  show_week_number: false,
  holidays: {'2026-12-15': 'Christmas'},
  diaries_dict: {
    My_Diary: {path: '~/my_diary', resolution: 'month'},
    Notes: {path: '~/notes', resolution: 'day'},
  },
  active_diary: 'My_Diary',
}
```

For full help inside Vim: `:help calendar`

## License

BSD-3.

[1]: https://github.com/mattn/calendar-vim
