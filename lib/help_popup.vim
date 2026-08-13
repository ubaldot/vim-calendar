vim9script

var popup_id = -1

def Filter(id: number, key: string): bool
  if key ==# 'q' || key ==# "\<Esc>"
    popup_close(id)
    popup_id = -1
    return true
  endif
  return false
enddef

export def Show()
  var lines = [
    'Calendar key bindings',
    '',
    'h/j/k/l  move cursor',
    '<Up>  previous month',
    '<Down>  next month',
    '<Left>  previous year',
    '<Right>  next year',
    '<CR>  open/switch on cursor',
    't  go to today',
    '<Tab> / <S-Tab>  next/prev diary',
    '',
    'q or <Esc>  close',
  ]
  if popup_id > 0
    popup_close(popup_id)
  endif

  var options = {
    title: ' Calendar Help ',
    borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    border: [1, 1, 1, 1],
    filter: Filter,
    mapping: 0,
  }
  popup_id = popup_create(lines, options)
enddef

export def ShowWeek()
  var lines = [
    'Week view key bindings',
    '',
    'K  preview appointment',
    '<CR>  open appointment details',
    'm  create event at cursor slot, or edit event under cursor',
    'd  delete event (provider may decline/cancel it)',
    'a  accept invitation',
    'v  respond tentatively',
    '<Tab> / <S-Tab>  next/prev diary',
    '<C-Left> / <C-Right>  previous/next week',
    't  go to current week',
    '<F5>  refresh appointments',
    'q or <Esc>  close appointment details',
    '',
    'Events are cached: a week is fetched from the provider the',
    'first time it is shown.  <F5> discards the cache.',
    '',
    'Layout',
    'One line per half hour: an event spans one line per half hour',
    'it lasts, so a 1.5-hour event covers three lines.',
    'Conflicting events share the day column side by side,',
    'separated by ┆, and stay aligned with the time column.',
    'Only the lines the conflict covers are split: an event',
    'that conflicts with nothing keeps the full width.',
    'A title that does not fit ends with ...; the organizer',
    'is shown in brackets on the last line of the event.',
  ]
  if popup_id > 0
    popup_close(popup_id)
  endif
  popup_id = popup_create(lines, {
    title: ' Week View Help ',
    borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    border: [1, 1, 1, 1],
    filter: Filter,
    mapping: 0,
  })
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
