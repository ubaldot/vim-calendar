# vim-calendar — Architecture & Design Notes

**Purpose of this document.** The durable design record for `vim-calendar`: what the
plugin is, how it is put together, which decisions were taken and *why*, and which
approaches were tried and deliberately abandoned. It is aimed at contributors and at AI
assistants working on the codebase, so that neither has to rediscover context that was
already settled.

It was distilled from the project's full development history (two long working sessions
covering 22 July – 3 August 2026, plus six milestone checkpoints) and verified line by
line against the source tree.

**Conflict rule applied throughout:** where the early phase (`master` / `new_architecture` /
`new_calendar`, Jul 22–26) and the late phase (`prepare_for_outlook` → `main`, Jul 31 – Aug 3)
disagree, the late phase wins. Superseded decisions are kept but explicitly marked
**[SUPERSEDED]** so nobody re-introduces them.

> **Maintenance note.** Sections 2 (Current state) and 7 (Open TODOs) are the parts that
> go stale first. Sections 3–5 (architecture, decisions, conventions) are long-lived.

---

## Table of contents

1. [What vim-calendar is](#1-what-vim-calendar-is)
2. [Current state](#2-current-state)
3. [Architecture](#3-architecture)
4. [Key design decisions and rationale](#4-key-design-decisions-and-rationale)
5. [Conventions and constraints the user cares about](#5-conventions-and-constraints-the-user-cares-about)
6. [Known issues, bugs and gotchas](#6-known-issues-bugs-and-gotchas)
7. [Open TODOs / next steps](#7-open-todos--next-steps)
8. [Glossary / map of the codebase](#8-glossary--map-of-the-codebase)

---

## 1. What vim-calendar is

### Identity

- Repository: `ubaldot/vim-calendar` (GitHub). Author: **Ubaldo Tiberi** (`ubaldot`,
  `ubaldo.tiberi@volvo.com` in commits). License: **BSD-3-Clause**.
- Lineage: originally a fork of [`mattn/calendar-vim`][mattn]. The agreed wording, settled in
  the last session and now live in `README.md` and `doc/calendar.txt`, is:
  > "A Vim 9.0 **ported, refactored and enhanced** version of mattn/calendar-vim."
  The assistant argued it is now a **hard fork** ("independent project derived from…"), the user
  chose "ported, refactored and enhanced". Git ancestry and attribution are kept for provenance,
  but releases/compat/roadmap are treated as an independent plugin. **Nothing of the original
  code survives**: `autoload/calendar.vim` (the monolith) was deleted in the first days.

### What it does today

A calendar + diary + *calendar-events* workbench that lives in its own Vim tab:

- Left/right split pane with N months rendered vertically (`__Calendar__`).
- A **week view** pane (`__WeekHeader__` + `__WeekView__`) showing a scrollable 24-hour grid
  with events, all-day banners, organizer names.
- Multiple **diaries** ("diary books"), each mapping to a directory of Markdown files
  (`YYYY/January.md` or `YYYY/January/01.md`).
- **Provider-neutral calendar events**: any backend (local JSON, Outlook, Google, CalDAV…)
  can be plugged in via two global functions.
- Meeting **reminder popups** with one-shot timers + sound.
- Holidays, ISO week numbers, EU/US/work-week layouts, quickfix diary search,
  address-book omni-completion for attendee fields.

### Target user

The author himself first: a Windows engineer at Volvo who lives in Vim, keeps a Markdown diary,
and wants Outlook meetings visible (and manageable) without leaving the editor. Secondary
audience: Vim 9 users who want a calendar/diary that can be wired to *any* event source.

### Version / language assumptions

- **Vim 9.0+ / Vim9script only.** `plugin/calendar.vim` hard-guards:
  ```vim
  if !has('vim9script') || v:version < 900
    finish
  endif
  ```
- **Neovim is explicitly NOT supported.** The user asked (Aug 3) to strip every Neovim
  reference from README and help: it is Vim9script, so it cannot work in Neovim. Do not
  re-introduce `stdpath()`, `nvim_*`, or "works with Neovim" claims.
- CI tests Vim `nightly`, `v9.1.1071` (Linux/macOS) and `v9.1.1270` (Windows).
- Optional feature guards used in the code: `exists('+winfixbuf')`, `exists('+relativenumber')`,
  `exists('+winhighlight')`, `has('win32')`, `has('mac')`.

### Platform notes (this is a Windows user)

- Dev machine: `C:\Users\yt75534\vimfiles\pack\minpac\start\vim-calendar` (minpac).
  Sibling plugin: `..\vim-outlook`.
- Windows-specific behavior that already exists in the code:
  - local-provider data dir → `%LOCALAPPDATA%\vim-calendar` on `has('win32')`;
    `$XDG_DATA_HOME/vim-calendar`; else `~/.local/share/vim-calendar`.
  - reminder sound → `powershell -NoProfile -WindowStyle Hidden -Command
    [System.Media.SystemSounds]::Asterisk.Play()` via `job_start`; `afplay` on mac; silent
    elsewhere.
- Outlook integration is **classic Outlook COM** only (PowerShell + `Outlook.Application`).
  New Outlook would require Microsoft Graph — see §4.

---

## 2. Current state

### Head

- Branch **`main`**, commit **`17125fc` "Bugfix based on Claude Opus review"** (Aug 3 2026).
- Working tree **clean** — everything discussed in the transcripts is committed.
- `main` is the **authoritative** branch. `origin/HEAD` still points at `origin/master`;
  the user's stated plan (Turn 110–113 of the latest transcript) is to make `main` the GitHub
  default branch and then delete `master` from the remote. **That flip may still be pending.**

### Branch layout (all other branches are ancestors of `main` — history is linear)

| Branch | Head | Meaning |
|---|---|---|
| **`main`** | `17125fc` (Aug 3) | **Authoritative.** Created explicitly to "ditch master". Contains everything. |
| `master` | `85c4d82` (Jul 29) "test: sync run_tests.py harness with vim-markdown-extras" | The old default branch, pre-Outlook/pre-provider. Historical only. Was going to be force-replaced (`--force-with-lease`), then the user chose to create `main` instead. |
| `new_architecture` | `aea384d` (Jul 23) "Added more tests. Everything seems to work now" | End of the early frontend/backend rewrite phase (still `autoload/`, still popup mode, no week view). |
| `new_calendar` | `1e169ed` (2025-09-21) "Added some sugar and defined DayUnderCursor" | Oldest prototype: the user's original `DisplaySingleCal()` / `DisplayMultipleCalVert()` sketch that the whole rewrite was later based on. |
| `outlook_interactivity` | `c23427e` (Jul 31) "Creations of events won't work. Abandoned." | Dead-end: first attempt at in-Vim Outlook meeting creation/sending. Explicitly abandoned. |
| `prepare_for_outlook` | `186f814` (Aug 3) | The big work branch (popup removal, provider contract, local provider, event form, delete/accept/tentative). `main` = this + 5 commits. |

Remote (`origin`) has: `main`, `master`, `new_architecture`, `prepare_for_outlook`
(no `outlook_interactivity`, no `new_calendar`).

### The last 6 commits on `main` (most recent first)

```
17125fc Bugfix based on Claude Opus review      # virtcol() + FitCell() grid fixes
21221f0 Updated hi-group for today              # CalToday = Visual + bold
60b7a3a Updated README
e30556d Updated README
7b8d61b Polish project identity and today highlight
186f814 (= prepare_for_outlook tip) omnifunc/attendees/lifecycle-events/screenshot
```

### What works today

- `:CalendarToggle [year [month]]` opens a dedicated **tab**: calendar pane + week view;
  focus lands in `__WeekView__`. Toggling again from that tab closes it; from another tab it
  jumps to it.
- Calendar pane: `<C-Up>/<C-Down>` month, `<C-Left>/<C-Right>` year, `t` today,
  `<Tab>/<S-Tab>` cycle diary, `<CR>` navigate week view to the day under the cursor,
  `<C-CR>`/`<S-CR>` close the tab and open the diary file, `q` close, `?` help popup,
  `<F5>` refresh.
- Week view: `K` preview popup, `<CR>` full body in a split, `m` create-or-edit (contextual),
  `d` delete/decline/cancel, `a` accept, `v` tentative, `<C-Left>/<C-Right>` week,
  `t` current week, `<Tab>/<S-Tab>` diary, `<F5>` refresh, `?` help.
- Hookless diaries automatically persist events to a local JSON file through
  `lib/local_provider.vim` and edit them in the `__CalendarEventForm__` buffer
  (`W` save, `Q` discard, `?` field help, `:w` also saves).
- Outlook diaries work end-to-end via `vim-outlook`'s
  `g:OutlookCalendarFetchEvents` / `g:OutlookCalendarManageEvents`.
- Reminders: 15-min-before + at-start popups, snooze (`<Esc>`, 5 min), dismiss (`d`), sound.
- **67 tests**, all passing, across `test_calendar.vim` (25), `test_week_view.vim` (32),
  `test_reminder.vim` (10).

### Release status

The user asked "is it OK for release?" (Aug 3) and the answer was **yes, suitable for 1.0**,
given breaking changes are intentional and documented, with two caveats at the time: commit the
pending highlight changes (done — `21221f0`) and set GitHub's default branch to `main`.
Then Claude Opus found and fixed two release-blocking week-grid bugs (`17125fc`).
So: **1.0-ready, tag not yet cut (no tags observed).**

---

## 3. Architecture

### Layer diagram

```
                     ┌──────────────────────────────────────────────┐
 user commands  ───► │ plugin/calendar.vim  (thin wiring only)       │
 :CalendarToggle     │  • 6 commands                                │
 :CalendarRefresh    │  • g:CalendarAddressBookComplete             │
 :CalendarSearch     │  • g:CalendarLocalFetchEvents                │
 :CalendarWipe       │  • g:CalendarLocalManageEvents               │
 :CalendarWeekNav    └───────────────┬──────────────────────────────┘
 :CalendarDiaryCycle                 │ import autoload
                                     ▼
   ┌─────────────────────────────────────────────────────────────────────┐
   │ lib/frontend.vim  — ORCHESTRATOR (639 lines)                        │
   │  InitVariables() ← config.Load()                                    │
   │  tab/window lifecycle, diary activation & cycling, provider select, │
   │  navigation dispatch (Action/HandleNavigation), diary opening       │
   └───┬────────┬────────┬────────┬────────┬────────┬────────┬───────────┘
       │        │        │        │        │        │        │
       ▼        ▼        ▼        ▼        ▼        ▼        ▼
  config.vim  calendar  week_view  diary  diary_   help_   highlights
   (normalize) _view.vim  .vim     .vim   search   popup     .vim
       │      (month     (week      (md    .vim     .vim       │
       │       grid)      grid,     files)                     │
       │        │         events,                              │
       ▼        ▼         actions)                             ▼
   g:calendar  backend.vim  ──► appointments.vim ──► reminder.vim
    _config    (pure date    (parse+cache JSON)     (timers+popups)
               math, JDN)          │
                                   │  provider boundary
                    ┌──────────────┴──────────────────────┐
                    ▼                                     ▼
        lib/local_provider.vim                 ../vim-outlook
        (built-in JSON DB +                    ms_calendar.vim +
         __CalendarEventForm__)                 *.ps1 (Outlook COM)
                                               …or ANY user hook
```

### Buffers (all `nofile`/`acwrite`, `nobuflisted`, mostly `winfixbuf`)

| Buffer | Module | Role |
|---|---|---|
| `__Calendar__` | `frontend.vim` | Left/right month grid pane |
| `__WeekHeader__` | `week_view.vim` | Fixed-height top: all-day banners, day labels, TZ label, separators |
| `__WeekView__` | `week_view.vim` | Scrollable 24-hour grid; week title in `statusline` |
| `__Appointment__` | `week_view.vim` | `<CR>`: full event body in a split below |
| `__CalendarEventForm__` | `local_provider.vim` | `buftype=acwrite` create/edit form |

Historical buffer names: `__Calendar` (no trailing underscores) was renamed to `__Calendar__`
in commit `a3db9ed`.

### Frontend / backend (provider) split — the central idea

Three separations, do not confuse them:

1. **`backend.vim` vs everything else** — `backend.vim` is *pure date math*
   (Julian Day Numbers, ISO weeks, month grids). The user was emphatic: **"You should NOT touch
   autoload/backend.vim. That already worked."** Everything else must consume it, never
   re-implement date arithmetic.
2. **rendering (`calendar_view.vim`, `week_view.vim`) vs orchestration (`frontend.vim`)**.
3. **plugin vs *calendar provider*** — the provider-neutral contract below.

### The neutral calendar provider contract (authoritative)

Configured **per diary** in `g:calendar_config.diaries_dict.<name>`:

```vim
{
  fetch_events:  'g:MyCalendarFetchEvents',   # string: name of a GLOBAL function
  manage_events: 'g:MyCalendarManageEvents',
}
```

Both are *string names of global functions*, resolved with `exists($'*{name}')` and called with
`function(name)(...)`. If **both** are empty the built-in local provider is used
(`g:CalendarLocalFetchEvents` / `g:CalendarLocalManageEvents`). A *partially* configured
provider does **not** silently mix with local persistence.

#### Exact signatures a provider must implement

```vim
# ── 1. Fetch ────────────────────────────────────────────────────────────────
def g:MyCalendarFetchEvents(request: dict<any>): string
  # request.start : 'YYYY-MM-DD'  INCLUSIVE
  # request.end   : 'YYYY-MM-DD'  EXCLUSIVE
  # MUST write normalized JSON (list of event objects) to a DISPOSABLE path and
  # return that path.  vim-calendar deletes the file after reading it.
  # NEVER return the persistent database path.
  # Return '' on failure.
enddef

# ── 2. Manage ───────────────────────────────────────────────────────────────
def g:MyCalendarManageEvents(request: dict<any>): bool
  # request.action is one of:
  #   {action: 'create',    start: 'YYYY-MM-DD HH:MM', end: 'YYYY-MM-DD HH:MM'}
  #   {action: 'edit',      id: '<provider id>'}
  #   {action: 'delete',    id: '<provider id>', start: '<provider timestamp>'}
  #   {action: 'accept',    id: '<provider id>', start: '<provider timestamp>'}
  #   {action: 'tentative', id: '<provider id>', start: '<provider timestamp>'}
  # Return false when the action is unsupported/failed.
enddef
```

Notes that cost real debugging time:

- `start` in delete/accept/tentative is `provider_start` — the **untruncated** provider
  timestamp, needed to disambiguate a *recurring occurrence* (Outlook resolves the occurrence
  of a recurring master by start; moved exceptions are searched by their current start).
- Range boundaries are computed by **vim-calendar**, never by the provider:
  `week_view.FetchRange()` → EU: Mon…next Mon, US: Sun…next Sun, work: Mon…Sat (covering Mon–Fri).
- Comparing an `any`-typed hook result with `is false` raises Vim9 **E1072**. The code uses
  `if type(result) == v:t_bool && !result`.

#### Event JSON (the wire format between provider and plugin)

```json
[
  {
    "id":        "local-1754209...",
    "start":     "2026-08-03T09:00:00",
    "end":       "2026-08-03T10:00:00",
    "subject":   "Planning",
    "required_attendees": "Alice <alice@example.com>",
    "optional_attendees": "Bob <bob@example.com>",
    "organizer": "Alice Smith",
    "location":  "Room A",
    "body":      "Agenda:\n1. …",
    "allday":    false
  }
]
```

- Required: `start`, `end`, `subject`. Optional: everything else.
- `id` is a **generic opaque string**. It replaced the Outlook-specific `entryid` when the
  contract was made neutral.
- All-day: `"allday": true`, **`end` is exclusive** (Mon–Wed ⇒ `end: 2026-07-30T00:00:00`).
- JSON must be **UTF-8 without BOM** (there is a vim-outlook commit specifically for this:
  `e660d9b "Fix calendar JSON encoding: UTF-8 without BOM"`).

#### Internal normalized shape (`appointments.LoadFile()`)

`lib/appointments.vim` turns the provider list into:

```vim
{
  '2026-07-27': [ {start: '09:00', end: '10:00', subject: …, organizer: …,
                   location: …, body: …, id: …, provider_start: '2026-07-27T09:00:00'} , … ],
  '2026-07-29': [ … ],
  'allday':     [ {start_date: 'YYYY-MM-DD', end_date: <inclusive last day>,
                   subject: …, organizer: …, id: …, provider_start: …, allday: true} , … ],
}
```

- Times are `strpart(start, 11, 5)` → `HH:MM`. `\r` is stripped from all text fields (`StripCR`).
- All-day `end_date` is converted from exclusive to **inclusive last day** (`JDN - 1`).
- ⚠️ `'allday'` is a magic key inside a date-keyed dict (see §6).
- `LoadFile()` **`delete()`s the file it read** — this is why providers must return snapshots.
- The cache (`appointments.vim`) is keyed by **displayed-week start date** (`WeekCacheKey`).

### Week view internals (`lib/week_view.vim`, 792 lines — largest module)

- Geometry: `WEEK_TIME_COL = 8` chars for the hour column, then `│`, then N day cells of
  `week_day_col` (default 16, min 8) chars separated by `│`.
- Rendering builds three maps rebuilt on **every** `RenderWeekView()`:
  - `appt_line_map: dict<list<dict>>` — body line number (string) → per-column event dicts
  - `allday_line_map: dict<dict>` — header line → `{event, first_col, last_col}`
  - `slot_line_hour: dict<number>` — body line → hour
  plus `displayed_dates: list<string>`.
  Slot metadata is **stored while rendering**, not inferred from line arithmetic, because
  overlapping events add a variable number of rows per hour.
- Hit testing uses **`virtcol()`**, never `col()` — `│` is 3 bytes (see §6, bug #1).
- Cell padding uses `FitCell()`/`TruncateToWidth()` (`strdisplaywidth`/`strcharpart`), never
  `printf('%-*s')`, which pads by **bytes** and breaks the grid on `Müller`/en-dashes.
- Each hour renders **2 lines per event slot**: subject line + `(organizer)` line; both map to
  the same event. The view scrolls to hour 7 on open (`hour7_line` + `&scrolloff`, `normal! zt`).
- Cross-view actions use handlers installed by `frontend.vim`; `week_view.vim` does not import
  the orchestrator, so dependencies remain one-way.
- Public API: `SetProviderFuncs()`, `SetNavigationHandlers()`, `Configure()`,
  `OpenWeekViewWindow()`, `RenderWeekView()`, `NavigateWeekView()`, `FetchEvents()`,
  `CalendarRefresh()`, `RescheduleReminders()`, `GetEventAtCursor()`, `GetSlotAtCursor()`,
  constants `WEEK_BUF_NAME`, `WEEK_HDR_BUF_NAME`, `APPT_BUF_NAME`.

### Calendar pane internals (`lib/calendar_view.vim`, 368 lines)

- `BuildView(base_year, base_month)` is the **single rendering entry point**. It returns
  `{lines, blocks, diary_rows, today, sat, sun, holiday, week}` where the last five are
  `matchaddpos()` position lists and `blocks` carries per-month
  `{year, month, line_start, line_end, col_start, col_end, day_col_start, day_col_end}`.
- `BuildMonthLines()` renders one month (the descendant of the user's original
  `DisplaySingleCal()`); `BuildVerticalComposite()` stacks them (descendant of
  `DisplayMultipleCalVert()`); `AppendDiarySection()` appends the diary selector
  (only when >1 diary is configured).
- Header line 1 is literally `Hit "?" for help`, then a blank line, hence the `+2` line shift
  applied to every position list and block.
- Week numbers render as a **left `WK` column** (`WK` + two spaces before `Mo`), highlighted
  with `CalWeeknm`.

### Popups / forms in use

| Popup | Where | Keys |
|---|---|---|
| Calendar help | `help_popup.Show()` | `q`/`<Esc>` |
| Week-view help | `help_popup.ShowWeek()` | `q`/`<Esc>` |
| Event preview (`K`) | `week_view.ShowAppointmentDetails()` → `popup_atcursor` | `q`/`<Esc>` |
| Reminder | `reminder.ShowReminderPopup()` | `<Esc>` snooze 5', `d` dismiss |
| Event-form field help (`?`) | `local_provider.ShowFormHelp()` | `q`/`<Esc>`/`?` |

All popups use the same border charset `['─','│','─','│','╭','╮','╯','╰']`, `border: [1,1,1,1]`,
`mapping: 0` and an explicit `filter`.

### Configuration schema (`g:calendar_config`, normalized by `lib/config.vim`)

```vim
g:calendar_config = {
  position:               'left',      # 'left' | 'right'                    (popup REMOVED)
  cal_type:               'eu',        # 'eu' | 'us' | 'work'  (month grid)
  show_week_number:       false,
  number_of_months:       3,           # min 1
  holidays:               {'2026-12-25': 'Christmas'},   # 'YYYY-MM-DD' -> label
  search_grep:            'internal',  # 'internal' (:vimgrep) | 'external' (:grep)
  auto_create_diary_dirs: false,
  week_display_type:      'eu',        # 'eu' | 'us' | 'work'  (week view columns)
  week_cell_width:        16,          # min 8
  reminder_sound:         true,
  diaries_dict: {
    My_Diary: {
      path:          '~/my_diary',     # default
      resolution:    'month',          # 'month' | 'day'
      fetch_events:  '',               # optional provider hook name
      manage_events: '',               # optional provider hook name
      events_file:   '',               # optional local-provider JSON path
      address_book:  '',               # optional JSON [{name,email}, …]
    },
  },
  active_diary: 'My_Diary',
}
```

`config.Load()` normalizes with a `Choice(value, allowed, fallback)` helper, falls back to
`DEFAULT_DIARIES` when `diaries_dict` is missing/empty, repairs an invalid `active_diary`
(writes it back to `g:calendar_config`), and `echomsg`s a warning if `fetch_events` is set at
**top level** (it must be per-diary).

---

## 4. Key design decisions and rationale

Ordered roughly chronologically. `[SUPERSEDED]` = deliberately reversed later.

### D1. Kill the monolith; split frontend / backend / plugin
**Decision.** Delete `autoload/calendar.vim` (mattn's monolith), keep `backend.vim` (date math)
and rewrite `frontend.vim` (UI), with `plugin/calendar.vim` as a thin command layer.
**Why.** The original was "very messy"; every change touched everything.
**Rejected.** Keeping the monolith "for reference" — the user only wanted it as a temporary
crutch and asked for its removal as soon as the split was complete.

### D2. `backend.vim` is sacred
**Decision.** Never modify `backend.vim`; the frontend must call
`CalendarMonth_iso8601()` / `ConvertISOtoUS()` / `WeekDays()` / `DateToJDN()` / `JDNToDate()` /
`ISOWeekNum()` / `WeekdayForDate()` instead of doing its own date arithmetic.
**Why.** It was already correct and unit-verifiable. The user twice caught the assistant
"just remapping the old calendar.vim into frontend.vim" without importing backend at all.
**Rejected.** Re-implementing month loops in the renderer.

### D3. Single config dict `g:calendar_config`, unprefixed keys
**Decision.** All configuration lives in one dict; the `calendar_` prefix is dropped from every
key (`g:calendar_erafmt` → `erafmt`, etc.). Legacy globals were kept briefly, then removed.
**Why.** One discoverable surface; no scattered `exists('g:calendar_*')` checks.
**Rejected.** ~15 separate globals as in the original plugin.

### D4. `InitVariables()` → script-local state
**Decision.** Config is read once per entry point into script-local `cfg_*` variables; runtime
state lives in script-local `state_*` variables (not `b:`).
**Why.** The user: *"frontend.vim looks very messy… remove these variables and use
ApplyCalendarConfig() to set script-local variables"*, then later *"Can the b: variables be
script-local instead? In this way we should be able to reduce the number of variables."*
`b:CalendarBaseYear` → `state_base_year`, `b:CalendarBlocks` → `state_blocks`, etc.
Note the *tab*-local exceptions that remain by design: `t:cal_week_key`,
`t:cal_curr_week_num`, `t:cal_fetch_events_func`.

### D5. Diaries as a dict, not a list
**Decision.** `diaries_dict: {Name: {path, resolution, …}}` + `active_diary: 'Name'`,
replacing `g:calendar_diary_list = [{name, path, ext, resolution}, …]` and `g:calendar_diary`.
**Why.** Lookup by name; no index bookkeeping (`diary_list_curr_idx` is gone).
**Rejected.** List-with-index; per-diary `ext` (always `.md` now).

### D6. Two diary resolutions
**Decision.** `resolution: 'month'` → `<path>/YYYY/January.md`;
`resolution: 'day'` → `<path>/YYYY/January/01.md`. Default is **`month`** (user's own choice,
changed from `day`).
**Why.** He keeps monthly notes, occasionally daily.

### D7. Naming: `OpenDiaryPage()`, `My_Diary`, `~/my_diary`
**Decision.** Rename the default action function `Diary()` → `OpenDiaryPage()`, default diary
key `Diary` → `My_Diary`, default path `~/diary` → `~/my_diary`.
**Why.** The user spotted a genuine collision: `Diary` meant both a function and a diary name.
Verbs for functions, nouns for data.

### D8. Directories are not silently created… then opt-in creation
**Decision (v1).** Never `mkdir()` behind the user's back — warn instead; `MakeDir()` deleted.
**Decision (v2, current).** Add `auto_create_diary_dirs` (default **false**). When true,
`diary.EnsureDir()` does `mkdir(path, 'p')`; when false it shows a `confirm()` prompt
*"please create diary directory: …"*.
**Why.** Safety by default, convenience opt-in.

### D9. Removed all directional commands; position comes from config
**Decision.** `:CalendarH`, `:CalendarVR`, `:CalendarT`, `:CalendarP` all deleted; a single
entry point takes only `[year [month]]`.
**Why.** The old `dir` argument with magic values `0,1,2,3` produced "that horrible logic …
in a huge monolithic block". Position is a *setting*, not a command variant.
**Trace.** `Show(a2, a3, dir)` → `Show(year, month)`; the `dir` argument was also dropped from
the action callback, making it `(day, month, year, week)`.

### D10. Arrows move the cursor; Ctrl+arrows move the view
**Decision.** Plain `hjkl`/arrows do nothing but move the cursor. `<C-Up>/<C-Down>` = prev/next
month, `<C-Left>/<C-Right>` = prev/next year. `t` = today. Cursor is placed **on today** when
the calendar opens.
**Why.** The user rejected the original's arrow-driven navigation outright:
*"don't bother with the original mappings"*. He also caught that Ctrl-navigation was moving the
cursor line as a side effect (fixed by saving/restoring `getpos('.')` and by using
buffer-local `nnoremap`, not `nmap`).

### D11. No `<Plug>` indirection
**Decision.** Map keys directly to `<ScriptCmd>Func()<CR>` / `<Cmd>Command<CR>`.
**Why.** User: *"the following can be simplified given that `<Plug>…` are not used any longer
(user cannot map)"*. Since mappings are buffer-local to plugin-owned scratch buffers, the extra
layer bought nothing.

### D12. Highlighting via `matchadd()`/`matchaddpos()`, not `:syntax`
**Decision.** All calendar-pane highlighting is window matches with explicit priorities
(today 40, week 35, holiday 32, sat/sun 30, header/CalHeader 25, weekdays 22, help 20,
diary list 15). No `syntax match`, and **`filetype=calendar` is never set**.
**Why.** The user found `synIDattr(synID(...))` returning `calendarNumber` / `Constant`; the
culprit was Vim's **runtime** `$VIMRUNTIME/syntax/calendar.vim` loading because the buffer's
filetype was `calendar`. Setting `ft` was removed. `:syntax` definitions were then added only
for `synID` introspection and immediately removed again — *"Let's keep it simple"*.
**Consequence.** `synID()` will NOT report calendar groups; use `getmatches()` to inspect.

### D13. Highlight-group policy (current)
- `CalToday` = a **copy of `Visual`** (`hlget('Visual', true)`) with `bold` forced on, defined
  programmatically in `DefineTodayHighlight()`. Rationale (Aug 3): plain bold was invisible, and
  a separate background confused it with the displayed-week highlight; the user asked for
  *"bold but with the same background colour used for highlighting the displayed week"*.
- `CalSaturday`→`LineNr`, `CalSunday`→`Error`, `CalHoliday`→`Error`, `CalWeekdays`→`WarningMsg`,
  `CalHeader`→`WarningMsg`, `CalWeeknm`→`Visual`, `CalCurrWeek`→`Visual`,
  `CalCurrList`→`Error`, `CalHelpHint`→`Question`, `CalWeekToday` = bold.
- **Only weekends/holidays/today/week numbers are coloured** — ordinary day numbers are not.
- Holidays no longer prepend `!`; the `~`/`*`/`+` day markers were all removed.

### D14. Calendar **popup display mode removed** — [SUPERSEDED feature]
**Decision (Jul 31).** Delete `position: 'popup'`, `lib/popup_selection.vim`,
`highlights.ApplyPopup()`, `CalPopupSelection`, `PopupFilter`, `popup_id/popup_year/popup_month`,
`PopupCycleDiary` (renamed `CycleDiary`), and the popup-only tests.
**Why.** Asked "what feature would you remove to drop complexity?", the answer was popup mode —
**not because of line count** but because it is a *second UI architecture* for the same feature:
split mode uses buffers/windows/mappings/native cursor; popup mode duplicated all of it with
popup filters, synthetic selection state, popup IDs and separate render/close paths, doubling the
state combinations and regression surface.
**What was NOT removed:** appointment-preview popups, help popups, reminder popups, the event
form. Only `position: 'popup'` died.
**Earlier work now dead:** the whole `h/j/k/l` day-selection-in-popup machinery
(`CalPopupSelection`, `PopupSetSelectedDay`, `<Tab>` diary cycling inside the popup,
`\<CursorHold>` swallowing in the filter) — implemented Jul 23, deleted Jul 31.

### D15. The custom `action` config key was removed — [SUPERSEDED]
**Decision.** `g:calendar_action` → `g:calendar_config.action` → **deleted**.
**Why.** After popup removal the custom action was only reachable in popup / no-week-view mode,
i.e. dead API. `<CR>` in the calendar pane now always navigates the week view; the diary is
opened with `<C-CR>`/`<S-CR>`.

### D16. Provider-neutral hooks, chosen names, two of them
**Decision.** `fetch_events` + `manage_events` (plural, both).
**Why.** The user: *"we are focusing too much on the Outlook feature whereas we want to keep this
plugin as neutral as possible… at bare minimum we need two functions"*. Names were debated:
- `read`/`write` — **rejected**, too generic, and Outlook does not write immediately (it opens
  an editor).
- `connect`/`compose`/`edit`/`create` — **superseded** (that was the pre-neutral vocabulary).
- `appointment` — **rejected** in favour of `event` (calendars also hold meetings and all-day
  entries).
- `fetch_events` + `manage_event(s)` — chosen; the user picked the plural `manage_events`.

### D17. Fetch takes an explicit `{start, end}` range — not `(year, month, day)`, not `(year, week)`
**Decision.** `fetch_events({start: 'YYYY-MM-DD', end: 'YYYY-MM-DD'})`, start inclusive, end
exclusive.
**Why.** `(year, month, day)` forced every provider to re-derive week boundaries and had caused
a real bug (cache stored under the wrong week). `(year, week)` was **rejected** because it
assumes ISO Monday weeks and is ambiguous at year boundaries. Explicit ranges map directly to
API/DB filters, work for EU/US/work layouts, and cross month/year safely.
**Superseded signature:** `g:MyCalendarFetchEvents(year, month, day): string`.

### D18. Fetched files are disposable snapshots
**Decision.** `appointments.LoadFile()` calls `delete(path)`. Providers must never return their
persistent database path; `local_provider.FetchEvents()` copies to `tempname() .. '.json'`.
**Why.** Guarantees the plugin can always clean up temporary plaintext data, and prevents a
provider's own DB from being deleted.
**Consequence documented for users:** the snapshot may contain the *whole* calendar; filtering
to the requested range is an optional provider-side optimization — vim-calendar renders only the
displayed week regardless.

### D19. Built-in local JSON provider is the default for hookless diaries
**Decision.** If both hooks are empty, `frontend.ConfigureProvider()` wires
`g:CalendarLocalFetchEvents` / `g:CalendarLocalManageEvents`.
Storage: `events_file` if set, else `<platform data dir>/<sanitized-diary-name>-events.json`.
**Why.** A diary should work out of the box; the user wanted to test the plugin without Outlook.
**Rejected.** Storing user data under `~/vimfiles` / `~/.vim` (the user's initial proposal) —
plugin installation directories must not hold user data. Also rejected: keeping it in
`examples/local_json_calendar.vim` (it was promoted into `lib/` and the example deleted).
**Rejected (hard):** Neovim's `stdpath('data')` — it does not exist in Vim and raised **E117**.

### D20. Event editing is a **buffer form**, not command-line prompts
**Decision.** `__CalendarEventForm__`, `buftype=acwrite`, prefilled `Key: value` lines,
`BufWriteCmd` → `SaveForm()`.
**Why.** The user: *"Wouldn't be easier to open a split window with prefilled all the fields …
and then on e.g. ':w' save the event?"* Prompt-based `input()` chains were also untestable
(see §6).
**Keys.** `W` save, `Q` discard, `?` field help. `:w` still works.
`q` and `<Esc>` as discard were **removed on request** — too easy to hit by accident.
**Fields.** `Title`, `Start`, `End`, `Required Attendees`, `Optional Attendees`, `Organizer`,
`Location`, `AllDay`, `Body` (multiline: everything after the `Body:` line).

### D21. One contextual `m` instead of `n` + `e`
**Decision.** `m` = "manage event": edits if `GetEventAtCursor()` returns something, otherwise
creates at `GetSlotAtCursor()`.
**Why.** The user derived it himself: *"if week_view.GetEventAtCursor() does not return
anything, you trigger 'create' otherwise you trigger 'edit', correct?"*
**Superseded:** `n` (create) and `e` (edit) as separate mappings.

### D22. `GetAppointmentAtCursor()` → `GetEventAtCursor()`
Provider-neutral terminology everywhere ("event", not "appointment") in *new* API. Legacy
internal names (`appt_line_map`, `APPT_BUF_NAME`, `ShowAppointmentDetails`) still say
"appointment" — cosmetic inconsistency, deliberately not chased.

### D23. `d` = "remove appropriately for this provider" (not a separate decline key)
**Decision.** One generic `{action: 'delete'}`; the provider decides:
- local JSON → confirm + remove from the file;
- Outlook **attendee** → decline-note form (`__OutlookMeetingResponse__`), `W` sends + removes,
  `Q` aborts;
- Outlook **organizer** → cancellation note, mark cancelled, save, send, delete;
- plain Outlook appointment (no recipients) → direct delete.
Plus `a` accept and `v` tentative (`AppointmentItem.Respond()` + send).
**Why.** *"in Outlook the behavior changes if I am the Organizer or not"*. `D` for delete was
proposed and **rejected** in favour of reusing `d`. `t` stayed "current week", so tentative got
`v`.

### D24. Appointment creation: in-Vim form → **native Outlook inspector** — [SUPERSEDED]
**Decision (final).** For the Outlook provider, `create`/`edit` just open Outlook's own
appointment inspector via COM `Display()` (`compose_appointment.ps1`, `edit_appointment.ps1`).
**Why.** The in-Vim compose flow silently produced imperfect invitations. Outlook then owns
attendee resolution, room booking policies, Scheduling Assistant, Teams, recurrence, reminders
and the final Send. The user: *"could a simplification be that when you hit 'n' you open Outlook
calendar itself with the 'New Event Calendar' window open at the datetime …? Otherwise, one may
get surprises…"* This deleted ~200 lines of workflow across both plugins.
**Deleted with it:** `lib/appointment_editor.vim`, `create_appointment.ps1`,
`find_available_rooms.ps1`.

### D25. Room availability / room picker — **built then removed** — [SUPERSEDED]
**What existed briefly (Jul 31).** A per-diary `rooms:` path key + `room_availability:` hook,
`R` in the appointment editor, `Recipient.FreeBusy()` checks, a picker popup that filled
`Room:`, and a generated `outlook_rooms.json` (48 rooms discovered from the Exchange room
distribution list **`Lundby-AB`**, incl. 2 `Restricted` and 4 `VideoConf`; capacity is embedded
in the room name). Proposed JSON shape:
`{name, email, capacity?, building?, floor?, features?[]}` — only `name`/`email` required.
**Why removed.** Superseded by D24 (Outlook's own UI does this better). Caveat recorded:
free/busy "free" ≠ bookable — room policies can still reject.
**Do not resurrect** unless the user asks; but the design notes above are the starting point.

### D26. Teams meetings: out of scope
Classic Outlook COM has no reliable "make this a Teams meeting" API; MAPI-property hacks are
fragile. Microsoft Graph would be needed. The user: *"Teams, yeah, let's skip it. Let's keep it
simple!"*

### D27. Classic Outlook COM only; Graph is a `vim-outlook` concern
If Graph is ever adopted, the plan is a **backend switch inside vim-outlook**
(`g:outlook_config.backends = {calendar: 'graph', mail: 'com'}`), keeping
`g:OutlookCalendarFetchEvents`/`ManageEvents` as the stable façade.
**vim-calendar needs no changes at all** — this is the payoff of D16/D17.

### D28. Google / Apple / CalDAV: documentation recipes, not code
**Decision.** Ship copy-pasteable Vim9 hook wrappers in `doc/calendar.txt` that shell out to a
user-provided `.ps1`/`.sh`, with a documented CLI contract
(`fetch START END OUTPUT`, `create START END`, `edit ID`, `delete|accept|tentative ID START`;
exit 0 = success; BOM-less UTF-8 JSON). Credentials stay in the OS credential store, never in
`vimrc`.
**Why.** OAuth/CalDAV cannot be reduced to a safe Vim snippet, and shipping fragile ones would
misrepresent them as turnkey.
**Rejected.** Built-in Google/Apple adapters in core.

### D29. Lifecycle autocommands
```vim
autocmd User CalendarBeforeShow    " fired by frontend.RenderView() before drawing
autocmd User CalendarEventCreated  " local provider persisted a NEW event
autocmd User CalendarEventModified " local provider updated an existing event
```
`g:calendar_event` holds the persisted event dict while the two latter run. Documented caveat:
these only fire for the **built-in local provider** — a native/external provider that merely
opens an external editor cannot reliably signal completion.

### D30. Omnifunc only in the event form
**Decision.** `omnifunc=CalendarAddressBookComplete` is set **only** in
`__CalendarEventForm__`, and `diary.Complete()` returns `-2` unless the current line matches
`^\%(Required\|Optional\) Attendees:`. Diary Markdown pages keep the user's own `'omnifunc'`.
**Why.** Explicit request (Aug 3): *"No need to use omnifunc in the diary pages… Here [attendee
fields] is where the omnifunc is needed"*.
**Mechanics.** `&omnifunc` needs a legacy-resolvable *string* name, hence the global wrapper
`g:CalendarAddressBookComplete()` in `plugin/calendar.vim` → `frontend.AddressBookComplete()`
→ `diary.Complete()`. The form stores its originating book in
`b:calendar_address_book_path` so switching diaries does not repoint an open form.

### D31. Reminders: one-shot timers, never polling
**Decision.** Per meeting, two `timer_start()` one-shots: `|pre` (start − 15 min) and `|now`
(start). Identity `date_key .. '|' .. (id or start|subject)`. `fired` persists across same-day
rescheduling; a newer stage `popup_close()`s the older popup for the same meeting;
`popup_zindex` increments so simultaneous popups stack visibly.
**Why.** The reported bug: 15-min popup, no action, then a *second* popup at 10 min — because
rescheduling forgot which stage had already fired.
`CancelAll()` resets timers, popups, `dismissed`, `fired` and `reminder_date`.

### D32. One calendar tab, tab-local shared state
`t:cal_week_key`, `t:cal_curr_week_num`, `t:cal_fetch_events_func`. `frontend.cal_tab_winid`
tracks the tab for toggling. Opening focuses `__WeekView__` by **buffer id lookup**
(`win_findbuf`), deliberately not `wincmd l`, so it works with `position: 'right'` too.

### D33. Breaking changes are acceptable
The user stated plainly: *"I am willing to bring breaking changes, no issues with it"* and
*"I would be fine if the branch fully replace main"*. Backwards compatibility with the old
`:Calendar` command and old globals was therefore **dropped on purpose**. Do not add
compatibility shims unless asked.

### D34. Stop refactoring
Repeated assessment: complexity went 7/10 → 6/10 (popup removal) → 5/10 (native Outlook
compose). Further suggested simplifications — *support one calendar layout only*, *day-only
diary resolution* — were considered genuinely simplifying but **not adopted** because they
remove useful behavior. Extracting pure week-layout math and consolidating state into one dict
were judged reorganization, not simplification. Verdict: *"we keep it as-is"*; future
refactoring should be driven by concrete features or recurring defects.

---

## 5. Conventions and constraints the user cares about

This section is the highest-value one for a future session. These are patterns the user
**corrected repeatedly**.

### 5.1 Vim9script idioms — required

- `vim9script` on line 1 of every `.vim` file. Modules are imported with
  `import autoload "./name.vim"` (relative), never `import autoload "../autoload/…"` any more.
- Exported API uses `export def`; everything else is script-local `def` — the module surface
  should be small.
- Interpolated strings `$'…{expr}…'` are the house style (used everywhere).
- `->` method chaining over nested calls where readable
  (`readfile(path)->join("\n")->json_decode()`).
- Prefer `const` dicts over functions returning literals — the user's own suggestion:
  > *"WeekLabels() can't be just defined as a constant dict, e.g.
  > `const weekdays = {us: [...], eu: [...], work: [...]}`"*
  (Now `calendar_view.weekdays`.)
- `get(dict, 'key', default)` everywhere — direct field access throws when the key is absent.
- Every file ends with `# vim: shiftwidth=2 softtabstop=2 noexpandtab`
  (note: **the modeline says noexpandtab but the files are space-indented, 2 spaces** — copy the
  existing style, do not "fix" the modeline unasked).
- Every function gets a **one-line purpose comment** above it. Explicitly requested:
  *"Also, please write the purpose of each function."*

### 5.2 Vim9script — banned / known traps

| Trap | Error | Fix used here |
|---|---|---|
| `let` | E1126-ish / compile error | Never use `let`; the user snapped: *"you cannot use let in Vim9. I remind you that the script is Vim9"* |
| `[1,1,1,1]` (missing space after comma) | **E1069** | `[1, 1, 1, 1]` — Vim9 requires whitespace after `,` |
| `block. year` (space after dot) | **E1127** | `block.year` |
| `1wincmd w` | **E1050** | `execute $":{ww}wincmd w"` — colon required before a range |
| Dict literal inside `mapnew()` lambda | **E476: Invalid command** | Replace with an explicit `for` loop |
| `try/finally` without a trailing `return` | **E1027 Missing return statement** | Track success, `return` after cleanup |
| `result is false` where result is `any` | **E1072** | `type(result) == v:t_bool && !result` |
| Function referenced before definition at script level | E129 / not-compiled | Mind declaration order; `defcompile` only works through a real import alias |
| `<ScriptCmd>` inside a `BufWriteCmd` autocmd | silently doesn't work | Call the function directly: `autocmd BufWriteCmd <buffer> SaveForm()` |
| `stdpath()` | **E117** | Neovim-only. Use `$LOCALAPPDATA` / `$XDG_DATA_HOME` / `~/.local/share` |
| `nmap` for plugin keys | recursion, stray motions | Always `nnoremap <silent> <buffer>` |

### 5.3 Naming conventions

- Functions: **verb-first**, PascalCase (`OpenDiaryPage`, `BuildMonthLines`, `RescheduleReminders`).
  The rename `Diary()` → `OpenDiaryPage()` was driven by exactly this rule.
- Config keys: snake_case, no `calendar_` prefix, descriptive not abbreviated
  (`show_week_number` not `weeknm`; `position` not `pos`; `cal_type` not `monday`).
- Script-local variables: `cfg_*` for configuration, `state_*` for runtime state.
- Buffers: `__Name__` with leading **and** trailing double underscores.
- Terminology: **event** (neutral) in new API; "appointment" only in legacy internals.
- Data labels are nouns (`My_Diary`); functions are verbs. Never overload one word for both.

### 5.4 Documentation discipline

The user checks docs **every single time** and repeatedly caught them stale:
- *"docs and README don't seem to be updated, or am I wrong?"*
- *"In the docs there are still a lot of old configuration variables…"*
- *"is the doc updated?"* / *"Did you update the documentation?"*
**Rule: any behavior change must land in `README.md` **and** `doc/calendar.txt` **and**
`lib/help_popup.vim` in the same change.** The help popups are user-facing docs too.
Also: he **edits the docs himself between turns** — there have been explicit *race conditions*
with his manual edits. Re-read the docs from disk before editing them; preserve his concise
structure and wording rather than regenerating sections.

### 5.5 Testing

- Runner: `python test/run_tests.py` (local) or `python test/run_tests.py ci`.
  From the repo root on Windows:
  ```powershell
  python test\run_tests.py
  ```
  The script `chdir`s into `test/`, writes a temporary `vimrc_for_tests`, launches
  `vim --clean -i NONE -N --not-a-term -u vimrc_for_tests -S runner.vim`, parses `results.txt`,
  and cleans up. 120-second timeout. `VIMPRG`/`VIM_PRG` override the Vim executable.
- **`test/run_tests.cmd` and `run_tests.sh` no longer exist** — they were replaced by the Python
  harness (shared with `vim-markdown-extras`). The old `.cmd` used to **hang** in a non-terminal
  Vim invocation; if a future harness hangs, that is the historical symptom.
- Test discovery is **textual**: `runner.vim` greps the test file for lines starting with
  `def g:` and runs the ones named `Test_*`. So:
  **every test must be declared as `def g:Test_<something>()` starting in column 1.**
  Anything `def g:` that is not `Test_*` is reported as skipped with a WARNING.
- `:%bw!` runs before each test; `v:errors` and `v:errmsg` are both checked.
- Test files are listed in `run_tests.py` `TEST_FILES`:
  `test_calendar.vim`, `test_week_view.vim`, `test_reminder.vim`. Add new files there.
- `test/common.vim` provides `WaitFor()` / `WaitForAssert()` (borrowed from Vim's own suite).
- Generic (non-Outlook) provider fakes are the norm: tests define local `TestFetchEvents` /
  `TestManageEvents` hooks and use `test/fixtures/appointments.json`.
- **Do not test interactive `input()` with queued `feedkeys(..., 't')`** — it hung Vim and
  leaked keys into the *next* test (causing a spurious `E21`). Inject a prompt function or test
  pure helpers instead. This is the reason the form-based UI is also the testable one.
- CI: `.github/workflows/unittests.yml`, matrix `ubuntu-latest`/`macos-latest` ×
  {nightly, v9.1.1071} and `windows-latest` × {nightly, v9.1.1270}.
- `git diff --check` (whitespace) is run before declaring work done.

### 5.6 The user's recurring preferences and pet peeves

Mined from both transcripts — these are the things that will get a correction if violated:

1. **"That's the wrong fix."** When `winfixbuf` blocked `:edit` (E1513) the assistant added
   `setlocal nowinfixbuf`; the user rejected it: *"This is the wrong fix. The right fix is to
   jump to the previous window before :edit."* → prefer addressing the cause, not disabling the
   guard. (`wincmd p` first, split only if that fails.)
2. **Don't reimplement what a module already provides.** Two separate scoldings about not
   importing `backend.vim` and about `Action()` duplicating information
   `CalendarMonth_iso8601()` already returns.
3. **Long functions are a defect.** `BuildView()` was "very long"; `Action()` was "very long";
   `frontend.vim` at ~1000 lines was unacceptable. Split into named helpers.
4. **Delete dead code aggressively.** `<Plug>` mappings, `DefaultAction()`, `ResolveHooks()`,
   `MakeDir()`, `Show()` (when `Render()` sufficed), the `dir` argument, `g:calendar_sign`,
   the `r` redraw key — all removed on his initiative.
5. **Pixel-level layout pedantry.** Real quotes: *"Between WK and Su there should be two
   whitespaces to have perfect alignment"*; *"A whitespace shall not be added in the month/year
   header but in the weekdays row"*; *"the first space and the first 2 are highlighted (i.e. the
   highlight is a bit off)"*. Alignment complaints must be taken literally; verify the exact
   rendered string.
6. **He edits the code between turns and asks you to review.** Frequent
   *"I made some changes, please check"*, *"I simplified here and there"*. Always re-read the
   files; do not assume your last edit is what is on disk. He also once **overwrote a file by
   accident** and asked for changes to be re-applied.
7. **He asks for numeric ratings** ("0 to 5 stars", "how complex, 0–10?") and expects an honest,
   specific answer with the biggest hotspot named.
8. **He asks "do we still need X?" as a way of saying "remove X".** Treat such questions as
   removal proposals with a request for justification.
9. **Ask before adding a config knob.** `auto_create_diary_dirs` was accepted only after being
   proposed as *opt-in, default false*.
10. **No unnecessary abstraction.** Both "let's keep it simple" and the rejection of extra
    syntax-group machinery came from him.
11. **Statusline format is fixed**: `%A, %Y-%m-%d` → `Monday, 2026-08-03`. No time of day.
    (He asked for the comma explicitly.)
12. **Don't commit test artifacts**: `test/results.txt`, `test/vimrc_for_tests` are runner
    output. He commits himself — **the assistant should generally leave changes uncommitted and
    let him review/commit/push**, unless asked.
13. **Security/privacy honesty.** After a discussion about BSD-3 and liability, he asked for a
    disclaimer in both README and help. The agreed wording avoids claiming the plugin "hides"
    or "securely destroys" data: it says storage is local plaintext, cleanup is best-effort, not
    secure erasure, and users/organizations must assess it themselves. **Do not weaken or
    over-promise here.**

### 5.7 Windows-specific gotchas (learned the hard way)

- **8.3 vs long paths.** Vim may report `%TEMP%` once as `C:\Users\RUNNER~1\…` and once as
  `C:\Users\runneradmin\…`. This broke `Test_open_diary_path_with_special_characters` on
  Windows CI. Fix pattern: compare the **meaningful trailing path components**, not raw absolute
  strings.
- Diary paths must survive spaces and Ex-special characters (`#`, `%`): use `fnameescape()` for
  Ex commands and `shellescape()` for external grep. There are dedicated tests for both.
- PowerShell output can carry **ANSI colour escapes** into Vim error messages — strip them
  (`vim-outlook` does).
- PowerShell note/attachment files must be read explicitly as **UTF-8**.
- Reminder sound uses `job_start(['powershell', '-NoProfile', '-WindowStyle', 'Hidden', …])`
  with `out_io: 'null', err_io: 'null'`.
- OneDrive-backed diary paths with spaces are in real use:
  `C:\Users\yt75534\OneDrive - Volvo Group\CabClimate\diary`.

---

## 6. Known issues, bugs and gotchas

### 6.1 Fixed but worth knowing (they will bite again in the same places)

1. **Wrong-day targeting via byte columns (fixed in `17125fc`).** `GetEventAtCursor()` /
   `GetSlotAtCursor()` used `col()`, but `│` is **3 bytes** in UTF-8, so the error accumulated
   per column: Sunday had 14 of 16 columns resolving to the *next* day. `d`, `a`, `v`, `m` could
   act on the wrong meeting. **Always use `virtcol()` in the week grid.**
2. **Grid misalignment on non-ASCII (fixed in `17125fc`).** `printf('%-*s', …)` pads by bytes;
   one `ü`/`é`/en-dash shrank a row from 127 to 120 columns and shifted every cell to its right.
   **Always use `FitCell()`/`TruncateToWidth()`** (`strdisplaywidth`, `strcharpart`).
3. `E95: Buffer with this name already exists` — opening the calendar after a stale hidden
   `__Calendar__`/`__WeekHeader__`/`__WeekView__` buffer. Fixed by **reusing** existing buffers
   (`sbuffer`) instead of `file`-renaming a new one. Regression test:
   `Test_calendar_reuses_stale_hidden_buffer`.
4. `E1513: Cannot switch buffer, 'winfixbuf' is enabled` — jump to another window first
   (`wincmd p`), split if necessary; only clear `winfixbuf` when wiping buffers.
   `diary_search.Run()` saves/restores `&l:winfixbuf` around `:vimgrep`/`:grep`.
5. Duplicate reminder popups (15-min then 10-min) — fixed by persisting `fired` stages across
   reschedules and by replacing the previous open popup for the same meeting.
6. Appointment cache stored under the wrong week when opening a historical month — fixed by
   setting `t:cal_week_key` **before** the fetch hook fires.
7. US weeks were non-chronological (next Sunday shown before the preceding Mon–Sat) — fixed;
   US weeks are now chronological Sunday→Saturday.
8. Stale reminder timers survived an empty/changed refresh, and survived diary switching —
   both fixed (`RescheduleReminders()` is called explicitly after every fetch and every diary
   change).
9. All-day boundaries could be invalid, and all-day actions fired when the cursor was outside
   the visible banner — fixed via midnight normalization + exclusive end, and
   `first_col`/`last_col` hit testing.
10. Local event form used to write to the *newly active* diary's JSON after a diary switch —
    fixed by capturing `form_events_path` at form-open time.
11. Timestamps containing seconds (`09:00:00`) were prefilled but rejected by the `HH:MM`
    validator — fixed by `FormDateTime()` truncating to 16 chars.
12. Pressing `m` elsewhere while a modified form was open silently wiped unsaved edits —
    fixed: `OpenForm()` refuses and jumps to the modified form.

### 6.2 Open / unresolved

1. **`doc/calendar.txt` ends the CODE STRUCTURE section with a truncated sentence:**
   *"The key for making all machinery to work is thanks to the"* (line ~590). Dangling text,
   clearly an interrupted edit. **Not fixed** (this brief is read-only w.r.t. the repo).
2. **`test/common.vim` line 1 reads `vim9scrip`** (missing `t`). The file is `import`ed by
   `test_calendar.vim` and `test_week_view.vim` and the suite passes, so it is currently benign,
   but it is a latent bug — a genuine `vim9script` header would change the file's semantics.
3. **`events.allday` is a magic key inside a date-keyed dict** — `appointments.LoadFile()`
   returns `{'YYYY-MM-DD': [...], 'allday': [...]}`. Type-punning; flagged in review as a
   non-blocking cleanup (a separate `{by_date, allday}` structure would be cleaner).
4. **The all-day banner still hit-tests in *bytes*** (`allday_line_map.first_col/last_col` come
   from `strlen()`), while the body now uses `virtcol()`. It is self-consistent today (the banner
   line is built from the same byte-measured padding) but it is inconsistent with the body and
   will break if the banner ever contains multibyte text before the hit-test columns.
5. **`WeekViewBuildKeymap()` and `WeekHeaderBuildKeymap()` are near-duplicates** (the header
   omits `<C-Left>/<C-Right>`, `t` and `<CR>`-into-split semantics differ only by intent).
6. **Week-key parsing `str2nr(key[0:3])`, `key[5:6]`, `key[8:9]` is repeated in three places**
   in `week_view.vim` (`FetchEvents`, `LoadAppointments`, `CalendarRefresh`).
7. **Pervasive `dict<any>`** weakens Vim9's type checking; noted as the main readability tax.
8. `week_view.vim` (792 lines) and `frontend.vim` (639 lines) remain the maintenance hotspots —
   rendering + window management + navigation + provider dispatch + mutable tab state.
9. **`origin/HEAD` still points at `origin/master`.** The GitHub default-branch flip to `main`
   and the deletion of remote `master` may still be outstanding.
10. **No release tag exists.** 1.0 was declared "ready", not cut.
11. **Room booking cannot be guaranteed** — even a free/busy-clear room can reject via booking
    policy. Recorded as a domain caveat if room support ever returns.
12. **New Outlook is unsupported** and there is no Graph implementation. Only classic Outlook COM.
13. **Provider lifecycle events are local-provider-only** — `CalendarEventCreated/Modified` do
    not fire for Outlook or external providers.
14. The `t:cal_*` design assumes **one calendar tab**; multiple simultaneous calendar tabs are
    not supported.
15. `test/results.txt` / `test/vimrc_for_tests` are runner artifacts; `.gitignore` should be
    checked before committing after a test run.

---

## 7. Open TODOs / next steps

Deduplicated across all six checkpoints; the latest state wins. Everything that older
checkpoints listed as "remaining" and that is now done has been dropped.

### Release mechanics (highest priority, user-owned)

1. Set GitHub's **default branch to `main`**; then delete remote `master`
   (a `master_bkup` backup branch was recommended and may or may not have been pushed).
2. Cut a **v1.0 tag** / GitHub release.
3. Ensure the sibling **`vim-outlook`** repository is committed and pushed — historically it
   lagged behind vim-calendar and repeatedly showed "substantial uncommitted changes".
   (Current local head there: `5c2e824 "Refactored, integrated with vim-calendar"`.)

### Small, safe cleanups

4. Finish the truncated sentence in `doc/calendar.txt` CODE STRUCTURE ("…is thanks to the").
5. Fix `vim9scrip` → `vim9script` in `test/common.vim`.
6. De-duplicate `WeekViewBuildKeymap()` / `WeekHeaderBuildKeymap()`.
7. Extract a `ParseWeekKey(key) -> [y, m, d]` helper in `week_view.vim` (3 call sites).
8. Make the all-day banner hit-test use display columns for consistency with the body.
9. Consider replacing `events.allday` magic key with an explicit `{by_date, allday}` shape.

### Deferred / conditional

10. Do **not** start another large refactor. Stabilize, collect real-world feedback, and only
    extract from `week_view.vim`/`frontend.vim` when a concrete feature or repeated defect
    demands it (explicit decision D34).
11. Typed dicts / classes instead of `dict<any>` — only if it pays for itself.
12. Microsoft Graph backend — **in `vim-outlook` only**, behind
    `g:outlook_config.backends = {calendar: 'graph', mail: 'com'}`. vim-calendar unchanged.
13. Google / Apple / CalDAV: keep as documentation recipes; if adapters are ever shipped, they
    go under `examples/`, never in `lib/`.
14. Chinese/lunar calendar (discussed Jul 23, never started). Agreed design: **display overlay +
    `popup_atcursor()` day-detail popup** on `CursorMoved`/`CursorHold` (lunar date, leap-month
    flag, festivals, zodiac, solar terms) — this reuses the whole current architecture. A *true
    alternate calendar mode* (lunar month structure, leap months, navigation, diary path
    semantics) would require a new backend contract and was judged ~7/10 effort.
15. Room availability / free-busy: only if explicitly requested; see D25 for the prior design and
    the `Lundby-AB` data source.

---

## 8. Glossary / map of the codebase

### Terms

| Term | Meaning here |
|---|---|
| **Diary** / diary book | A named directory of Markdown notes (`diaries_dict` entry). Not a calendar. |
| **Provider** | The pair of global functions supplying calendar *events*. Local JSON, Outlook, or user-written. |
| **Event** | Provider-neutral calendar entry. Preferred over "appointment" in new code. |
| **Snapshot** | The disposable JSON file returned by `fetch_events`; vim-calendar deletes it. |
| **Week key** | `'YYYY-MM-DD'` of the displayed week's first day; the appointments cache key. |
| **Slot** | A (date, hour) cell in the week grid; source of `{action: 'create'}` start/end. |
| **Block** | One rendered month in the calendar pane, with its line/column bounds. |
| **cal_type** | Month-grid layout: `eu`/`us`/`work`. Replaced the old boolean `monday`. |
| **week_display_type** | Week-view column layout: `eu`/`us`/`work`. Independent of `cal_type`. |
| **resolution** | Diary file granularity: `month` (`YYYY/January.md`) or `day` (`YYYY/January/01.md`). |

### Files (repo root: `C:\Users\yt75534\vimfiles\pack\minpac\start\vim-calendar`)

| Path | Lines | What lives there |
|---|---:|---|
| `plugin/calendar.vim` | 38 | Vim-version guard, `g:loaded_calendar`, the 6 commands, and the 3 global wrappers (`g:CalendarAddressBookComplete`, `g:CalendarLocalFetchEvents`, `g:CalendarLocalManageEvents`). Nothing else — deliberately thin. |
| `lib/frontend.vim` | 639 | Orchestrator: `InitVariables()`, `ConfigureProvider()`, `OpenCalendarWindow()`, `RenderView()`, `Action()`/`HandleNavigation()`, `ActivateDiary()`/`CycleDiary()`/`DiaryCycleNavigate()`, `SwitchDiaryAtCursor()`, `OpenDiaryPage()`, `ActionOpenDiaryAndClose()`, `CalendarBuildKeymap()`, `CalendarToggle()`, `Show()`, `Close()`, `CalendarWipe()`, `WeekViewNavigate()`, `Search()`, `AddressBookComplete()`. |
| `lib/backend.vim` | 254 | **Pure date math, do not touch.** `month_num_to_str`, `DateToJDN()`, `JDNToDate()`, `WeekdayForDate()` (1=Mon…7=Sun), `ISOWeekNum()`, `WeekDays()`, `ConvertISOtoUS()`, `CalendarMonth_iso8601()`. |
| `lib/calendar_view.vim` | 368 | Month-grid rendering: `Configure()`, `SetActiveDiary()`, `WeekNumberEnabled()`, `MonthWeeks()`, `AddMonths()`, `DiaryMonthDir()`, `DiaryFilePath()`, `BuildMonthLines()`, `BuildVerticalComposite()`, `AppendDiarySection()`, `BuildView()`. Owns the `weekdays` const dict. |
| `lib/week_view.vim` | 792 | **Largest module.** Week grid rendering, all-day banners, the `appt_line_map`/`allday_line_map`/`slot_line_hour` maps, `FetchRange()`, provider dispatch (`ComposeAppointment`, `EditAppointment`, `ManageEventAtCursor`, `EventAction`), cursor resolution (`GetEventAtCursor`, `GetSlotAtCursor`), cell geometry (`FitCell`, `TruncateToWidth`), preview popup, `__Appointment__` split, both keymap builders. |
| `lib/config.vim` | 70 | `Load()` — the single normalizer for `g:calendar_config`; `Choice()` validator; `DEFAULT_DIARIES`. Flattens the active diary's keys into the returned dict. |
| `lib/local_provider.vim` | 390 | Built-in JSON provider + `__CalendarEventForm__`: `Configure()`, `EventsPath()`, `FetchEvents()`, `ManageEvents()`; `ReadEvents`/`WriteEvents` (temp+backup atomic-ish writes), `ParseFormLines`, `BuildEventFromForm` (validation, all-day normalization), `FormLines`, `SaveForm` (BufWriteCmd), `OpenForm`, `ShowFormHelp`, lifecycle autocommands. |
| `lib/appointments.vim` | 109 | Week-keyed cache (`Clear/Has/Get/Put/Remove/EventsOn`) and `LoadFile()` — the provider-JSON → render-shape normalizer that also `delete()`s the snapshot. |
| `lib/reminder.vim` | 247 | One-shot timer reminders: `SetSoundEnabled`, `Schedule`, `CancelAll`, `PendingCount`, `FireReminder`, `ShowReminderPopup`, `ReminderFilter` (snooze/dismiss), `PlaySound`. State: `scheduled`, `dismissed`, `fired`, `active_popups`, `reminder_date`, `popup_zindex`. |
| `lib/diary.vim` | 98 | Diary file paths and attendee completion: `Configure`, `EnsureDir` (warn or `mkdir -p`), `PrepareFile` (returns an `fnameescape`d path), `LoadAddressBook`, `Complete` (omnifunc; returns `-2` off attendee lines). |
| `lib/diary_search.vim` | 41 | `Run()` — `:vimgrep`/`:grep` over `<diary>/<year>/**/*.md` into quickfix, with `winfixbuf` save/restore and 4-digit year validation. |
| `lib/highlights.vim` | 93 | `Apply()` (all `matchaddpos`/`matchadd` with priorities), `UpdateCurrWeek()`, `WeekHeader()` (today-column match in the header window), `DefineTodayHighlight()` (Visual + bold), and all `hi def link` defaults. |
| `lib/help_popup.vim` | 71 | `Show()` (calendar pane) and `ShowWeek()` (week view) key-binding popups + shared `Filter()`. **Keep in sync with mappings and docs.** |
| `test/run_tests.py` | 149 | Cross-platform harness (`python test/run_tests.py [ci]`). Writes `vimrc_for_tests`, runs `runner.vim`, parses `results.txt`, cleans up, 120 s timeout. |
| `test/runner.vim` | 73 | Discovers `def g:Test_*` textually, `:%bw!` between tests, records pass/FAIL into `results.txt`, `qall!`. |
| `test/common.vim` | 81 | `WaitFor()` / `WaitForAssert()` helpers (from Vim's own test suite). ⚠️ first line typo `vim9scrip`. |
| `test/test_calendar.vim` | 660 | 25 tests: rendering, positions, help popup, week-number column, `CalendarBeforeShow`, diary cycling, auto-create dirs, special-character paths/search, local provider (snapshot, default path, hookless selection, form create/edit, address-book completion, originating events file, seconds normalization, modified-form protection, delete, malformed JSON), today-bold highlight, stale-buffer reuse. |
| `test/test_week_view.vim` | 807 | 32 tests: window layout, `t:` variables, week keys, event rendering, overlapping events, all-day banners, cursor resolution across **every** cell column, non-ASCII alignment, `manage_events` request shapes, fetch ranges per layout, display types, cell widths, navigation, diary cycling, reminder rescheduling, `:CalendarWipe`. |
| `test/test_reminder.vim` | 131 | 10 tests: scheduling, past meetings skipped, cancel-all, reschedule, empty lists, missing start, sound toggle, immediate fire inside the 15-min window, no repeat of a fired stage. |
| `test/fixtures/appointments.json` | 42 | 5 events incl. overlapping and two all-day spans; ids `ENTRY-1`, `ALLDAY-1`. |
| `doc/calendar.txt` | 625 | Authoritative help: intro, commands, mappings (3 tables), configuration, external calendars (local provider, events JSON, `fetch_events`/`manage_events` hooks, external-script recipe), address book, autocommands, security, code structure, license. |
| `doc/tags` | 21 | Generated help tags. |
| `README.md` | ~95 | Short marketing/quick-start; embeds `Calendar_demo.png`; points at `:help calendar`; includes the security disclaimer. |
| `Calendar_demo.png` | — | Screenshot replacing the old screencast placeholder (added Aug 3). |
| `.github/workflows/unittests.yml` | 63 | CI: Linux/macOS × {nightly, v9.1.1071}, Windows × {nightly, v9.1.1270}. |
| `.github/dependabot.yml` | — | Action updates. |

### Sibling repo: `ubaldot/vim-outlook`

Local path `C:\Users\yt75534\vimfiles\pack\minpac\start\vim-outlook`
(**note:** the repo is `vim-outlook`, not `vim-ms-outlook`). It is a **separate repository** —
commit it separately. Not audited here; only the integration contract matters:

- `lib/calendar/ms_calendar.vim` defines exactly the two neutral hooks
  `g:OutlookCalendarFetchEvents(request): string` and
  `g:OutlookCalendarManageEvents(request): bool`, dispatching on
  `create | edit | delete | accept | tentative`.
- PowerShell scripts under `lib/calendar/ps1_scripts/`:
  `calendar_common.ps1`, `fetch_calendar.ps1` (explicit `[start, end)` overlap filter),
  `compose_appointment.ps1` (unsaved inspector via `Display()`),
  `edit_appointment.ps1` (opens only when the current user is the organizer),
  `respond_appointment.ps1` (classification + decline/cancel/delete/accept/tentative).
- Outlook COM constants recorded during development: `CreateItem(1)` = `olAppointmentItem`;
  recipient types 1 = required, 2 = optional, 3 = resource/room; `MeetingStatus = 1` when
  recipients exist; `Recipients.ResolveAll()` must succeed before sending.
- `lib/mail/…` is the (unrelated) mail side: `ms_outlook.vim` + `address_book.vim`,
  `compose_parser.vim`, `mail_cache.vim`, `mail_filter.vim`, `mail_format.vim`,
  `outlook_process.vim`, `help_popup.vim`. The address book JSON it writes
  (`%TEMP%\outlook_address_book.json`) is the same format vim-calendar consumes.
- Example wiring in the user's `vimrc`:
  ```vim
  cc_diary: {
    path:          'C:\Users\yt75534\OneDrive - Volvo Group\CabClimate\diary',
    resolution:    'month',
    fetch_events:  'g:OutlookCalendarFetchEvents',
    manage_events: 'g:OutlookCalendarManageEvents',
    address_book:  $'{$TEMP}\outlook_address_book.json',
  }
  ```
  (Historic trap: he once configured the *documentation placeholder* names
  `g:MyCalendarFetchEvents`/`g:MyCalendarManageEvents` and nothing worked.)

---

## Appendix A — Complete mapping reference (as implemented at `17125fc`)

**`__Calendar__` pane** (`frontend.CalendarBuildKeymap`)

| Key | Action |
|---|---|
| `<CR>` | Diary switch if on the selector rows; else navigate week view to the day under the cursor |
| `<C-Up>` / `<C-Down>` | Previous / next month |
| `<C-Left>` / `<C-Right>` | Previous / next year |
| `t` | Today (also snaps the week view and resets `t:cal_curr_week_num`) |
| `<Tab>` / `<S-Tab>` | Next / previous diary |
| `<C-CR>` / `<S-CR>` | Close the calendar tab and open the diary entry |
| `q` | Close |
| `?` | Help popup |
| `<F5>` | `:CalendarRefresh` |

**`__WeekView__`** (and `__WeekHeader__`, minus `<C-Left>/<C-Right>`/`t`)

| Key | Action |
|---|---|
| `K` | Preview popup at cursor |
| `<CR>` | Full body in `__Appointment__` split |
| `m` | Manage: edit event under cursor, else create at slot |
| `d` / `a` / `v` | delete / accept / tentative → `manage_events` |
| `<C-Left>` / `<C-Right>` | Previous / next week (`:CalendarWeekNav`) |
| `t` | Current week |
| `<Tab>` / `<S-Tab>` | Diary cycle (`:CalendarDiaryCycle`) |
| `<F5>` | Refresh |
| `?` | Week-view help popup |

**`__CalendarEventForm__`**: `W` save · `Q` discard · `?` field help · `:w` save.
**`__Appointment__`**: `q` / `<Esc>` close.
**Reminder popup**: `<Esc>` snooze 5 min · `d` dismiss (kills both stages for that meeting).

## Appendix B — Commands

| Command | Implementation |
|---|---|
| `:CalendarToggle [year [month]]` | `frontend.CalendarToggle(<args>)` |
| `:CalendarRefresh` | `week_view.CalendarRefresh()` |
| `:CalendarSearch {keyword} [{year}]` | `frontend.Search(<f-args>)` |
| `:CalendarWipe` | `frontend.CalendarWipe()` |
| `:CalendarWeekNav next\|prev\|today` | `frontend.WeekViewNavigate(<q-args>)` — internal, used by mappings |
| `:CalendarDiaryCycle next\|prev` | `frontend.DiaryCycleNavigate(<q-args>)` — internal, used by mappings |

**Removed commands** (do not resurrect): `:Calendar`, `:CalendarH`, `:CalendarVR`,
`:CalendarT`, `:CalendarP`.

## Appendix C — Highlight groups

`CalToday` (Visual + bold, defined at load), `CalSaturday`→`LineNr`, `CalSunday`→`Error`,
`CalHoliday`→`Error`, `CalWeekdays`→`WarningMsg`, `CalHeader`→`WarningMsg`,
`CalWeeknm`→`Visual`, `CalCurrWeek`→`Visual`, `CalCurrList`→`Error`, `CalHelpHint`→`Question`,
`CalRuler`→`Normal` (vestigial), `CalWeekToday` (bold; week-header today column).
Removed: `CalMemo`, `CalPopupSelection`.

[mattn]: https://github.com/mattn/calendar-vim
