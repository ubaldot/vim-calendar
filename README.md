# vim-calendar

A Vim9 rewrite of [mattn/calendar-vim][1], focused on a cleaner frontend and diary workflow.

> Screencast: _coming soon_

## What it does

- Split or popup calendar (`left`, `right`, `popup`)
- Multi-month rendering in split mode
- Diary pages opened from calendar days (`<CR>`)
- Two diary resolutions:
  - **month**: `~/my_diary/2026/January.md`
  - **day**: `~/my_diary/2026/January/01.md`
- Configurable holidays (custom highlight group)
- Runtime behavior centralized in `g:calendar_config`

## Installation

Install with your preferred plugin manager (minpac, vim-plug, packer-style packages, etc.).

## Commands

- `:Calendar` — open calendar for current month
- `:Calendar {year}, {month}` — open a specific month
- `:CalendarSearch {keyword}` — search in diary markdown files

## Minimal configuration

```vim
g:calendar_config = {
  position: 'left',
  cal_type: 'eu',
  show_week_number: false,
  number_of_months: 3,
  holidays: {},
  search_grep: 'internal',
  action: 'OpenDiaryPage',
  diaries_dict: {
    My_Diary: {path: '~/my_diary', resolution: 'month'},
  },
  active_diary: 'My_Diary',
}
```

## Configuration keys

| Key | Values | Default |
|---|---|---|
| `position` | `left`, `right`, `popup` | `left` |
| `cal_type` | `eu`, `us`, `work` | `eu` |
| `show_week_number` | `true` / `false` | `false` |
| `number_of_months` | integer `>= 1` | `3` |
| `holidays` | dict keyed by `YYYY-MM-DD` | `{}` |
| `search_grep` | `internal`, `external` | `internal` |
| `action` | function name | `OpenDiaryPage` |
| `diaries_dict` | `{name: {path, resolution}}` | `{My_Diary: {path: '~/my_diary', resolution: 'month'}}` |
| `active_diary` | key from `diaries_dict` | first diary key |

## Important notes

- Directory creation is **manual**: this plugin does not create diary directories for you.
- If an expected diary directory does not exist, you get a warning prompt.
- `resolution` accepts `month` or `day`.

## Keybindings

### Split mode (`position = left/right`)

- `<CR>` open selected day/month page
- `<Up>/<Down>` previous/next month
- `<Left>/<Right>` previous/next year
- `t` go to today
- `<Tab>/<S-Tab>` next/previous diary
- `h/j/k/l` move cursor
- `?` help
- `q` or `<Esc>` close calendar

### Popup mode (`position = popup`)

- `h/j/k/l` move popup day selection
- `<CR>` open page for selected day
- `<Up>/<Down>` previous/next month
- `<Left>/<Right>` previous/next year
- `t` go to today
- `<Tab>/<S-Tab>` next/previous diary
- `?` help
- `q` or `<Esc>` close popup

## Highlight groups

- `CalSaturday`
- `CalSunday`
- `CalHoliday`
- `CalToday`
- `CalWeekdays`
- `CalWeeknm`
- `CalHeader`
- `CalHelpHint`
- `CalCurrList`
- `CalPopupSelection`

For full help inside Vim: `:help calendar`

[1]: https://github.com/mattn/calendar-vim
