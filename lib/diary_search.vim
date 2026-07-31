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
  try
    if engine ==# 'internal'
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

  silent cwindow
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
