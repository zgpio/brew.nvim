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

function! dein#util#_check_clean() abort
  let plugins_directories = map(values(v:lua.dein.get()), 'v:val.path')
  let path = v:lua._substitute_path(
        \ globpath(luaeval('dein._base_path'), 'repos/*/*/*'))
  return filter(split(path, "\n"),
        \ "isdirectory(v:val) && fnamemodify(v:val, ':t') !=# 'dein.vim'
        \  && index(plugins_directories, v:val) < 0")
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

function! dein#util#_sort_by(list, expr) abort
  let pairs = map(a:list, printf('[v:val, %s]', a:expr))
  return map(s:sort(pairs,
  \      'a:a[1] ==# a:b[1] ? 0 : a:a[1] ># a:b[1] ? 1 : -1'), 'v:val[0]')
endfunction

function! dein#util#_expand(path) abort
  let path = (a:path =~# '^\~') ? fnamemodify(a:path, ':p') :
        \ (a:path =~# '^\$\h\w*') ? substitute(a:path,
        \               '^\$\h\w*', '\=eval(submatch(0))', '') :
        \ a:path
  return (s:is_windows && path =~# '\\') ?
        \ v:lua._substitute_path(path) : path
endfunction

function! dein#util#_split(expr) abort
  return type(a:expr) ==# v:t_list ? copy(a:expr) :
        \ split(a:expr, '\r\?\n')
endfunction

function! s:msg2list(expr) abort
  return type(a:expr) ==# v:t_list ? a:expr : split(a:expr, '\n')
endfunction

function! s:sort(list, expr) abort
  if type(a:expr) == v:t_func
    return sort(a:list, a:expr)
  endif
  let s:expr = a:expr
  return sort(a:list, 's:_compare')
endfunction
function! s:_compare(a, b) abort
  return eval(s:expr)
endfunction

function! s:execute(expr) abort
  return execute(split(a:expr, '\n'))
endfunction
