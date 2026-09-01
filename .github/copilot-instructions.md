# Copilot instructions — vim-calendar

**Read [`ARCHITECTURE.md`](../ARCHITECTURE.md) before making non-trivial changes.** It holds
the provider contract, 34 numbered design decisions with rationale, and the features that were
built and then deliberately removed. This file is only the short version.

## What this project is

A Vim 9 calendar + diary + calendar-events plugin (BSD-3-Clause), originally ported from
`mattn/calendar-vim` but sharing none of its code. Pure Vim9script, no external runtime
dependency except Python for the test harness. The maintainer develops on Windows; CI also
covers Linux and macOS.

## Language rules (Vim9script)

- `vim9script` on line 1 of every `.vim` file. Import with `import autoload "./name.vim"`.
- Public API is `export def`; everything else is script-local `def`. Keep the module surface small.
- Interpolated strings `$'…{expr}…'` are the house style. `->` chaining where it reads better.
- `get(dict, 'key', default)` rather than direct field access.
- Every function gets a one-line purpose comment above it.
- Prefer a `const` dict over a function that just returns a literal.
- Files end with `# vim: shiftwidth=2 softtabstop=2 noexpandtab`. Indentation on disk is
  **2 spaces**; match the surrounding file and do not "fix" the modeline.

Known traps that have bitten this codebase before:

| Don't | Why |
|---|---|
| `let` | Not Vim9. Use `var` / `const`. |
| `[1,1,1]` | **E1069** — Vim9 needs a space after `,`. |
| `block. year` | **E1127** — no space after `.`. |
| `1wincmd w` | **E1050** — needs `execute $":{n}wincmd w"`. |
| Dict literal inside a `mapnew()` lambda | **E476** — use an explicit loop. |
| `try`/`finally` with no trailing `return` | **E1027**. |
| `result is false` on an `any` | **E1072** — use `type(r) == v:t_bool && !r`. |
| `<ScriptCmd>` in a `BufWriteCmd` autocmd | Silently does nothing; call the function directly. |
| `stdpath()` | **E117** — Neovim only. |
| `nmap` for plugin keys | Always `nnoremap <silent> <buffer>`. |

## Architecture in one paragraph

`plugin/calendar.vim` defines commands; `lib/frontend.vim` orchestrates windows, navigation and
public commands; `lib/calendar_view.vim` and `lib/week_view.vim` render; `lib/backend.vim` is
pure date arithmetic (treat it as sacred — never duplicate its logic); `lib/config.vim`
normalizes `g:calendar_config`; `lib/local_provider.vim` is the default JSON backend.

Calendar data reaches the views through exactly **two provider hooks**, named in the config as
`fetch_events` and `manage_events` and installed via `week_view.SetProviderFuncs()`. The views
only ever know the *names* of two global functions. `fetch_events(request)` gets
`{start, end}` (`end` **exclusive**, `YYYY-MM-DD`) and returns the path of a JSON file that
vim-calendar reads once and then **deletes** — so always hand back a disposable snapshot,
never your live database. `manage_events(request)` handles `create`/`edit`/`delete`/`accept`/
`tentative` and returns `false` for anything it does not support. Adding a backend must never
require touching the views.

## Conventions

- Functions are verb-first PascalCase (`OpenDiaryPage`, `BuildMonthLines`).
- Config keys are snake_case with no `calendar_` prefix, spelled out, not abbreviated.
- Script-locals: `cfg_*` for configuration, `state_*` for runtime state.
- Buffers are named `__LikeThis__`.
- Say **event** in new API surface; "appointment" survives only in legacy internals.
- Long functions are treated as a defect — split into named helpers.
- Delete dead code rather than leaving it commented out.

## Documentation is part of the change

Any behavior change must update **`README.md`, `doc/calendar.txt` and `lib/help_popup.vim`
in the same change** — the help popup is user-facing documentation too. `doc/calendar.txt`
wraps at 78 columns; note that `*word*` in a help file **defines a help tag**, so never use
asterisks for emphasis there. Regenerate tags with `:helptags doc` (`doc/tags` is gitignored).

## Testing

```powershell
python test\run_tests.py        # local
python test\run_tests.py ci     # CI mode
```

- Test discovery is **textual**: `runner.vim` scans for lines beginning `def g:` and runs those
  named `Test_*`. Every test must be `def g:Test_<name>()` starting in **column 1**; anything
  else matching `def g:` is reported as a skipped test.
- Register new test files in `TEST_FILES` inside `test/run_tests.py`.
- `test/common.vim` provides `WaitFor()` / `WaitForAssert()`.
- Use generic provider fakes (`TestFetchEvents` / `TestManageEvents`), not Outlook.
- **Never test interactive `input()` with queued `feedkeys(…, 't')`** — it hangs Vim and leaks
  keystrokes into the following test.
- `test/results.txt` and `test/vimrc_for_tests` are runner artifacts; never commit them.
- Run `git diff --check` before declaring work finished.

## Working style the maintainer expects

- **Fix causes, not symptoms.** Disabling a guard to make an error go away will be rejected.
- **Re-read files from disk before editing.** He edits code and docs between turns; do not
  assume your previous edit is still what is on disk.
- **"Do we still need X?" means "remove X"** — answer with a recommendation, not just a fact.
- **Ask before adding a config option.** New knobs should be opt-in and default to off.
- Layout and alignment complaints are literal — verify the exact rendered string, column by column.
- **Do not commit.** Leave changes in the working tree; the maintainer reviews and commits.

## Do not reintroduce

Popup calendar display mode, the custom `action` config key, separate `n`/`e` mappings, the room
picker / availability lookup, and the in-Vim Outlook composer were all built and then removed on
purpose. See the `[SUPERSEDED]` entries in `ARCHITECTURE.md`.
