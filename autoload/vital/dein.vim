let s:plugin_name = expand('<sfile>:t:r')
let s:vital_base_dir = expand('<sfile>:h')
let s:project_root = expand('<sfile>:h:h:h')
let s:is_vital_vim = s:plugin_name is# 'vital'

let s:loaded = {}
let s:cache_sid = {}

function! vital#dein#new() abort
  return s:new('dein')
endfunction

function! vital#dein#import(...) abort
  if !exists('s:V')
    let s:V = s:new('dein')
  endif
  return call(s:V.import, a:000, s:V)
endfunction

let s:Vital = {}

function! s:new(plugin_name) abort
  let base = deepcopy(s:Vital)
  let base._plugin_name = a:plugin_name
  return base
endfunction

function! s:vital_files() abort
  if !exists('s:vital_files')
    let s:vital_files = map(
    \   s:is_vital_vim ? s:_global_vital_files() : s:_self_vital_files(),
    \   'fnamemodify(v:val, ":p:gs?[\\\\/]?/?")')
  endif
  return copy(s:vital_files)
endfunction
let s:Vital.vital_files = function('s:vital_files')

function! s:import(name, ...) abort dict
  let target = {}
  let functions = []
  for a in a:000
    if type(a) == type({})
      let target = a
    elseif type(a) == type([])
      let functions = a
    endif
    unlet a
  endfor
  let module = self._import(a:name)
  if empty(functions)
    call extend(target, module, 'keep')
  else
    for f in functions
      if has_key(module, f) && !has_key(target, f)
        let target[f] = module[f]
      endif
    endfor
  endif
  return target
endfunction
let s:Vital.import = function('s:import')

function! s:plugin_name() abort dict
  return self._plugin_name
endfunction
let s:Vital.plugin_name = function('s:plugin_name')

function! s:_self_vital_files() abort
  let builtin = printf('%s/__%s__/', s:vital_base_dir, 'dein')
  let installed = printf('%s/_%s/', s:vital_base_dir, 'dein')
  let base = builtin . ',' . installed
  return split(globpath(base, '**/*.vim', 1), "\n")
endfunction

function! s:_global_vital_files() abort
  let pattern = 'autoload/vital/__*__/**/*.vim'
  return split(globpath(&runtimepath, pattern, 1), "\n")
endfunction

function! s:_extract_files(pattern, files) abort
  let tr = {'.': '/', '*': '[^/]*', '**': '.*'}
  let target = substitute(a:pattern, '\.\|\*\*\?', '\=tr[submatch(0)]', 'g')
  let regexp = printf('autoload/vital/[^/]\+/%s.vim$', target)
  return filter(a:files, 'v:val =~# regexp')
endfunction

