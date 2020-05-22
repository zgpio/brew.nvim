"=============================================================================
" FILE: install.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu at gmail.com>
" License: MIT license
"=============================================================================

lua require 'dein/util'
lua require 'dein/install'
" Variables
let g:__global_context = {}
let g:__log = []
let g:__updates_log = []
let g:__progress = ''

" Global options definition.
let g:dein#install_max_processes =
      \ get(g:, 'dein#install_max_processes', 8)
let g:dein#install_progress_type =
      \ get(g:, 'dein#install_progress_type', 'echo')
let g:dein#install_message_type =
      \ get(g:, 'dein#install_message_type', 'echo')
let g:dein#install_process_timeout =
      \ get(g:, 'dein#install_process_timeout', 120)
let g:dein#install_log_filename =
      \ get(g:, 'dein#install_log_filename', '')

function! s:get_job() abort
  if !exists('s:Job')
    let s:Job = dein#job#import()
  endif
  " call luaeval('dein_log:write(vim.inspect(_A), "\n")', [string(s:Job)])
  " lua dein_log:flush()
  return s:Job
endfunction

function! dein#install#_update(plugins, update_type, async) abort
  if luaeval('dein._is_sudo')
    call s:error('update/install is disabled in sudo session.')
    return
  endif

  let plugins = v:lua._get_plugins(a:plugins)

  if a:update_type ==# 'install'
    let plugins = filter(plugins, '!isdirectory(v:val.path)')
  elseif a:update_type ==# 'check_update'
    let plugins = filter(plugins, 'isdirectory(v:val.path)')
  endif

  if a:async && !empty(g:__global_context) &&
        \ confirm('The installation has not finished. Cancel now?',
        \         "yes\nNo", 2) != 1
    return
  endif

  " Set context.
  let context = s:init_context(plugins, a:update_type, a:async)

  call s:init_variables(context)

  if empty(plugins)
    if a:update_type !=# 'check_update'
      call s:notify('Target plugins are not found.')
      call s:notify('You may have used the wrong plugin name,'.
            \ ' or all of the plugins are already installed.')
    endif
    let g:__global_context = {}
    return
  endif

  call s:start()

  if !a:async || has('vim_starting')
    return s:update_loop(context)
  endif

  augroup dein-install
    autocmd!
  augroup END

  if exists('s:timer')
    call timer_stop(s:timer)
    unlet s:timer
  endif

  let s:timer = timer_start(1000,
        \ {-> dein#install#_polling()}, {'repeat': -1})
endfunction
function! s:update_loop(context) abort
  let errored = 0
  try
    if has('vim_starting')
      while !empty(g:__global_context)
        let errored = s:install_async(a:context)
        sleep 50ms
        redraw
      endwhile
    else
      let errored = s:install_blocking(a:context)
    endif
  catch
    call s:error(v:exception)
    call s:error(v:throwpoint)
    return 1
  endtry

  return errored
endfunction

function! dein#install#_reinstall(plugins) abort
  let plugins = v:lua._get_plugins(a:plugins)

  for plugin in plugins
    " Remove the plugin
    if plugin.type ==# 'none'
          \ || get(plugin, 'local', 0)
          \ || (plugin.sourced &&
          \     index(['dein'], plugin.normalized_name) >= 0)
      call dein#util#_error(
            \ printf('|%s| Cannot reinstall the plugin!', plugin.name))
      continue
    endif

    " Reinstall.
    call s:print_progress_message(printf('|%s| Reinstalling...', plugin.name))

    if isdirectory(plugin.path)
      call dein#install#_rm(plugin.path)
    endif
  endfor

  call dein#install#_update(v:lua._convert2list(a:plugins),
        \ 'install', 0)
endfunction
function! dein#install#_direct_install(repo, options) abort
  let options = copy(a:options)
  let options.merged = 0

  let plugin = dein#add(a:repo, options)
  if empty(plugin)
    return
  endif

  call dein#install#_update(plugin.name, 'install', 0)
  call dein#source(plugin.name)

  " Add to direct_install.vim
  let file = dein#get_direct_plugins_path()
  let line = printf('call dein#add(%s, %s)',
        \ string(a:repo), string(options))
  if !filereadable(file)
    call writefile([line], file)
  else
    call writefile(add(readfile(file), line), file)
  endif
endfunction
function! dein#install#_rollback(date, plugins) abort
  let glob = s:get_rollback_directory() . '/' . a:date . '*'
  let rollbacks = reverse(sort(v:lua._globlist(glob)))
  if empty(rollbacks)
    return
  endif

  call dein#install#_load_rollback(rollbacks[0], a:plugins)
endfunction

