"=============================================================================
" FILE: autoload.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu at gmail.com>
" License: MIT license
"=============================================================================
lua require 'dein/autoload'

function! dein#autoload#_on_default_event(event) abort
  let lazy_plugins = dein#util#_get_lazy_plugins()
  let plugins = []

  let path = expand('<afile>')
  " For ":edit ~".
  if fnamemodify(path, ':t') ==# '~'
    let path = '~'
  endif
  let path = dein#util#_expand(path)

  for filetype in split(&l:filetype, '\.')
    let plugins += filter(copy(lazy_plugins),
          \ "index(get(v:val, 'on_ft', []), filetype) >= 0")
  endfor

  let plugins += filter(copy(lazy_plugins),
        \ "!empty(filter(copy(get(v:val, 'on_path', [])),
        \                'path =~? v:val'))")
  let plugins += filter(copy(lazy_plugins),
        \ "!has_key(v:val, 'on_event')
        \  && has_key(v:val, 'on_if') && eval(v:val.on_if)")

  call v:lua.source_events(a:event, plugins)
endfunction
function! dein#autoload#_on_event(event, plugins) abort
  let lazy_plugins = filter(dein#util#_get_plugins(a:plugins),
        \ '!v:val.sourced')
  if empty(lazy_plugins)
    execute 'autocmd! dein-events' a:event
    return
  endif

  let plugins = filter(copy(lazy_plugins),
        \ "!has_key(v:val, 'on_if') || eval(v:val.on_if)")
  call v:lua.source_events(a:event, plugins)
endfunction

function! dein#autoload#_on_func(name) abort
  let function_prefix = substitute(a:name, '[^#]*$', '', '')
  if function_prefix =~# '^dein#'
        \ || function_prefix =~# '^vital#'
        \ || has('vim_starting')
    return
  endif

  call v:lua._source(filter(dein#util#_get_lazy_plugins(),
        \  "stridx(function_prefix, v:val.normalized_name.'#') == 0
        \   || (index(get(v:val, 'on_func', []), a:name) >= 0)"))
endfunction

function! dein#autoload#_on_pre_cmd(name) abort
  call v:lua._source(
        \ filter(dein#util#_get_lazy_plugins(),
        \ "index(map(copy(get(v:val, 'on_cmd', [])),
        \            'tolower(v:val)'), a:name) >= 0
        \  || stridx(tolower(a:name),
        \            substitute(tolower(v:val.normalized_name),
        \                       '[_-]', '', 'g')) == 0"))
endfunction

function! dein#autoload#_on_cmd(command, name, args, bang, line1, line2) abort
  call dein#source(a:name)

  if exists(':' . a:command) != 2
    call dein#util#_error(printf('command %s is not found.', a:command))
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
  let command = matchstr(a:cmdline, '\h\w*')
  if exists(':'.command) == 2
    " Remove the dummy command.
    silent! execute 'delcommand' command
  endif

  " Load plugins
  call dein#autoload#_on_pre_cmd(tolower(command))

  if exists(':'.command) == 2
    " Print the candidates
    call feedkeys("\<C-d>", 'n')
  endif

  return [a:arglead]
endfunction
