"=============================================================================
" FILE: dein.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu at gmail.com>
" License: MIT license
"=============================================================================

lua require 'dein'
function! dein#load_state(path, ...) abort
  return v:lua.load_state(a:path, a:000)
endfunction

function! dein#begin(path, ...) abort
  lua require 'dein/util'
  return v:lua._begin(a:path, (empty(a:000) ? [] : a:1))
endfunction
function! dein#end() abort
  lua require 'dein/util'
  return v:lua._end()
endfunction
function! dein#add(repo, ...) abort
  lua require 'dein/util'
  return v:lua._add(a:repo, get(a:000, 0, {}))
endfunction
function! dein#local(dir, ...) abort
  return dein#parse#_local(a:dir, get(a:000, 0, {}), get(a:000, 1, ['*']))
endfunction
function! dein#get(...) abort
  return empty(a:000) ? copy(luaeval('dein_plugins')) : get(luaeval('dein_plugins'), a:1, {})
endfunction
function! dein#source(...) abort
  return v:lua._source(a:000)
endfunction
function! dein#check_install(...) abort
  lua require 'dein/util'
  return v:lua._check_install(get(a:000, 0, []))
endfunction
function! dein#check_clean() abort
  return dein#util#_check_clean()
endfunction
function! dein#install(...) abort
  return dein#install#_update(get(a:000, 0, []),
        \ 'install', dein#install#_is_async())
endfunction
function! dein#update(...) abort
  return dein#install#_update(get(a:000, 0, []),
        \ 'update', dein#install#_is_async())
endfunction
function! dein#check_update(...) abort
  return dein#install#_update(get(a:000, 0, []),
        \ 'check_update', dein#install#_is_async())
endfunction
function! dein#direct_install(repo, ...) abort
  call dein#install#_direct_install(a:repo, (a:0 ? a:1 : {}))
endfunction
function! dein#get_direct_plugins_path() abort
  return get(g:, 'dein#cache_directory', luaeval('dein_base_path'))
        \ .'/direct_install.vim'
endfunction
function! dein#reinstall(plugins) abort
  call dein#install#_reinstall(a:plugins)
endfunction
function! dein#rollback(date, ...) abort
  call dein#install#_rollback(a:date, (a:0 ? a:1 : []))
endfunction
function! dein#save_rollback(rollbackfile, ...) abort
  call dein#install#_save_rollback(a:rollbackfile, (a:0 ? a:1 : []))
endfunction
function! dein#load_rollback(rollbackfile, ...) abort
  call dein#install#_load_rollback(a:rollbackfile, (a:0 ? a:1 : []))
endfunction
function! dein#remote_plugins() abort
  return dein#install#_remote_plugins()
endfunction
function! dein#recache_runtimepath() abort
  call dein#install#_recache_runtimepath()
endfunction
function! dein#call_hook(hook_name, ...) abort
  lua require 'dein/util'
  return v:lua._call_hook(a:hook_name, a:000)
endfunction
function! dein#check_lazy_plugins() abort
  lua require 'dein/util'
  return v:lua._check_lazy_plugins()
endfunction
function! dein#load_toml(filename, ...) abort
  return dein#parse#_load_toml(a:filename, get(a:000, 0, {}))
endfunction
function! dein#load_dict(dict, ...) abort
  return dein#parse#_load_dict(a:dict, get(a:000, 0, {}))
endfunction
function! dein#get_log() abort
  return join(dein#install#_get_log(), "\n")
endfunction
function! dein#get_updates_log() abort
  return join(dein#install#_get_updates_log(), "\n")
endfunction
function! dein#get_progress() abort
  return dein#install#_get_progress()
endfunction
function! dein#each(command, ...) abort
  return dein#install#_each(a:command, (a:0 ? a:1 : []))
endfunction
function! dein#build(...) abort
  return dein#install#_build(a:0 ? a:1 : [])
endfunction
function! dein#save_state() abort
  lua require 'dein/util'
  return v:lua._save_state(has('vim_starting'))
endfunction
function! dein#clear_state() abort
  lua require 'dein/util'
  call v:lua._clear_state()
endfunction
