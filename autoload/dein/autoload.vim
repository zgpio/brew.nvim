"=============================================================================
" FILE: autoload.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu at gmail.com>
" License: MIT license
"=============================================================================
lua require 'dein/autoload'

function! dein#autoload#_on_cmd(command, name, args, bang, line1, line2) abort
  call dein#source(a:name)

  if exists(':' . a:command) != 2
    call v:lua._error(printf('command %s is not found.', a:command))
    return
  endif

  let range = (a:line1 == a:line2) ? '' :
        \ (a:line1 == line("'<") && a:line2 == line("'>")) ?
        \ "'<,'>" : a:line1.','.a:line2

  try
    execute range.a:command.a:bang a:args
  catch /^Vim\%((\a\+)\)\=:E481/
    " E481: No range allowed
    execute a:command.a:bang a:args
  endtry
endfunction

function! dein#autoload#_dummy_complete(arglead, cmdline, cursorpos) abort
  return v:lua._dummy_complete(a:arglead, a:cmdline, a:cursorpos)
endfunction
