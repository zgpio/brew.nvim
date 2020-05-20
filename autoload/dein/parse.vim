"=============================================================================
" FILE: parse.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu at gmail.com>
" License: MIT license
"=============================================================================

lua require 'dein/parse'
lua require 'dein/util'
" Global options definition."
let g:dein#enable_name_conversion =
      \ get(g:, 'dein#enable_name_conversion', 0)


let s:git = dein#types#git#define()

function! dein#parse#_init(repo, options) abort
  let repo = v:lua._expand(a:repo)
  let plugin = has_key(a:options, 'type') ?
        \ dein#util#_get_type(a:options.type).init(repo, a:options) :
        \ s:git.init(repo, a:options)
  if empty(plugin)
    let plugin = s:check_type(repo, a:options)
  endif
  call extend(plugin, a:options)
  let plugin.repo = repo
  if !empty(a:options)
    let plugin.orig_opts = deepcopy(a:options)
  endif
  return plugin
endfunction
function! dein#parse#_load_toml(filename, default) abort
  try
    let toml = dein#toml#parse_file(v:lua._expand(a:filename))
  catch /Text.TOML:/
    call dein#util#_error('Invalid toml format: ' . a:filename)
    call dein#util#_error(v:exception)
    return 1
  endtry
  if type(toml) != v:t_dict
    call dein#util#_error('Invalid toml file: ' . a:filename)
    return 1
  endif

  " Parse.
  if has_key(toml, 'hook_add')
    let pattern = '\n\s*\\\|\%(^\|\n\)\s*"[^\n]*'
    call v:lua.set_dein_hook_add(luaeval('dein._hook_add')."\n" . substitute(
          \ toml.hook_add, pattern, '', 'g'))
  endif
  if has_key(toml, 'ftplugin')
    call v:lua.merge_ftplugin(toml.ftplugin)
  endif

  if has_key(toml, 'plugins')
    for plugin in toml.plugins
      if !has_key(plugin, 'repo')
        call dein#util#_error('No repository plugin data: ' . a:filename)
        return 1
      endif

      let options = extend(plugin, a:default, 'keep')
      call dein#add(plugin.repo, options)
    endfor
  endif

  " Add to dein._vimrcs
  call v:lua.add_dein_vimrcs(v:lua._expand(a:filename))
endfunction
function! dein#parse#_load_dict(dict, default) abort
  for [repo, options] in items(a:dict)
    call dein#add(repo, extend(copy(options), a:default, 'keep'))
  endfor
endfunction
function! dein#parse#_local(localdir, options, includes) abort
  lua require 'dein/util'
  let base = fnamemodify(v:lua._expand(a:localdir), ':p')
  let directories = []
  for glob in a:includes
    let directories += map(filter(v:lua._globlist(base . glob),
          \ 'isdirectory(v:val)'), "
          \ substitute(v:lua._substitute_path(
          \   fnamemodify(v:val, ':p')), '/$', '', '')")
  endfor

  lua require 'dein/util'
  for dir in v:lua._uniq(directories)
    let options = extend({
          \ 'repo': dir, 'local': 1, 'path': dir,
          \ 'name': fnamemodify(dir, ':t')
          \ }, a:options)

    if has_key(luaeval('dein._plugins'), options.name)
      call dein#config(options.name, options)
    else
      call dein#add(dir, options)
    endif
  endfor
endfunction

function! dein#parse#_get_types() abort
  if !exists('s:types')
    " Load types.
    let s:types = {}
    for type in filter(map(split(globpath(&runtimepath,
          \ 'autoload/dein/types/*.vim', 1), '\n'),
          \ "dein#types#{fnamemodify(v:val, ':t:r')}#define()"),
          \ '!empty(v:val)')
      let s:types[type.name] = type
    endfor
  endif
  return s:types
endfunction
function! s:check_type(repo, options) abort
  let plugin = {}
  for type in values(dein#parse#_get_types())
    let plugin = type.init(a:repo, a:options)
    if !empty(plugin)
      break
    endif
  endfor

  if empty(plugin)
    let plugin.type = 'none'
    let plugin.local = 1
    let plugin.path = isdirectory(a:repo) ? a:repo : ''
  endif

  return plugin
endfunction
