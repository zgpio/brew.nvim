"=============================================================================
" FILE: util.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu at gmail.com>
" License: MIT license
"=============================================================================

lua require 'dein/util'
let s:is_windows = has('win32') || has('win64')

function! dein#util#_set_default(var, val, ...) abort
  if !exists(a:var) || type({a:var}) != type(a:val)
    let alternate_var = get(a:000, 0, '')

    let {a:var} = exists(alternate_var) ?
          \ {alternate_var} : a:val
  endif
endfunction

function! dein#util#_error(msg) abort
  for mes in s:msg2list(a:msg)
    echohl WarningMsg | echomsg '[dein] ' . mes | echohl None
  endfor
endfunction

function! dein#util#_is_fish() abort
  return dein#install#_is_async() && fnamemodify(&shell, ':t:r') ==# 'fish'
endfunction
function! dein#util#_is_powershell() abort
  return dein#install#_is_async() && fnamemodify(&shell, ':t:r') =~? 'powershell\|pwsh'
endfunction

function! dein#util#_get_type(name) abort
  return get(dein#parse#_get_types(), a:name, {})
endfunction

function! dein#util#_execute_hook(plugin, hook) abort
  try
    let g:dein#plugin = a:plugin

    if type(a:hook) == v:t_string
      call s:execute(a:hook)
    else
      call call(a:hook, [])
    endif
  catch
    call dein#util#_error(
          \ 'Error occurred while executing hook: ' .
          \ get(a:plugin, 'name', ''))
    call dein#util#_error(v:exception)
  endtry
endfunction

function! s:msg2list(expr) abort
  return type(a:expr) ==# v:t_list ? a:expr : split(a:expr, '\n')
endfunction

function! s:execute(expr) abort
  return execute(split(a:expr, '\n'))
endfunction
