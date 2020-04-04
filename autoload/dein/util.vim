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

function! dein#util#_get_vimrcs(vimrcs) abort
  return !empty(a:vimrcs) ?
        \ map(v:lua._convert2list(a:vimrcs), 'expand(v:val)') :
        \ [dein#util#_get_myvimrc()]
endfunction
function! dein#util#_get_myvimrc() abort
  let vimrc = $MYVIMRC !=# '' ? $MYVIMRC :
        \ matchstr(split(dein#util#_redir('scriptnames'), '\n')[0],
        \  '^\s*\d\+:\s\zs.*')
  return dein#util#_substitute_path(vimrc)
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
  let plugins_directories = map(values(dein#get()), 'v:val.path')
  let path = dein#util#_substitute_path(
        \ globpath(v:lua._get_base_path(), 'repos/*/*/*'))
  return filter(split(path, "\n"),
        \ "isdirectory(v:val) && fnamemodify(v:val, ':t') !=# 'dein.vim'
        \  && index(plugins_directories, v:val) < 0")
endfunction

function! dein#util#_get_type(name) abort
  return get(dein#parse#_get_types(), a:name, {})
endfunction

function! dein#util#_check_vimrcs() abort
  let time = getftime(v:lua._get_runtime_path())
  let ret = !empty(filter(map(copy(luaeval('dein_vimrcs')), 'getftime(expand(v:val))'),
        \ 'time < v:val'))
  if !ret
    return 0
  endif

  call dein#clear_state()

  if get(g:, 'dein#auto_recache', 0)
    silent execute 'source' dein#util#_get_myvimrc()

    if v:lua._get_merged_plugins() !=# v:lua._load_merged_plugins()
      lua require 'dein/util'
      call v:lua._notify('auto recached')
      call dein#recache_runtimepath()
    endif
  endif

  return ret
endfunction

function! dein#util#_clear_state() abort
  let base = get(g:, 'dein#cache_directory', luaeval('dein_base_path'))
  for cache in dein#util#_globlist(base.'/state_*.vim')
        \ + dein#util#_globlist(base.'/cache_*')
    call delete(cache)
  endfor
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
function! dein#util#_tsort(plugins) abort
  let sorted = []
  let mark = {}
  for target in a:plugins
    call s:tsort_impl(target, mark, sorted)
  endfor

  return sorted
endfunction

function! dein#util#_expand(path) abort
  let path = (a:path =~# '^\~') ? fnamemodify(a:path, ':p') :
        \ (a:path =~# '^\$\h\w*') ? substitute(a:path,
        \               '^\$\h\w*', '\=eval(submatch(0))', '') :
        \ a:path
  return (s:is_windows && path =~# '\\') ?
        \ dein#util#_substitute_path(path) : path
endfunction
function! dein#util#_substitute_path(path) abort
  return ((s:is_windows || has('win32unix')) && a:path =~# '\\') ?
        \ tr(a:path, '\', '/') : a:path
endfunction
function! dein#util#_globlist(path) abort
  return split(glob(a:path), '\n')
endfunction

function! dein#util#_split(expr) abort
  return type(a:expr) ==# v:t_list ? copy(a:expr) :
        \ split(a:expr, '\r\?\n')
endfunction

function! dein#util#_redir(cmd) abort
  if exists('*execute')
    return execute(a:cmd)
  endif
endfunction

function! dein#util#_get_plugins(plugins) abort
  return empty(a:plugins) ?
        \ values(dein#get()) :
        \ filter(map(v:lua._convert2list(a:plugins),
        \   'type(v:val) == v:t_dict ? v:val : dein#get(v:val)'),
        \   '!empty(v:val)')
endfunction

function! s:tsort_impl(target, mark, sorted) abort
  if empty(a:target) || has_key(a:mark, a:target.name)
    return
  endif

  let a:mark[a:target.name] = 1
  if has_key(a:target, 'depends')
    for depend in a:target.depends
      call s:tsort_impl(dein#get(depend), a:mark, a:sorted)
    endfor
  endif

  call add(a:sorted, a:target)
endfunction

function! s:msg2list(expr) abort
  return type(a:expr) ==# v:t_list ? a:expr : split(a:expr, '\n')
endfunction
function! s:skipempty(string) abort
  return filter(split(a:string, '\n'), "v:val !=# ''")
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
