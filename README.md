# vim-calendar

A Vim 9.0 ported and refactored version of [mattn/calendar-vim][1].

> Screencast: _coming soon_

## What it does

- Split-window calendar display
- ISO (EU), US, and work-week (Mon–Fri) layouts
- Week view panel with calendar events integration
- Multiple configurable diary books
- Address-book omni-completion in diary files
- Configurable holidays

## Installation

Install with your preferred plugin manager (minpac, vim-plug, lazy.nvim, etc.).

Requires **Vim 9.0** or later.

## Commands

| Command | Description |
|---|---|
| `:CalendarToggle [year [month]]` | Toggle calendar tab (open / focus / close) |
| `:CalendarRefresh` | Re-fetch appointments for the visible week |
| `:CalendarSearch {keyword} [{year}]` | Search diary markdown files |
| `:CalendarWipe` | Close tab and wipe all calendar buffers |


Press `?` inside the calendar for a full key-binding reference.

## Minimal configuration

```vim
g:calendar_config = {
  position:         'left',
  cal_type:         'eu',
  show_week_number: false,
  number_of_months: 3,
  holidays: {'2026-12-25': 'Christmas'},
  auto_create_diary_dirs: false,
  diaries_dict: {
    My_Diary: {path: '~/my_diary', resolution: 'month'},
    Notes:    {path: '~/notes',    resolution: 'day'},
  },
  active_diary: 'My_Diary',
}
```

## Calendar provider integration

Events in the calendar can be created, edited, stored and fetched from a
locally stored JSON file or from an external source such as Outlook.
See `:help calendar` for more info.

### Built-in local event form

When a diary defines neither `fetch_events` nor `manage_events`, vim-calendar
uses its built-in local JSON provider. In `__WeekView__`, press `m` on an
empty hour cell to create an event, or on an existing event to edit it.

`__CalendarEventForm__` supports these fields:

| Field | Format |
|---|---|
| `Title` | Required |
| `Start`, `End` | Required; `YYYY-MM-DD HH:MM` |
| `Organizer`, `Location` | Optional |
| `AllDay` | `true` or `false`; times are ignored and the end date is exclusive |
| `Body` | Optional; may continue on following lines |

Press `W` to save/create/update, `Q` to discard, or `?` for field help.
`:w` also saves the form. Event IDs are generated and preserved internally.
In `__WeekView__`, `d` deletes a local event. Provider-backed calendars may
interpret `d` as the appropriate decline, cancellation, or deletion action.
Use `a` to accept an invitation and `v` to respond tentatively when supported
by the active provider. `t` remains “go to current week.”

## Security and privacy

Calendar and address-book data may be confidential. This plugin processes
that data locally, but it does not encrypt it or provide access control.
The built-in provider stores events persistently as plaintext JSON, and
providers may create additional plaintext snapshots or cache files.

Temporary files are deleted on the normal processing path where possible,
but deletion is best-effort, is not secure erasure, and may not occur after
a crash or forced termination. Files may also be retained by backups,
indexing tools, antivirus software, or filesystem recovery mechanisms.

Use storage locations and operating-system permissions appropriate for the
data, and assess the plugin against your organization's confidentiality and
retention requirements. The software is provided "as is" under the BSD
3-Clause License.

## License

BSD-3.

[1]: https://github.com/mattn/calendar-vim