function! dein#install#_recache_runtimepath() abort
  if luaeval('dein._is_sudo')
    return
  endif

  " Clear runtime path.
  call v:lua.clear_runtimepath()

  let plugins = values(v:lua.dein.get())

  let merged_plugins = filter(copy(plugins), 'v:val.merged')

  call s:copy_files(filter(copy(merged_plugins), 'v:val.lazy'), '')
  " Remove plugin directory
  call dein#install#_rm(v:lua._get_runtime_path() . '/plugin')
  call dein#install#_rm(v:lua._get_runtime_path() . '/after/plugin')

  call s:copy_files(filter(copy(merged_plugins), '!v:val.lazy'), '')

  call s:helptags()

  call s:generate_ftplugin()

  " Clear ftdetect and after/ftdetect directories.
  call dein#install#_rm(
        \ v:lua._get_runtime_path().'/ftdetect')
  call dein#install#_rm(
        \ v:lua._get_runtime_path().'/after/ftdetect')

  call v:lua.merge_files(plugins, 'ftdetect')
  call v:lua.merge_files(plugins, 'after/ftdetect')

  silent call dein#remote_plugins()

  call dein#call_hook('post_source')

  call v:lua._save_merged_plugins()

  call dein#install#_save_rollback(
        \ s:get_rollback_directory() . '/' . strftime('%Y%m%d%H%M%S'), [])

  lua _clear_state()

  call s:log(strftime('Runtimepath updated: (%Y/%m/%d %H:%M:%S)'))
endfunction
function! s:helptags() abort
  if luaeval('dein._runtime_path') ==# '' || luaeval('dein._is_sudo')
    return ''
  endif

  try
    let tags = v:lua._get_runtime_path() . '/doc'
    if !isdirectory(tags)
      call mkdir(tags, 'p')
    endif
    call s:copy_files(filter(
          \ values(v:lua.dein.get()), '!v:val.merged'), 'doc')
    silent execute 'helptags' fnameescape(tags)
  catch /^Vim(helptags):E151:/
    " Ignore an error that occurs when there is no help file
  catch
    call s:error('Error generating helptags:')
    call s:error(v:exception)
    call s:error(v:throwpoint)
  endtry
endfunction
function! s:copy_files(plugins, directory) abort
  let directory = (a:directory ==# '' ? '' : '/' . a:directory)
  let srcs = filter(map(copy(a:plugins), 'v:val.rtp . directory'),
        \ 'isdirectory(v:val)')
  let stride = 50
  for start in range(0, len(srcs), stride)
    call dein#install#_copy_directories(srcs[start : start + stride-1],
          \ v:lua._get_runtime_path() . directory)
  endfor
endfunction
function! s:list_directory(directory) abort
  lua require 'dein/util'
  return v:lua._globlist(a:directory . '/*')
endfunction
function! dein#install#_save_rollback(rollbackfile, plugins) abort
  let revisions = {}
  for plugin in filter(v:lua._get_plugins(a:plugins),
        \ 's:check_rollback(v:val)')
    let rev = s:get_revision_number(plugin)
    if rev !=# ''
      let revisions[plugin.name] = rev
    endif
  endfor

  call writefile([json_encode(revisions)], expand(a:rollbackfile))
