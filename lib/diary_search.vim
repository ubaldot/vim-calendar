vim9script

# Search diary markdown files and populate the quickfix list.
export def Run(diary_path: string, engine: string,
               keyword: string, year: string)
  if year !~# '^\d\{4}$'
    echoerr '[Calendar] Search year must contain exactly four digits.'
    return
  endif

  var files = globpath(expand(diary_path) .. '/' .. year,
    '**/*.md', false, true)
  if empty(files)
    setqflist([], 'r')
    echomsg $'[Calendar] No diary files found for {year}.'
    return
  endif

  var restore_winfixbuf = exists('+winfixbuf') && &l:winfixbuf
  if restore_winfixbuf
    setlocal nowinfixbuf
  endif

  var saved_key = &key
  try
    if engine ==# 'internal'
      # Check if the diary has a crypto key to avoid repeating inserting key
      # for each match found by vimgrep
      var active_diary = g:calendar_config.active_diary
      if has_key(g:calendar_config.diaries_dict[active_diary], 'secret')
          && g:calendar_config.diaries_dict[active_diary].secret
        &key = inputsecret($"Insert key for diary '{active_diary}': ")
      endif

      var pattern = escape(keyword, '/\')
      var file_args = files->mapnew((_, path) => fnameescape(path))->join(' ')
      execute $'vimgrep /{pattern}/j {file_args}'
    else
      var grep_args = files->mapnew((_, path) => shellescape(path))->join(' ')
      execute $'grep! {shellescape(keyword)} {grep_args}'
    endif
  finally
    if restore_winfixbuf
      setlocal winfixbuf
    endif
  endtry
  &key = saved_key

  silent cwindow
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
