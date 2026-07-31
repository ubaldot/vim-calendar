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

export def Show(calendar_is_popup: bool)
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
  if calendar_is_popup
    extend(options, {line: &lines, col: &columns, pos: 'botright'})
  endif
  popup_id = popup_create(lines, options)
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
