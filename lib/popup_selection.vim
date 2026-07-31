vim9script

# Selection state and movement for calendar day cells in popup mode.

var popup_id = -1
var cells: list<dict<any>> = []
var selected_index = -1

def Select(index: number)
  if popup_id <= 0 || empty(cells)
    return
  endif
  selected_index = min([max([0, index]), len(cells) - 1])
  var cell = cells[selected_index]
  var position = [[cell.line, cell.colpos, 2]]
  win_execute(popup_id,
    "if getwinvar(win_getid(), 'cal_popup_day', 0) > 0"
    .. " | call matchdelete(getwinvar(win_getid(), 'cal_popup_day'))"
    .. " | call setwinvar(win_getid(), 'cal_popup_day', 0) | endif")
  win_execute(popup_id,
    $"call setwinvar(win_getid(), 'cal_popup_day', matchaddpos('CalPopupSelection', {string(position)}, 50))")
  win_execute(popup_id, $"call cursor({cell.line}, {cell.colpos})")
enddef

export def Initialize(winid: number, view_cells: list<dict<any>>,
                      year: number, month: number)
  popup_id = winid
  cells = view_cells
  selected_index = -1
  if empty(cells)
    return
  endif

  var target_index = 0
  if year == str2nr(strftime('%Y')) && month == str2nr(strftime('%m'))
    var today = str2nr(strftime('%d'))
    for i in range(0, len(cells) - 1)
      if cells[i].day == today
        target_index = i
        break
      endif
    endfor
  endif
  Select(target_index)
enddef

export def Move(key: string)
  if empty(cells) || selected_index < 0
    return
  endif
  var current = cells[selected_index]
  var next_index = selected_index

  if key ==# 'h'
    next_index = max([0, selected_index - 1])
  elseif key ==# 'l'
    next_index = min([len(cells) - 1, selected_index + 1])
  elseif key ==# 'j' || key ==# 'k'
    var target_row = key ==# 'j' ? current.row + 1 : current.row - 1
    var best_index = -1
    var best_distance = 999
    for i in range(0, len(cells) - 1)
      var candidate = cells[i]
      if candidate.row != target_row
        continue
      endif
      var distance = abs(candidate.col - current.col)
      if best_index < 0 || distance < best_distance
        best_index = i
        best_distance = distance
      endif
    endfor
    if best_index >= 0
      next_index = best_index
    endif
  else
    return
  endif

  Select(next_index)
enddef

export def SelectedDay(): number
  return selected_index >= 0 && selected_index < len(cells)
    ? cells[selected_index].day
    : -1
enddef

export def Reset()
  popup_id = -1
  cells = []
  selected_index = -1
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
