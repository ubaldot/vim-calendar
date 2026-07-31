# vim-calendar

A Vim 9.0 ported and refactored version of [mattn/calendar-vim][1].

> Screencast: _coming soon_

## What it does

REMOVE ME

- Split-window calendar (EU, US, or work-week layout)
- ISO week-number column (optional)
- Multiple diary books — per-diary path, resolution, and Outlook connect hook
- Diary pages opened from calendar days (`<CR>` navigates, `<C-CR>` opens and closes)
- Week view panel with appointment grid (requires a `connect` hook)
- Native provider appointment composition and editing from the week grid
- Address-book omni-completion in diary files (`<C-X><C-O>`)
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

Recommended mapping in your `.vimrc`:

```vim
nnoremap W <Cmd>CalendarToggle<CR>
```

Press `?` inside the calendar for a full key-binding reference.

## Minimal configuration

```vim
g:calendar_config = {
  position:         'left',   # 'left' | 'right'
  cal_type:         'eu',     # 'eu' | 'us' | 'work'
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

## Week view with Outlook integration (Windows)

Add a `connect` function and optional `week_display_type` / `week_cell_width`
to your config:

```vim
# 1. The connect hook — called whenever a new week is needed.
#    Must write a JSON file and return its path ('': failure).
def g:OutlookCalendarFetch(year: number, month: number, day: number): string
  var out    = $'{$TEMP}\calendar_week.json'
  var script = expand('~/vimfiles/ps1_scripts/fetch_calendar.ps1')
  system($'powershell -NoProfile -File "{script}"'
      .. $' -Year {year} -Month {month} -Day {day} -OutputFile "{out}"')
  return filereadable(out) ? out : ''
enddef

# 2. Config — diary with connect hook
g:calendar_config = {
  cal_type:          'eu',
  week_display_type: 'work',   # 'eu' | 'us' | 'work'
  week_cell_width:   18,
  diaries_dict: {
    Outlook: {
      path:    '~/diary/outlook',
      resolution: 'day',
      connect: 'g:OutlookCalendarFetch',
      compose: 'g:OutlookCalendarCompose',
      edit:    'g:OutlookCalendarEdit',
      address_book: $'{$TEMP}\outlook_address_book.json',
    },
  },
  active_diary: 'Outlook',
}
```

### Appointments JSON format

The PowerShell script must write a UTF-8 **without BOM** JSON file
(`[IO.File]::WriteAllText`, not `Set-Content -Encoding UTF8`):

```json
[
  {
    "start":     "2026-07-27T09:00:00",
    "end":       "2026-07-27T10:00:00",
    "subject":   "Team Meeting",
    "organizer": "Alice Smith",
    "location":  "Room A",
    "body":      "Agenda:\n1. Sprint review\n2. Planning",
    "entryid":   "<opaque Outlook EntryID>"
  },
  {
    "start":   "2026-07-28T00:00:00",
    "end":     "2026-07-29T00:00:00",
    "allday":  true,
    "subject": "Sprint Planning",
    "organizer": "Dave"
  }
]
```

Required fields: `start`, `end`, `subject`.
Optional: `organizer`, `location`, `body`, `entryid`, `allday`.
All-day `end` is exclusive (Outlook convention: a Mon–Wed event ends on Thu midnight).

### Week view key bindings

| Key | Action |
|---|---|
| `K` | Popup preview (subject, time, organizer, location, body excerpt — Teams/Zoom links stripped) |
| `<CR>` | Open full appointment body in a split below |
| `n` | Open a native provider event at the selected date/hour |
| `e` | Edit the appointment under the cursor (organizer only) |
| `?` | Show week-view key bindings |
| `q` / `<Esc>` | Close the appointment split |

The `compose` hook receives start and end strings in `YYYY-MM-DD HH:MM`
format. The `edit` hook receives the provider-specific `entryid`.

## Address book completion

Set `address_book` in a diary entry to enable `<C-X><C-O>` omni-completion
when editing diary files.  The file format (same as vim-outlook):

```json
[
  {"name": "Alice Smith", "email": "alice@example.com"},
  {"name": "Bob Jones",   "email": "bob@example.com"}
]
```

When using vim-outlook, it writes this file automatically.  In pure-Outlook
setups you can export contacts from PowerShell:

```powershell
$ol = New-Object -ComObject Outlook.Application
$contacts = $ol.GetNamespace("MAPI").GetDefaultFolder(10).Items
$book = $contacts | ForEach-Object {
    [ordered]@{ name = $_.FullName; email = $_.Email1Address }
} | Where-Object { $_.email }
[IO.File]::WriteAllText(
    "$env:TEMP\outlook_address_book.json",
    ($book | ConvertTo-Json),
    [Text.UTF8Encoding]::new($false))
```

## Full help

```vim
:help calendar
```

## Code structure

- `frontend.vim` coordinates calendar windows, navigation, and public commands.
- `calendar_view.vim` and `week_view.vim` render calendar and appointment views.
- `config.vim`, `diary.vim`, and `diary_search.vim` own configuration and diary operations.
- `appointments.vim` parses and caches appointment data.
- `help_popup.vim` and `highlights.vim` contain focused UI behavior.

## License

BSD-3.

[1]: https://github.com/mattn/calendar-vim
