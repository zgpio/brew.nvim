"=============================================================================
" FILE: parse.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu at gmail.com>
" License: MIT license
"=============================================================================

lua require 'dein/parse'
" Global options definition."
let g:dein#enable_name_conversion =
      \ get(g:, 'dein#enable_name_conversion', 0)


let s:git = dein#types#git#define()

function! dein#parse#_add(repo, options) abort
  let plugin = dein#parse#_dict(dein#parse#_init(a:repo, a:options))
  if (has_key(g:dein#_plugins, plugin.name)
        \ && g:dein#_plugins[plugin.name].sourced)
        \ || !get(plugin, 'if', 1)
    " Skip already loaded or not enabled plugin.
    return {}
  endif

  if plugin.lazy && plugin.rtp !=# ''
    let plugin = v:lua.parse_lazy(plugin)
  endif

  if has_key(g:dein#_plugins, plugin.name)
        \ && g:dein#_plugins[plugin.name].sourced
    let plugin.sourced = 1
  endif
  let g:dein#_plugins[plugin.name] = plugin
  if has_key(plugin, 'hook_add')
    call dein#util#_execute_hook(plugin, plugin.hook_add)
  endif
  if has_key(plugin, 'ftplugin')
    call s:merge_ftplugin(plugin.ftplugin)
  endif
  return plugin
endfunction
function! dein#parse#_init(repo, options) abort
  let repo = dein#util#_expand(a:repo)
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
function! dein#parse#_dict(plugin) abort
  let plugin = {
        \ 'rtp': '',
        \ 'sourced': 0,
        \ }
  call extend(plugin, a:plugin)

  if !has_key(plugin, 'name')
    let plugin.name = dein#parse#_name_conversion(plugin.repo)
  endif

  if !has_key(plugin, 'normalized_name')
    let plugin.normalized_name = substitute(
          \ fnamemodify(plugin.name, ':r'),
          \ '\c^n\?vim[_-]\|[_-]n\?vim$', '', 'g')
  endif

  if !has_key(a:plugin, 'name') && g:dein#enable_name_conversion
    " Use normalized name.
    let plugin.name = plugin.normalized_name
  endif

  lua require 'dein/util'
  if !has_key(plugin, 'path')
    let plugin.path = (plugin.repo =~# '^/\|^\a:[/\\]') ?
          \ plugin.repo : v:lua._get_base_path().'/repos/'.plugin.name
  endif

  let plugin.path = v:lua._chomp(dein#util#_expand(plugin.path))
  if get(plugin, 'rev', '') !=# ''
    " Add revision path
    let plugin.path .= '_' . substitute(
          \ plugin.rev, '[^[:alnum:].-]', '_', 'g')
  endif

  " Check relative path
  if (!has_key(a:plugin, 'rtp') || a:plugin.rtp !=# '')
        \ && plugin.rtp !~# '^\%([~/]\|\a\+:\)'
    let plugin.rtp = plugin.path.'/'.plugin.rtp
  endif
  if plugin.rtp[0:] ==# '~'
    let plugin.rtp = dein#util#_expand(plugin.rtp)
  endif
  lua require 'dein/util'
  let plugin.rtp = v:lua._chomp(plugin.rtp)
  if g:dein#_is_sudo && !get(plugin, 'trusted', 0)
    let plugin.rtp = ''
  endif

  if has_key(plugin, 'script_type')
    " Add script_type.
    let plugin.path .= '/' . plugin.script_type
  endif

  if has_key(plugin, 'depends') && type(plugin.depends) != v:t_list
    let plugin.depends = [plugin.depends]
  endif

  " Deprecated check.
  for key in filter(['directory', 'base'], 'has_key(plugin, v:val)')
    call dein#util#_error('plugin name = ' . plugin.name)
    call dein#util#_error(string(key) . ' is deprecated.')
  endfor

  if !has_key(plugin, 'lazy')
    let plugin.lazy =
          \    has_key(plugin, 'on_i')
          \ || has_key(plugin, 'on_idle')
          \ || has_key(plugin, 'on_ft')
          \ || has_key(plugin, 'on_cmd')
          \ || has_key(plugin, 'on_func')
          \ || has_key(plugin, 'on_map')
          \ || has_key(plugin, 'on_path')
          \ || has_key(plugin, 'on_if')
          \ || has_key(plugin, 'on_event')
          \ || has_key(plugin, 'on_source')
  endif

  if !has_key(a:plugin, 'merged')
    let plugin.merged = !plugin.lazy
          \ && plugin.normalized_name !=# 'dein'
          \ && !has_key(plugin, 'local')
          \ && !has_key(plugin, 'build')
          \ && !has_key(plugin, 'if')
          \ && stridx(plugin.rtp, v:lua._get_base_path()) == 0
  endif

  if has_key(plugin, 'if') && type(plugin.if) == v:t_string
    let plugin.if = eval(a:plugin.if)
  endif

  " Hooks
  for hook in filter([
        \ 'hook_add', 'hook_source',
        \ 'hook_post_source', 'hook_post_update',
        \ ], 'has_key(plugin, v:val) && type(plugin[v:val]) == v:t_string')
    let plugin[hook] = substitute(plugin[hook],
          \ '\n\s*\\\|\%(^\|\n\)\s*"[^\n]*', '', 'g')
  endfor

  return plugin
endfunction
function! dein#parse#_load_toml(filename, default) abort
  try
    let toml = dein#toml#parse_file(dein#util#_expand(a:filename))
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
    call v:lua.set_dein_hook_add(luaeval('dein_hook_add')."\n" . substitute(
          \ toml.hook_add, pattern, '', 'g'))
  endif
  if has_key(toml, 'ftplugin')
    call s:merge_ftplugin(toml.ftplugin)
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

  " Add to dein_vimrcs
  call v:lua.add_dein_vimrcs(dein#util#_expand(a:filename))
endfunction
function! dein#parse#_load_dict(dict, default) abort
  for [repo, options] in items(a:dict)
    call dein#add(repo, extend(copy(options), a:default, 'keep'))
  endfor
endfunction
function! dein#parse#_local(localdir, options, includes) abort
  let base = fnamemodify(dein#util#_expand(a:localdir), ':p')
  let directories = []
  for glob in a:includes
    let directories += map(filter(dein#util#_globlist(base . glob),
          \ 'isdirectory(v:val)'), "
          \ substitute(dein#util#_substitute_path(
          \   fnamemodify(v:val, ':p')), '/$', '', '')")
  endfor

  lua require 'dein/util'
  for dir in v:lua._uniq(directories)
    let options = extend({
          \ 'repo': dir, 'local': 1, 'path': dir,
          \ 'name': fnamemodify(dir, ':t')
          \ }, a:options)

    if has_key(g:dein#_plugins, options.name)
      call dein#config(options.name, options)
    else
      call dein#add(dir, options)
    endif
  endfor
endfunction
function! s:merge_ftplugin(ftplugin) abort
  let pattern = '\n\s*\\\|\%(^\|\n\)\s*"[^\n]*'
  for [ft, val] in items(a:ftplugin)
    if !has_key(g:dein#_ftplugin, ft)
      let g:dein#_ftplugin[ft] = val
    else
      let g:dein#_ftplugin[ft] .= "\n" . val
    endif
  endfor
  call map(g:dein#_ftplugin, "substitute(v:val, pattern, '', 'g')")
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

function! dein#parse#_name_conversion(path) abort
  return fnamemodify(get(split(a:path, ':'), -1, ''),
        \ ':s?/$??:t:s?\c\.git\s*$??')
endfunction
