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

function! dein#util#_get_base_path() abort
  return g:dein#_base_path
endfunction
function! dein#util#_get_vimrcs(vimrcs) abort
  return !empty(a:vimrcs) ?
        \ map(dein#util#_convert2list(a:vimrcs), 'expand(v:val)') :
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

function! dein#util#_uniq(list) abort
  let list = copy(a:list)
  let i = 0
  let seen = {}
  while i < len(list)
    let key = list[i]
    if key !=# '' && has_key(seen, key)
      call remove(list, i)
    else
      if key !=# ''
        let seen[key] = 1
      endif
      let i += 1
    endif
  endwhile
  return list
endfunction

function! dein#util#_is_fish() abort
  return dein#install#_is_async() && fnamemodify(&shell, ':t:r') ==# 'fish'
endfunction
function! dein#util#_is_powershell() abort
  return dein#install#_is_async() && fnamemodify(&shell, ':t:r') =~? 'powershell\|pwsh'
endfunction

function! dein#util#_check_lazy_plugins() abort
  return map(filter(dein#util#_get_lazy_plugins(),
        \   "isdirectory(v:val.rtp)
        \    && !get(v:val, 'local', 0)
        \    && get(v:val, 'hook_source', '') ==# ''
        \    && get(v:val, 'hook_add', '') ==# ''
        \    && !isdirectory(v:val.rtp . '/plugin')
        \    && !isdirectory(v:val.rtp . '/after/plugin')"),
        \   'v:val.name')
endfunction
function! dein#util#_check_clean() abort
  let plugins_directories = map(values(dein#get()), 'v:val.path')
  let path = dein#util#_substitute_path(
        \ globpath(dein#util#_get_base_path(), 'repos/*/*/*'))
  return filter(split(path, "\n"),
        \ "isdirectory(v:val) && fnamemodify(v:val, ':t') !=# 'dein.vim'
        \  && index(plugins_directories, v:val) < 0")
endfunction

function! dein#util#_writefile(path, list) abort
  if g:dein#_is_sudo || !filewritable(v:lua._get_cache_path())
    return 1
  endif

  let path = v:lua._get_cache_path() . '/' . a:path
  let dir = fnamemodify(path, ':h')
  if !isdirectory(dir)
    call mkdir(dir, 'p')
  endif

  return writefile(a:list, path)
endfunction

function! dein#util#_get_type(name) abort
  return get(dein#parse#_get_types(), a:name, {})
endfunction

function! dein#util#_check_vimrcs() abort
  let time = getftime(v:lua._get_runtime_path())
  let ret = !empty(filter(map(copy(g:dein#_vimrcs), 'getftime(expand(v:val))'),
        \ 'time < v:val'))
  if !ret
    return 0
  endif

  call dein#clear_state()

  if get(g:, 'dein#auto_recache', 0)
    silent execute 'source' dein#util#_get_myvimrc()

    if dein#util#_get_merged_plugins() !=# dein#util#_load_merged_plugins()
      lua require 'dein/util'
      call v:lua._notify('auto recached')
      call dein#recache_runtimepath()
    endif
  endif

  return ret
endfunction
function! dein#util#_load_merged_plugins() abort
  let path = v:lua._get_cache_path() . '/merged'
  if !filereadable(path)
    return []
  endif
  let merged = readfile(path)
  if len(merged) != g:dein#_merged_length
    return []
  endif
  sandbox return merged[: g:dein#_merged_length - 2] + eval(merged[-1])
endfunction
function! dein#util#_save_merged_plugins() abort
  let merged = dein#util#_get_merged_plugins()
  call writefile(merged[: g:dein#_merged_length - 2] +
        \ [string(merged[g:dein#_merged_length - 1 :])],
        \ v:lua._get_cache_path() . '/merged')
endfunction
function! dein#util#_get_merged_plugins() abort
  let ftplugin_len = 0
  for ftplugin in values(g:dein#_ftplugin)
    let ftplugin_len += len(ftplugin)
  endfor
  return [g:dein#_merged_format, string(ftplugin_len)] +
         \ sort(map(values(g:dein#_plugins), g:dein#_merged_format))
endfunction

function! dein#util#_save_state(is_starting) abort
  if g:dein#_block_level != 0
    call dein#util#_error('Invalid dein#save_state() usage.')
    return 1
  endif

  if v:lua._get_cache_path() ==# '' || !a:is_starting
    " Ignore
    return 1
  endif

  let g:dein#_vimrcs = dein#util#_uniq(g:dein#_vimrcs)
  lua require 'dein/util'
  let &runtimepath = v:lua._join_rtp(dein#util#_uniq(
        \ v:lua._split_rtp(&runtimepath)), &runtimepath, '')

  call v:lua._save_cache(g:dein#_vimrcs, 1, a:is_starting)

  " Version check

  let lines = [
        \ 'lua require "dein/autoload"',
        \ 'if g:dein#_cache_version !=# ' . g:dein#_cache_version . ' || ' .
        \ 'g:dein#_init_runtimepath !=# ' . string(g:dein#_init_runtimepath) .
        \      ' | throw ''Cache loading error'' | endif',
        \ 'let [plugins, ftplugin] = dein#load_cache_raw('.
        \      string(g:dein#_vimrcs) .')',
        \ "if empty(plugins) | throw 'Cache loading error' | endif",
        \ 'let g:dein#_plugins = plugins',
        \ 'let g:dein#_ftplugin = ftplugin',
        \ 'let g:dein#_base_path = ' . string(g:dein#_base_path),
        \ 'let g:dein#_runtime_path = ' . string(g:dein#_runtime_path),
        \ 'let g:dein#_cache_path = ' . string(g:dein#_cache_path),
        \ 'let &runtimepath = ' . string(&runtimepath),
        \ ]

  if g:dein#_off1 !=# ''
    call add(lines, g:dein#_off1)
  endif
  if g:dein#_off2 !=# ''
    call add(lines, g:dein#_off2)
  endif

  " Add dummy mappings/commands
  for plugin in dein#util#_get_lazy_plugins()
    for command in get(plugin, 'dummy_commands', [])
      call add(lines, 'silent! ' . command[1])
    endfor
    for mapping in get(plugin, 'dummy_mappings', [])
      call add(lines, 'silent! ' . mapping[2])
    endfor
  endfor

  " Add hooks
  if !empty(g:dein#_hook_add)
    let lines += s:skipempty(g:dein#_hook_add)
  endif
  for plugin in dein#util#_tsort(values(dein#get()))
    if has_key(plugin, 'hook_add') && type(plugin.hook_add) == v:t_string
      let lines += s:skipempty(plugin.hook_add)
    endif
  endfor

  " Add events
  for [event, plugins] in filter(items(g:dein#_event_plugins),
        \ "exists('##' . v:val[0])")
    call add(lines, printf('autocmd dein-events %s call '
          \. 'dein#autoload#_on_event("%s", %s)',
          \ (exists('##' . event) ? event . ' *' : 'User ' . event),
          \ event, string(plugins)))
  endfor

  call writefile(lines, get(g:, 'dein#cache_directory', g:dein#_base_path)
        \ .'/state_' . g:dein#_progname . '.vim')
endfunction
function! dein#util#_clear_state() abort
  let base = get(g:, 'dein#cache_directory', g:dein#_base_path)
  for cache in dein#util#_globlist(base.'/state_*.vim')
        \ + dein#util#_globlist(base.'/cache_*')
    call delete(cache)
  endfor
endfunction

function! dein#util#_config(arg, dict) abort
  let name = type(a:arg) == v:t_dict ?
        \   g:dein#name : a:arg
  let dict = type(a:arg) == v:t_dict ?
        \   a:arg : a:dict
  if !has_key(g:dein#_plugins, name)
        \ || g:dein#_plugins[name].sourced
    return {}
  endif

  let plugin = g:dein#_plugins[name]
  let options = extend({'repo': plugin.repo}, dict)
  if has_key(plugin, 'orig_opts')
    call extend(options, copy(plugin.orig_opts), 'keep')
  endif
  return dein#parse#_add(options.repo, options)
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
function! dein#util#_set_hook(plugins, hook_name, hook) abort
  let names = empty(a:plugins) ? keys(dein#get()) :
        \ dein#util#_convert2list(a:plugins)
  for name in names
    if !has_key(g:dein#_plugins, name)
      call dein#util#_error(name . ' is not found.')
      return 1
    endif
    let plugin = g:dein#_plugins[name]
    let plugin[a:hook_name] =
          \ type(a:hook) != v:t_string ? a:hook :
          \   substitute(a:hook, '\n\s*\\\|\%(^\|\n\)\s*"[^\n]*', '', 'g')
    if a:hook_name ==# 'hook_add'
      call dein#util#_execute_hook(plugin, plugin[a:hook_name])
    endif
  endfor
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

function! dein#util#_add_after(rtps, path) abort
  let idx = index(a:rtps, $VIMRUNTIME)
  call insert(a:rtps, a:path, (idx <= 0 ? -1 : idx + 1))
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

function! dein#util#_convert2list(expr) abort
  return type(a:expr) ==# v:t_list ? copy(a:expr) :
        \ type(a:expr) ==# v:t_string ?
        \   (a:expr ==# '' ? [] : split(a:expr, '\r\?\n', 1))
        \ : [a:expr]
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

function! dein#util#_get_lazy_plugins() abort
  return filter(values(g:dein#_plugins),
        \ "!v:val.sourced && v:val.rtp !=# ''")
endfunction

function! dein#util#_get_plugins(plugins) abort
  return empty(a:plugins) ?
        \ values(dein#get()) :
        \ filter(map(dein#util#_convert2list(a:plugins),
        \   'type(v:val) == v:t_dict ? v:val : dein#get(v:val)'),
        \   '!empty(v:val)')
endfunction

function! dein#util#_disable(names) abort
  for plugin in map(filter(dein#util#_convert2list(a:names),
        \ 'has_key(g:dein#_plugins, v:val)
        \  && !g:dein#_plugins[v:val].sourced'), 'g:dein#_plugins[v:val]')
    if has_key(plugin, 'dummy_commands')
      for command in plugin.dummy_commands
        silent! execute 'delcommand' command[0]
      endfor
      let plugin.dummy_commands = []
    endif

    if has_key(plugin, 'dummy_mappings')
      for map in plugin.dummy_mappings
        silent! execute map[0].'unmap' map[1]
      endfor
      let plugin.dummy_mappings = []
    endif

    call remove(g:dein#_plugins, plugin.name)
  endfor
endfunction

function! dein#util#_download(uri, outpath) abort
  if !exists('g:dein#download_command')
    let g:dein#download_command =
          \ executable('curl') ?
          \   'curl --silent --location --output' :
          \ executable('wget') ?
          \   'wget -q -O' : ''
  endif
  if g:dein#download_command !=# ''
    return printf('%s "%s" "%s"',
          \ g:dein#download_command, a:outpath, a:uri)
  elseif v:lua._is_windows()
    " Use powershell
    " Todo: Proxy support
    let pscmd = printf("(New-Object Net.WebClient).DownloadFile('%s', '%s')",
          \ a:uri, a:outpath)
    return printf('powershell -Command "%s"', pscmd)
  else
    return 'E: curl or wget command is not available!'
  endif
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