endfunction
function! dein#install#_load_rollback(rollbackfile, plugins) abort
  let revisions = json_decode(readfile(a:rollbackfile)[0])

  let plugins = v:lua._get_plugins(a:plugins)
  call filter(plugins, "has_key(revisions, v:val.name)
        \ && has_key(dein#util#_get_type(v:val.type),
        \            'get_rollback_command')
        \ && s:check_rollback(v:val)
        \ && s:get_revision_number(v:val) !=# revisions[v:val.name]")
  if empty(plugins)
    return
  endif

  for plugin in plugins
    let type = dein#util#_get_type(plugin.type)
    let cmd = type.get_rollback_command(
          \ dein#util#_get_type(plugin.type), revisions[plugin.name])
    call dein#install#_each(cmd, plugin)
  endfor

  call dein#recache_runtimepath()
  call s:error('Rollback to '.fnamemodify(a:rollbackfile, ':t').' version.')
endfunction
function! s:get_rollback_directory() abort
  let parent = printf('%s/rollbacks/%s',
        \ v:lua._get_cache_path(), luaeval('dein._progname'))
  if !isdirectory(parent)
    call mkdir(parent, 'p')
  endif

  return parent
endfunction
function! s:check_rollback(plugin) abort
  return !has_key(a:plugin, 'local')
        \ && !get(a:plugin, 'frozen', 0)
        \ && get(a:plugin, 'rev', '') ==# ''
endfunction

function! s:generate_ftplugin() abort
  " Create after/ftplugin
  let after = v:lua._get_runtime_path() . '/after/ftplugin'
  if !isdirectory(after)
    call mkdir(after, 'p')
  endif

  " Merge dein._ftplugin
  let ftplugin = {}
  for [key, string] in items(luaeval('dein._ftplugin'))
    for ft in (key ==# '_' ? ['_'] : split(key, '_'))
      if !has_key(ftplugin, ft)
        let ftplugin[ft] = (ft ==# '_') ? [] : [
              \ "if exists('b:undo_ftplugin')",
              \ "  let b:undo_ftplugin .= '|'",
              \ 'else',
              \ "  let b:undo_ftplugin = ''",
              \ 'endif',
              \ ]
      endif
      let ftplugin[ft] += split(string, '\n')
    endfor
  endfor

  " Generate ftplugin.vim
  call writefile(v:lua._get_default_ftplugin() + [
        \ 'function! s:after_ftplugin()',
        \ ] + get(ftplugin, '_', []) + ['endfunction'],
        \ v:lua._get_runtime_path() . '/ftplugin.vim')

  " Generate after/ftplugin
  for [filetype, list] in filter(items(ftplugin), "v:val[0] !=# '_'")
    call writefile(list, printf('%s/%s.vim', after, filetype))
  endfor
endfunction

function! dein#install#_is_async() abort
  return g:dein#install_max_processes > 1
endfunction

function! dein#install#_polling() abort
  if exists('+guioptions')
    " Note: guioptions-! does not work in async state
    let save_guioptions = &guioptions
    set guioptions-=!
  endif

  call s:install_async(g:__global_context)

  if exists('+guioptions')
    let &guioptions = save_guioptions
  endif
endfunction

function! dein#install#_remote_plugins() abort
  if !has('nvim')
    return
  endif

  if has('vim_starting')
    " Note: UpdateRemotePlugins is not defined in vim_starting
    autocmd dein VimEnter * silent call dein#remote_plugins()
    return
  endif

  if exists(':UpdateRemotePlugins') != 2
    return
  endif

  " Load not loaded neovim remote plugins
  let remote_plugins = filter(values(v:lua.dein.get()),
        \ "isdirectory(v:val.rtp . '/rplugin') && !v:val.sourced")

  lua require 'dein/autoload'
  call v:lua._source(remote_plugins)

  call s:log('loaded remote plugins: ' .
        \ string(map(copy(remote_plugins), 'v:val.name')))

  lua require 'dein/util'
  let &runtimepath = v:lua._join_rtp(v:lua._uniq(
        \ v:lua._split_rtp(&runtimepath)), &runtimepath, '')

  let result = execute('UpdateRemotePlugins', '')
  call s:log(result)
endfunction

function! dein#install#_each(cmd, plugins) abort
  let plugins = filter(v:lua._get_plugins(a:plugins),
        \ 'isdirectory(v:val.path)')

  let global_context_save = g:__global_context

  let context = s:init_context(plugins, 'each', 0)
  call s:init_variables(context)

  let cwd = getcwd()
  let error = 0
  try
    for plugin in plugins
      call dein#install#_cd(plugin.path)

      if dein#install#_execute(a:cmd)
        let error = 1
      endif
    endfor
  catch
    call s:error(v:exception . ' ' . v:throwpoint)
    return 1
  finally
    let g:__global_context = global_context_save
    call dein#install#_cd(cwd)
  endtry

  return error
endfunction
function! dein#install#_build(plugins) abort
  let error = 0
  for plugin in filter(v:lua._get_plugins(a:plugins),
        \ "isdirectory(v:val.path) && has_key(v:val, 'build')")
    call s:print_progress_message('Building: ' . plugin.name)
    if dein#install#_each(plugin.build, plugin)
      let error = 1
    endif
  endfor
  return error
endfunction

function! dein#install#_get_log() abort
  return g:__log
endfunction
function! dein#install#_get_updates_log() abort
  return g:__updates_log
endfunction
function! dein#install#_get_context() abort
  return g:__global_context
endfunction
function! dein#install#_get_progress() abort
  return g:__progress
endfunction

function! s:get_progress_message(plugin, number, max) abort
  return printf('(%'.len(a:max).'d/%'.len(a:max).'d) [%s%s] %s',
        \ a:number, a:max,
        \ repeat('+', (a:number*20/a:max)),
        \ repeat('-', 20 - (a:number*20/a:max)),
        \ a:plugin.name)
endfunction
function! s:get_plugin_message(plugin, number, max, message) abort
  return printf('(%'.len(a:max).'d/%d) |%-20s| %s',
        \ a:number, a:max, a:plugin.name, a:message)
endfunction
function! s:get_short_message(plugin, number, max, message) abort
  return printf('(%'.len(a:max).'d/%d) %s', a:number, a:max, a:message)
endfunction
function! s:get_sync_command(plugin, update_type, number, max) abort "{{{i
  let type = dein#util#_get_type(a:plugin.type)

  if a:update_type ==# 'check_update'
        \ && has_key(type, 'get_fetch_remote_command')
    let cmd = type.get_fetch_remote_command(a:plugin)
  elseif has_key(type, 'get_sync_command')
    let cmd = type.get_sync_command(a:plugin)
  else
    return ['', '']
  endif

  if empty(cmd)
    return ['', '']
  endif

  let message = s:get_plugin_message(a:plugin, a:number, a:max, string(cmd))

  return [cmd, message]
endfunction
function! s:get_revision_number(plugin) abort
  let type = dein#util#_get_type(a:plugin.type)

  if !isdirectory(a:plugin.path)
        \ || !has_key(type, 'get_revision_number_command')
    return ''
  endif

  let cmd = type.get_revision_number_command(a:plugin)
  if empty(cmd)
    return ''
  endif

  let rev = s:system_cd(cmd, a:plugin.path)

  " If rev contains spaces, it is error message
  if rev =~# '\s'
    call s:error(a:plugin.name)
    call s:error('Error revision number: ' . rev)
    return ''
  elseif rev ==# ''
    call s:error(a:plugin.name)
    call s:error('Empty revision number: ' . rev)
    return ''
  endif
  return rev
endfunction
function! s:get_revision_remote(plugin) abort
  let type = dein#util#_get_type(a:plugin.type)

  if !isdirectory(a:plugin.path)
        \ || !has_key(type, 'get_revision_remote_command')
    return ''
  endif

  let cmd = type.get_revision_remote_command(a:plugin)
  if empty(cmd)
    return ''
  endif

  let rev = s:system_cd(cmd, a:plugin.path)
  " If rev contains spaces, it is error message
  return (rev !~# '\s') ? rev : ''
endfunction
function! s:get_updated_log_message(plugin, new_rev, old_rev) abort
  let type = dein#util#_get_type(a:plugin.type)

  let cmd = has_key(type, 'get_log_command') ?
        \ type.get_log_command(a:plugin, a:new_rev, a:old_rev) : ''
  let log = empty(cmd) ? '' : s:system_cd(cmd, a:plugin.path)
  return log !=# '' ? log :
        \            (a:old_rev  == a:new_rev) ? ''
        \            : printf('%s -> %s', a:old_rev, a:new_rev)
endfunction
function! s:lock_revision(process, context) abort
  let num = a:process.number
  let max = a:context.max_plugins
  let plugin = a:process.plugin

  let plugin.new_rev = s:get_revision_number(plugin)

  let type = dein#util#_get_type(plugin.type)
  if !has_key(type, 'get_revision_lock_command')
    return 0
  endif

  let cmd = type.get_revision_lock_command(plugin)

  if empty(cmd) || plugin.new_rev ==# get(plugin, 'rev', '')
    " Skipped.
    return 0
  elseif type(cmd) == v:t_string && cmd =~# '^E: '
    " Errored.
    call s:error(plugin.path)
    call s:error(cmd[3:])
    return -1
  endif

  if get(plugin, 'rev', '') !=# ''
    call s:log(s:get_plugin_message(plugin, num, max, 'Locked'))
  endif

  let result = s:system_cd(cmd, plugin.path)
  let status = dein#install#_status()

  if status
    call s:error(plugin.path)
    call s:error(result)
    return -1
  endif
endfunction
function! s:get_updated_message(context, plugins) abort
  if empty(a:plugins)
    return ''
  endif

  return "Updated plugins:\n".
        \ join(map(copy(a:plugins),
        \ "'  ' . v:val.name . (v:val.commit_count == 0 ? ''
        \                     : printf('(%d change%s)',
        \                              v:val.commit_count,
        \                              (v:val.commit_count == 1 ? '' : 's')))
        \    . ((a:context.update_type !=# 'check_update'
        \        && v:val.old_rev !=# ''
        \        && v:val.uri =~# '^\\h\\w*://github.com/') ? \"\\n\"
        \      . printf('    %s/compare/%s...%s',
        \        substitute(substitute(v:val.uri, '\\.git$', '', ''),
        \          '^\\h\\w*:', 'https:', ''),
        \        v:val.old_rev, v:val.new_rev) : '')")
        \ , "\n")
endfunction
function! s:get_errored_message(plugins) abort
  if empty(a:plugins)
    return ''
  endif

  let msg = "Error installing plugins:\n".join(
        \ map(copy(a:plugins), "'  ' . v:val.name"), "\n")
  let msg .= "\n"
  let msg .= "Please read the error message log with the :message command.\n"

  return msg
endfunction


" Helper functions
function! dein#install#_cd(path) abort
  if !isdirectory(a:path)
    return
  endif

  try
    noautocmd execute (haslocaldir() ? 'lcd' : 'cd') fnameescape(a:path)
  catch
    call s:error('Error cd to: ' . a:path)
    call s:error('Current directory: ' . getcwd())
    call s:error(v:exception)
    call s:error(v:throwpoint)
  endtry
endfunction
function! dein#install#_system(command) abort
  " Todo: use job API instead for Vim8/neovim only
  " let job = s:Job.start()
  " let exitval = job.wait()

  let command = a:command
  let command = s:iconv(command, &encoding, 'char')
  let output = s:iconv(system(command), 'char', &encoding)
  return substitute(output, '\n$', '', '')
endfunction
function! dein#install#_status() abort
  return v:shell_error
endfunction
function! s:system_cd(command, path) abort
  let cwd = getcwd()
  try
    call dein#install#_cd(a:path)
    return dein#install#_system(a:command)
  finally
    call dein#install#_cd(cwd)
  endtry
  return ''
endfunction

function! dein#install#_execute(command) abort
  return s:job_execute.execute(a:command)
endfunction
let s:job_execute = {}
function! s:job_execute.on_out(data) abort
  for line in a:data
    echo line
  endfor

  let candidates = s:job_execute.candidates
  if empty(candidates)
    call add(candidates, a:data[0])
  else
    let candidates[-1] .= a:data[0]
  endif
  let candidates += a:data[1:]
endfunction
function! s:job_execute.execute(cmd) abort
  let self.candidates = []

  let job = s:get_job().start(
        \ s:convert_args(a:cmd),
        \ {'on_stdout': self.on_out})

  return job.wait(g:dein#install_process_timeout * 1000)
endfunction

function! dein#install#_rm(path) abort
  if !isdirectory(a:path) && !filereadable(a:path)
    return
  endif

  " Todo: use :python3 instead.

  " Note: delete rf is broken
  " if has('patch-7.4.1120')
  "   try
  "     call delete(a:path, 'rf')
  "   catch
  "     call s:error('Error deleting directory: ' . a:path)
  "     call s:error(v:exception)
  "     call s:error(v:throwpoint)
  "   endtry
  "   return
  " endif

  " Note: In Windows, ['rmdir', '/S', '/Q'] does not work.
  " After Vim 8.0.928, double quote escape does not work in job.  Too bad.
  let cmdline = ' "' . a:path . '"'
  if v:lua._is_windows()
    " Note: In rm command, must use "\" instead of "/".
    let cmdline = substitute(cmdline, '/', '\\\\', 'g')
  endif

  let rm_command = v:lua._is_windows() ? 'cmd /C rmdir /S /Q' : 'rm -rf'
  let cmdline = rm_command . cmdline
  let result = system(cmdline)
  if v:shell_error
    call dein#util#_error(result)
  endif

  " Error check.
  if getftype(a:path) !=# ''
    call dein#util#_error(printf('"%s" cannot be removed.', a:path))
    call dein#util#_error(printf('cmdline is "%s".', cmdline))
  endif
endfunction

function! dein#install#_copy_directories(srcs, dest) abort
  if empty(a:srcs)
    return 0
  endif

  let status = 0
  if v:lua._is_windows()
    if !executable('robocopy')
      call dein#util#_error('robocopy command is needed.')
      return 1
    endif

    let temp = tempname() . '.bat'
    let exclude = tempname()

    try
      let lines = ['@echo off']
      let format ='robocopy.exe %s /E /NJH /NJS /NDL /NC /NS /MT /XO /XD ".git"'
      for src in a:srcs
        call add(lines, printf(format,
              \                substitute(printf('"%s" "%s"', src, a:dest),
              \                           '/', '\\', 'g')))
      endfor
      call writefile(lines, temp)
      let result = dein#install#_system(temp)
    finally
      call delete(temp)
    endtry

    " For some baffling reason robocopy almost always returns between 1 and 3
    " upon success
    let status = dein#install#_status()
    let status = (status > 3) ? status : 0

    if status
      call dein#util#_error('copy command failed.')
      call dein#util#_error(s:iconv(result, 'char', &encoding))
      call dein#util#_error('cmdline: ' . temp)
      call dein#util#_error('tempfile: ' . string(lines))
    endif
  else " Not Windows
    let srcs = map(filter(copy(a:srcs),
          \ 'len(s:list_directory(v:val))'), 'shellescape(v:val . ''/'')')
    let is_rsync = executable('rsync')
    if is_rsync
      let cmdline = printf("rsync -a -q --exclude '/.git/' %s %s",
            \ join(srcs), shellescape(a:dest))
      let result = dein#install#_system(cmdline)
      let status = dein#install#_status()
    else
      for src in srcs
        let cmdline = printf('cp -Ra %s* %s', src, shellescape(a:dest))
        let result = dein#install#_system(cmdline)
        let status = dein#install#_status()
        if status
          break
        endif
      endfor
    endif
    if status
      call dein#util#_error('copy command failed.')
      call dein#util#_error(result)
      call dein#util#_error('cmdline: ' . cmdline)
    endif
  endif

  return status
endfunction

function! s:install_blocking(context) abort
  try
    while 1
      call s:check_loop(a:context)

      if empty(a:context.processes)
            \ && a:context.number == a:context.max_plugins
        break
      endif
    endwhile
  finally
    call s:done(a:context)
  endtry


  return len(a:context.errored_plugins)
endfunction
function! s:install_async(context) abort
  if empty(a:context)
    return
  endif

  call s:check_loop(a:context)

  if empty(a:context.processes)
        \ && a:context.number == a:context.max_plugins
    call s:done(a:context)
  elseif a:context.number != a:context.prev_number
        \ && a:context.number < len(a:context.plugins)
    let plugin = a:context.plugins[a:context.number]
    call s:print_progress_message(
          \ s:get_progress_message(plugin,
          \   a:context.number, a:context.max_plugins))
    let a:context.prev_number = a:context.number
  endif

  return len(a:context.errored_plugins)
endfunction
function! s:check_loop(context) abort
  while a:context.number < a:context.max_plugins
        \ && len(a:context.processes) < g:dein#install_max_processes

    let plugin = a:context.plugins[a:context.number]
    call s:sync(plugin, a:context)

    if !a:context.async
      call s:print_progress_message(
            \ s:get_progress_message(plugin,
            \   a:context.number, a:context.max_plugins))
    endif
  endwhile

  for process in a:context.processes
    call s:check_output(a:context, process)
  endfor

  " Filter eof processes.
  call filter(a:context.processes, '!v:val.eof')
endfunction
function! s:restore_view(context) abort
  if a:context.progress_type ==# 'tabline'
    let &g:showtabline = a:context.showtabline
    let &g:tabline = a:context.tabline
  elseif a:context.progress_type ==# 'title'
    let &g:title = a:context.title
    let &g:titlestring = a:context.titlestring
  endif
endfunction
function! s:init_context(plugins, update_type, async) abort
  let context = {}
  let context.update_type = a:update_type
  let context.async = a:async
  let context.synced_plugins = []
  let context.errored_plugins = []
  let context.processes = []
  let context.number = 0
  let context.prev_number = -1
  let context.plugins = a:plugins
  let context.max_plugins = len(context.plugins)
  let context.progress_type = (has('vim_starting')
        \ && g:dein#install_progress_type !=# 'none') ?
        \ 'echo' : g:dein#install_progress_type
  if !has('nvim') && context.progress_type ==# 'title'
    let context.progress_type = 'echo'
  endif
  let context.message_type = (has('vim_starting')
        \ && g:dein#install_message_type !=# 'none') ?
        \ 'echo' : g:dein#install_message_type
  let context.laststatus = &g:laststatus
  let context.showtabline = &g:showtabline
  let context.tabline = &g:tabline
  let context.title = &g:title
  let context.titlestring = &g:titlestring
  return context
endfunction
function! s:init_variables(context) abort
  let g:__progress = ''
  let g:__global_context = a:context
  let g:__log = []
  let g:__updates_log = []
endfunction
function! s:convert_args(args) abort
  let args = s:iconv(a:args, &encoding, 'char')
  if type(args) != v:t_list
    let args = split(&shell) + split(&shellcmdflag) + [args]
  endif
  return args
endfunction
function! s:start() abort
  call s:notify(strftime('Update started: (%Y/%m/%d %H:%M:%S)'))
endfunction
function! s:done(context) abort
  call s:restore_view(a:context)

  if !has('vim_starting')
    call s:notify(s:get_updated_message(a:context, a:context.synced_plugins))
    call s:notify(s:get_errored_message(a:context.errored_plugins))
  endif

  if a:context.update_type !=# 'check_update'
    call dein#install#_recache_runtimepath()
  endif

  if !empty(a:context.synced_plugins)
    call dein#call_hook('done_update', a:context.synced_plugins)
    call dein#source(map(copy(a:context.synced_plugins), 'v:val.name'))
  endif

  call s:notify(strftime('Done: (%Y/%m/%d %H:%M:%S)'))

  " Disable installation handler
  let g:__global_context = {}
  let g:__progress = ''
  augroup dein-install
    autocmd!
  augroup END
  if exists('s:timer')
    call timer_stop(s:timer)
    unlet s:timer
  endif
endfunction

function! s:sync(plugin, context) abort
  let a:context.number += 1

  let num = a:context.number
  let max = a:context.max_plugins

  if isdirectory(a:plugin.path) && get(a:plugin, 'frozen', 0)
    " Skip frozen plugin
    call s:log(s:get_plugin_message(a:plugin, num, max, 'is frozen.'))
    return
  endif

  let [cmd, message] = s:get_sync_command(
        \   a:plugin, a:context.update_type,
        \   a:context.number, a:context.max_plugins)

  if empty(cmd)
    " Skip
    call s:log(s:get_plugin_message(a:plugin, num, max, message))
    return
  endif

  if type(cmd) == v:t_string && cmd =~# '^E: '
    " Errored.

    call s:print_progress_message(s:get_plugin_message(
          \ a:plugin, num, max, 'Error'))
    call s:error(cmd[3:])
    call add(a:context.errored_plugins,
          \ a:plugin)
    return
  endif

  if !a:context.async
    call s:print_progress_message(message)
  endif

  let process = s:init_process(a:plugin, a:context, cmd)
  if !empty(process)
    call add(a:context.processes, process)
  endif
endfunction
function! s:init_process(plugin, context, cmd) abort
  let process = {}

  let cwd = getcwd()
  let lang_save = $LANG
  let prompt_save = $GIT_TERMINAL_PROMPT
  try
    let $LANG = 'C'
    " Disable git prompt (git version >= 2.3.0)
    let $GIT_TERMINAL_PROMPT = 0

    call dein#install#_cd(a:plugin.path)

    let rev = s:get_revision_number(a:plugin)

    let process = {
          \ 'number': a:context.number,
          \ 'max_plugins': a:context.max_plugins,
          \ 'rev': rev,
          \ 'plugin': a:plugin,
          \ 'output': '',
          \ 'status': -1,
          \ 'eof': 0,
          \ 'installed': isdirectory(a:plugin.path),
          \ }

    if isdirectory(a:plugin.path)
          \ && !get(a:plugin, 'local', 0)
      let rev_save = get(a:plugin, 'rev', '')
      try
        " Force checkout HEAD revision.
        " The repository may be checked out.
        let a:plugin.rev = ''

        call s:lock_revision(process, a:context)
      finally
        let a:plugin.rev = rev_save
      endtry
    endif

    call s:init_job(process, a:context, a:cmd)
  finally
    let $LANG = lang_save
    let $GIT_TERMINAL_PROMPT = prompt_save
    call dein#install#_cd(cwd)
  endtry

  return process
endfunction
function! s:init_job(process, context, cmd) abort
  let a:process.start_time = localtime()

  if !a:context.async
    let a:process.output = dein#install#_system(a:cmd)
    let a:process.status = dein#install#_status()
    return
  endif

  let a:process.async = {'eof': 0}
  function! a:process.async.job_handler(data) abort
    if !has_key(self, 'candidates')
      let self.candidates = []
    endif
    let candidates = self.candidates
    if empty(candidates)
      call add(candidates, a:data[0])
    else
      let candidates[-1] .= a:data[0]
    endif

    let candidates += a:data[1:]
  endfunction

  function! a:process.async.on_exit(exitval) abort
    let self.exitval = a:exitval
  endfunction

  function! a:process.async.get(process) abort
    " Check job status
    let status = -1
    if has_key(a:process.job, 'exitval')
      let self.eof = 1
      let status = a:process.job.exitval
    endif

    let candidates = get(a:process.job, 'candidates', [])
    let output = join((self.eof ? candidates : candidates[: -2]), "\n")
    if output !=# ''
      let a:process.output .= output
      let a:process.start_time = localtime()
      call s:log(s:get_short_message(
            \ a:process.plugin, a:process.number,
            \ a:process.max_plugins, output))
    endif
    let self.candidates = self.eof ? [] : candidates[-1:]

    let is_timeout = (localtime() - a:process.start_time)
          \             >= get(a:process.plugin, 'timeout',
          \                    g:dein#install_process_timeout)

    if self.eof
      let is_timeout = 0
      let is_skip = 0
    else
      let is_skip = 1
    endif

    if is_timeout
      call a:process.job.stop()
      let status = -1
    endif

    return [is_timeout, is_skip, status]
  endfunction

  let a:process.job = s:get_job().start(
        \ s:convert_args(a:cmd), {
        \   'on_stdout': a:process.async.job_handler,
        \   'on_stderr': a:process.async.job_handler,
        \   'on_exit': a:process.async.on_exit,
        \ })
  let a:process.id = a:process.job.pid()
  let a:process.job.candidates = []
endfunction
function! s:check_output(context, process) abort
  if a:context.async
    let [is_timeout, is_skip, status] = a:process.async.get(a:process)
  else
    let [is_timeout, is_skip, status] = [0, 0, a:process.status]
  endif

  if is_skip && !is_timeout
    return
  endif

  let num = a:process.number
  let max = a:context.max_plugins
  let plugin = a:process.plugin

  if isdirectory(plugin.path)
        \ && get(plugin, 'rev', '') !=# ''
        \ && !get(plugin, 'local', 0)
    " Restore revision.
    call s:lock_revision(a:process, a:context)
  endif

  let new_rev = (a:context.update_type ==# 'check_update') ?
        \ s:get_revision_remote(plugin) :
        \ s:get_revision_number(plugin)

  if is_timeout || status
    call s:log(s:get_plugin_message(plugin, num, max, 'Error'))
    call s:error(plugin.path)
    if !a:process.installed
      if !isdirectory(plugin.path)
        call s:error('Maybe wrong username or repository.')
      elseif isdirectory(plugin.path)
        call s:error('Remove the installed directory:' . plugin.path)
        call dein#install#_rm(plugin.path)
      endif
    endif

    call s:error((is_timeout ?
          \    strftime('Process timeout: (%Y/%m/%d %H:%M:%S)') :
          \    split(a:process.output, '\n')
          \ ))

    call add(a:context.errored_plugins,
          \ plugin)
  elseif a:process.rev ==# new_rev
        \ || (a:context.update_type ==# 'check_update' && new_rev ==# '')
    if a:context.update_type !=# 'check_update'
      call s:log(s:get_plugin_message(
            \ plugin, num, max, 'Same revision'))
    endif
  else
    call s:log(s:get_plugin_message(plugin, num, max, 'Updated'))

    if a:context.update_type !=# 'check_update'
      let log_messages = split(s:get_updated_log_message(
            \   plugin, new_rev, a:process.rev), '\n')
      let plugin.commit_count = len(log_messages)
      call s:log(map(log_messages,
            \   's:get_short_message(plugin, num, max, v:val)'))
    else
      let plugin.commit_count = 0
    endif

    let plugin.old_rev = a:process.rev
    let plugin.new_rev = new_rev

    let type = dein#util#_get_type(plugin.type)
    let plugin.uri = has_key(type, 'get_uri') ?
          \ type.get_uri(plugin.repo, plugin) : ''

    let cwd = getcwd()
    try
      call dein#install#_cd(plugin.path)

      call dein#call_hook('post_update', plugin)
    finally
      call dein#install#_cd(cwd)
    endtry

    if dein#install#_build([plugin.name])
      call s:log(s:get_plugin_message(plugin, num, max, 'Build failed'))
      call s:error(plugin.path)
      " Remove.
      call add(a:context.errored_plugins, plugin)
    else
      call add(a:context.synced_plugins, plugin)
    endif
  endif

  let a:process.eof = 1
endfunction

function! s:iconv(expr, from, to) abort
  if a:from ==# '' || a:to ==# '' || a:from ==? a:to
    return a:expr
  endif

  if type(a:expr) == v:t_list
    return map(copy(a:expr), 'iconv(v:val, a:from, a:to)')
  else
    let result = iconv(a:expr, a:from, a:to)
    return result !=# '' ? result : a:expr
  endif
endfunction
function! s:print_progress_message(msg) abort
  let msg = v:lua._convert2list(a:msg)
  let context = g:__global_context
  if empty(msg) || empty(context)
    return
  endif

  let progress_type = context.progress_type
  if progress_type ==# 'tabline'
    set showtabline=2
    let &g:tabline = join(msg, "\n")
  elseif progress_type ==# 'title'
    set title
    let &g:titlestring = join(msg, "\n")
  elseif progress_type ==# 'echo'
    call s:echo(msg, 'echo')
  endif

  call s:log(msg)

  let g:__progress = join(msg, "\n")
endfunction
function! s:error(msg) abort
  let msg = v:lua._convert2list(a:msg)
  if empty(msg)
    return
  endif

  call s:echo(msg, 'error')

  call s:updates_log(msg)
endfunction
function! s:notify(msg) abort
  let msg = v:lua._convert2list(a:msg)
  let context = g:__global_context
  if empty(msg) || empty(context)
    return
  endif

  if context.message_type ==# 'echo'
    lua require 'dein/util'
    call v:lua._notify(a:msg)
  endif

  call s:updates_log(msg)
  let g:__progress = join(msg, "\n")
endfunction
function! s:updates_log(msg) abort
  let msg = v:lua._convert2list(a:msg)

  let g:__updates_log += msg
  call s:log(msg)
endfunction
function! s:log(msg) abort
  let msg = v:lua._convert2list(a:msg)
  let g:__log += msg
  call v:lua.append_log_file(msg)
endfunction

function! s:echo(expr, mode) abort
  let msg = map(filter(v:lua._convert2list(a:expr), "v:val !=# ''"),
        \ "'[dein] ' .  v:val")
  if empty(msg)
    return
  endif

  let more_save = &more
  let showcmd_save = &showcmd
  let ruler_save = &ruler
  try
    set nomore
    set noshowcmd
    set noruler

    let height = max([1, &cmdheight])
    echo ''
    for i in range(0, len(msg)-1, height)
      redraw

      let m = join(msg[i : i+height-1], "\n")
      call v:lua.__echo_mode(m, a:mode)
      if has('vim_starting')
        echo ''
      endif
    endfor
  finally
    let &more = more_save
    let &showcmd = showcmd_save
    let &ruler = ruler_save
  endtry
endfunction