" @param {string} name e.g. Data.List
function! s:_import(name) abort dict
  if has_key(s:loaded, a:name)
    return copy(s:loaded[a:name])
  endif
  let module = self._get_module(a:name)
  if has_key(module, '_vital_created')
    call module._vital_created(module)
  endif
  let export_module = filter(copy(module), 'v:key =~# "^\\a"')
  " Cache module before calling module.vital_loaded() to avoid cyclic
  " dependences but remove the cache if module._vital_loaded() fails.
  " let s:loaded[a:name] = export_module
  let s:loaded[a:name] = export_module
  if has_key(module, '_vital_loaded')
    try
      call module._vital_loaded(vital#dein#new())
    catch
      unlet s:loaded[a:name]
      throw 'vital: fail to call ._vital_loaded(): ' . v:exception
    endtry
  endif
  return copy(s:loaded[a:name])
endfunction
let s:Vital._import = function('s:_import')

" s:_get_module() returns module object wihch has all script local functions.
function! s:_get_module(name) abort dict
  let funcname = s:_import_func_name(self.plugin_name(), a:name)
  try
    return call(funcname, [])
  catch /^Vim\%((\a\+)\)\?:E117/
    return s:_get_builtin_module(a:name)
  endtry
endfunction

function! s:_get_builtin_module(name) abort
 return s:sid2sfuncs(s:_module_sid(a:name))
endfunction

if s:is_vital_vim
  " For vital.vim, we can use s:_get_builtin_module directly
  let s:Vital._get_module = function('s:_get_builtin_module')
else
  let s:Vital._get_module = function('s:_get_module')
endif

function! s:_import_func_name(plugin_name, module_name) abort
  return printf('vital#_%s#%s#import', a:plugin_name, s:_dot_to_sharp(a:module_name))
endfunction

function! s:_module_sid(name) abort
  let path = s:_module_path(a:name)
  if !filereadable(path)
    throw 'vital: module not found: ' . a:name
  endif
  let vital_dir = s:is_vital_vim ? '__\w\+__' : printf('_\{1,2}%s\%%(__\)\?', 'dein')
  let base = join([vital_dir, ''], '[/\\]\+')
  let p = base . substitute('' . a:name, '\.', '[/\\\\]\\+', 'g')
  let sid = s:_sid(path, p)
  if !sid
    call s:_source(path)
    let sid = s:_sid(path, p)
    if !sid
      throw printf('vital: cannot get <SID> from path: %s', path)
    endif
  endif
  return sid
endfunction

function! s:_module_path(name) abort
  return get(s:_extract_files(a:name, s:vital_files()), 0, '')
endfunction

function! s:_dot_to_sharp(name) abort
  return substitute(a:name, '\.', '#', 'g')
endfunction

function! s:_source(path) abort
  execute 'source' fnameescape(a:path)
endfunction

" @vimlint(EVL102, 1, l:_)
" @vimlint(EVL102, 1, l:__)
function! s:_sid(path, filter_pattern) abort
  let unified_path = s:_unify_path(a:path)
  if has_key(s:cache_sid, unified_path)
    return s:cache_sid[unified_path]
  endif
  for line in filter(split(execute(':scriptnames'), "\n"), 'v:val =~# a:filter_pattern')
    let [_, sid, path; __] = matchlist(line, '^\s*\(\d\+\):\s\+\(.\+\)\s*$')
    if s:_unify_path(path) is# unified_path
      let s:cache_sid[unified_path] = sid
      return s:cache_sid[unified_path]
    endif
  endfor
  return 0
endfunction

if filereadable(expand('<sfile>:r') . '.VIM') " is case-insensitive or not
  let s:_unify_path_cache = {}
  " resolve() is slow, so we cache results.
  " Note: On windows, vim can't expand path names from 8.3 formats.
  " So if getting full path via <sfile> and $HOME was set as 8.3 format,
  " vital load duplicated scripts. Below's :~ avoid this issue.
  function! s:_unify_path(path) abort
    if has_key(s:_unify_path_cache, a:path)
      return s:_unify_path_cache[a:path]
    endif
    let value = tolower(fnamemodify(resolve(fnamemodify(
    \                   a:path, ':p')), ':~:gs?[\\/]?/?'))
    let s:_unify_path_cache[a:path] = value
    return value
  endfunction
else
  function! s:_unify_path(path) abort
    return resolve(fnamemodify(a:path, ':p:gs?[\\/]?/?'))
  endfunction
endif

" copied and modified from Vim.ScriptLocal
let s:SNR = join(map(range(len("\<SNR>")), '"[\\x" . printf("%0x", char2nr("\<SNR>"[v:val])) . "]"'), '')
function! s:sid2sfuncs(sid) abort
  let fs = split(execute(printf(':function /^%s%s_', s:SNR, a:sid)), "\n")
  let r = {}
  let pattern = printf('\m^function\s<SNR>%d_\zs\w\{-}\ze(', a:sid)
  for fname in map(fs, 'matchstr(v:val, pattern)')
    let r[fname] = function(s:_sfuncname(a:sid, fname))
  endfor
  return r
endfunction

"" Return funcname of script local functions with SID
function! s:_sfuncname(sid, funcname) abort
  return printf('<SNR>%s_%s', a:sid, a:funcname)
endfunction
