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

func dein#install#_timer_handler(timer)
  call dein#install#_polling()
endf

function! dein#install#_rollback(date, plugins) abort
  let glob = v:lua.__get_rollback_directory() . '/' . a:date . '*'
  let rollbacks = reverse(sort(v:lua._globlist(glob)))
  if empty(rollbacks)
    return
  endif

  call dein#install#_load_rollback(rollbacks[0], a:plugins)
endfunction

function! dein#install#_save_rollback(rollbackfile, plugins) abort
  let revisions = {}
  for plugin in filter(v:lua._get_plugins(a:plugins),
        \ 's:check_rollback(v:val)')
    let rev = v:lua.__get_revision_number(plugin)
    if rev !=# ''
      let revisions[plugin.name] = rev
    endif
  endfor

  call writefile([json_encode(revisions)], expand(a:rollbackfile))
endfunction
function! dein#install#_load_rollback(rollbackfile, plugins) abort
  let revisions = json_decode(readfile(a:rollbackfile)[0])

  let plugins = v:lua._get_plugins(a:plugins)
  " TODO has_key(dein#util#_get_type(v:val.type), 'get_rollback_command')
  call filter(plugins, "has_key(revisions, v:val.name)
        \ && dein#util#_get_type(v:val.type).name == 'git'
        \ && s:check_rollback(v:val)
        \ && v:lua.__get_revision_number(v:val) !=# revisions[v:val.name]")
  if empty(plugins)
    return
  endif

  for plugin in plugins
    let type = dein#util#_get_type(plugin.type)
    let cmd = v.lua.get_rollback_command(type,
          \ dein#util#_get_type(plugin.type), revisions[plugin.name])
    call v:lua._each(cmd, plugin)
  endfor

  call dein#recache_runtimepath()
  call v:lua.__error('Rollback to '.fnamemodify(a:rollbackfile, ':t').' version.')
endfunction
function! s:check_rollback(plugin) abort
  return !has_key(a:plugin, 'local')
        \ && !get(a:plugin, 'frozen', 0)
        \ && get(a:plugin, 'rev', '') ==# ''
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

  call dein#install#__install_async(g:__global_context)

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

  call v:lua.__log('loaded remote plugins: ' .
        \ string(map(copy(remote_plugins), 'v:val.name')))

  lua require 'dein/util'
  let &runtimepath = v:lua._join_rtp(v:lua._uniq(
        \ v:lua._split_rtp(&runtimepath)), &runtimepath, '')

  let result = execute('UpdateRemotePlugins', '')
  call v:lua.__log(result)
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

function! dein#install#_system(command) abort
  " Todo: use job API instead for Vim8/neovim only
  " let job = s:Job.start()
  " let exitval = job.wait()

  let command = a:command
  let command = v:lua.__iconv(command, &encoding, 'char')
  let output = v:lua.__iconv(system(command), 'char', &encoding)
  return substitute(output, '\n$', '', '')
endfunction
function! dein#install#_status() abort
  return v:shell_error
endfunction

function! dein#install#_execute(command) abort
  let s:job_execute.candidates = []

  let job = s:get_job().start(
        \ s:convert_args(a:command),
        \ {'on_stdout': s:job_execute_on_out})

  return dein#job#_job_wait(job, g:dein#install_process_timeout * 1000)
endfunction
let s:job_execute = {}
function! s:job_execute_on_out(data) abort
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

function! dein#install#__install_async(context) abort
  if empty(a:context)
    return
  endif

  call dein#install#__check_loop(a:context)

  if empty(a:context.processes)
        \ && a:context.number == a:context.max_plugins
    call v:lua.__done(a:context)
  elseif a:context.number != a:context.prev_number
        \ && a:context.number < len(a:context.plugins)
    let plugin = a:context.plugins[a:context.number]
    call v:lua.__print_progress_message(
          \ v:lua.__get_progress_message(plugin,
          \   a:context.number, a:context.max_plugins))
    let a:context.prev_number = a:context.number
  endif

  return len(a:context.errored_plugins)
endfunction
function! dein#install#__check_loop(context) abort
  while a:context.number < a:context.max_plugins
        \ && len(a:context.processes) < g:dein#install_max_processes

    let plugin = a:context.plugins[a:context.number]
    call dein#install#__sync(plugin, a:context)

    if !a:context.async
      call v:lua.__print_progress_message(
            \ v:lua.__get_progress_message(plugin,
            \   a:context.number, a:context.max_plugins))
    endif
  endwhile

  for process in a:context.processes
    call dein#install#__check_output(a:context, process)
  endfor

  " Filter eof processes.
  call filter(a:context.processes, '!v:val.eof')
endfunction
function! s:convert_args(args) abort
  let args = v:lua.__iconv(a:args, &encoding, 'char')
  if type(args) != v:t_list
    let args = split(&shell) + split(&shellcmdflag) + [args]
  endif
  return args
endfunction

function! dein#install#__sync(plugin, context) abort
  let a:context.number += 1

  let num = a:context.number
  let max = a:context.max_plugins

  if isdirectory(a:plugin.path) && get(a:plugin, 'frozen', 0)
    " Skip frozen plugin
    call v:lua.__log(v:lua.__get_plugin_message(a:plugin, num, max, 'is frozen.'))
    return
  endif

  let [cmd, message] = v:lua.__get_sync_command(
        \   a:plugin, a:context.update_type,
        \   a:context.number, a:context.max_plugins)

  if empty(cmd)
    " Skip
    call v:lua.__log(v:lua.__get_plugin_message(a:plugin, num, max, message))
    return
  endif

  if type(cmd) == v:t_string && cmd =~# '^E: '
    " Errored.

    call v:lua.__print_progress_message(v:lua.__get_plugin_message(
          \ a:plugin, num, max, 'Error'))
    call v:lua.__error(cmd[3:])
    call add(a:context.errored_plugins,
          \ a:plugin)
    return
  endif

  if !a:context.async
    call v:lua.__print_progress_message(message)
  endif

  let process = dein#install#__init_process(a:plugin, a:context, cmd)
  if !empty(process)
    call add(a:context.processes, process)
  endif
endfunction
function! dein#install#__init_process(plugin, context, cmd) abort
  let process = {}

  let cwd = getcwd()
  let lang_save = $LANG
  let prompt_save = $GIT_TERMINAL_PROMPT
  try
    let $LANG = 'C'
    " Disable git prompt (git version >= 2.3.0)
    let $GIT_TERMINAL_PROMPT = 0

    call v:lua._cd(a:plugin.path)

    let rev = v:lua.__get_revision_number(a:plugin)

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

        call v:lua.__lock_revision(process, a:context)
      finally
        let a:plugin.rev = rev_save
      endtry
    endif

    call s:init_job(process, a:context, a:cmd)
  finally
    let $LANG = lang_save
    let $GIT_TERMINAL_PROMPT = prompt_save
    call v:lua._cd(cwd)
  endtry

  return process
endfunction

function! s:async_get(async, process) abort
  " Check job status
  let status = -1
  if has_key(g:job_pool[a:process.job], 'exitval')
    let a:async.eof = 1
    let status = g:job_pool[a:process.job].exitval
  endif

  let candidates = get(g:job_pool[a:process.job], 'candidates', [])
  let output = join((a:async.eof ? candidates : candidates[: -2]), "\n")
  if output !=# ''
    let a:process.output .= output
    let a:process.start_time = localtime()
    call v:lua.__log(v:lua.__get_short_message(
          \ a:process.plugin, a:process.number,
          \ a:process.max_plugins, output))
  endif
  let a:async.candidates = a:async.eof ? [] : candidates[-1:]

  let is_timeout = (localtime() - a:process.start_time)
        \             >= get(a:process.plugin, 'timeout',
        \                    g:dein#install_process_timeout)

  if a:async.eof
    let is_timeout = 0
    let is_skip = 0
  else
    let is_skip = 1
  endif

  if is_timeout
    call dein#job#_job_stop(g:job_pool[a:process.job])
    let status = -1
  endif

  return [is_timeout, is_skip, status]
endfunction
let g:job_pool = []
function! s:init_job(process, context, cmd) abort
  let a:process.start_time = localtime()

  if !a:context.async
    let a:process.output = dein#install#_system(a:cmd)
    let a:process.status = dein#install#_status()
    return
  endif

  let a:process.async = {'eof': 0}

  let a:process.job = len(g:job_pool)
  call add(g:job_pool, s:get_job().start(s:convert_args(a:cmd), {}))
  let a:process.id = dein#job#_job_pid(g:job_pool[a:process.job])
  let g:job_pool[a:process.job].candidates = []
endfunction
function! dein#install#__check_output(context, process) abort
  if a:context.async
    let [is_timeout, is_skip, status] = s:async_get(a:process.async, a:process)
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
    call v:lua.__lock_revision(a:process, a:context)
  endif

  let new_rev = (a:context.update_type ==# 'check_update') ?
        \ v:lua.__get_revision_remote(plugin) :
        \ v:lua.__get_revision_number(plugin)

  if is_timeout || status
    call v:lua.__log(v:lua.__get_plugin_message(plugin, num, max, 'Error'))
    call v:lua.__error(plugin.path)
    if !a:process.installed
      if !isdirectory(plugin.path)
        call v:lua.__error('Maybe wrong username or repository.')
      elseif isdirectory(plugin.path)
        call v:lua.__error('Remove the installed directory:' . plugin.path)
        call v:lua._rm(plugin.path)
      endif
    endif

    call v:lua.__error((is_timeout ?
          \    strftime('Process timeout: (%Y/%m/%d %H:%M:%S)') :
          \    split(a:process.output, '\n')
          \ ))

    call add(a:context.errored_plugins,
          \ plugin)
  elseif a:process.rev ==# new_rev
        \ || (a:context.update_type ==# 'check_update' && new_rev ==# '')
    if a:context.update_type !=# 'check_update'
      call v:lua.__log(v:lua.__get_plugin_message(
            \ plugin, num, max, 'Same revision'))
    endif
  else
    call v:lua.__log(v:lua.__get_plugin_message(plugin, num, max, 'Updated'))

    if a:context.update_type !=# 'check_update'
      let log_messages = split(v:lua.__get_updated_log_message(
            \   plugin, new_rev, a:process.rev), '\n')
      let plugin.commit_count = len(log_messages)
      call v:lua.__log(map(log_messages,
            \   'v:lua.__get_short_message(plugin, num, max, v:val)'))
    else
      let plugin.commit_count = 0
    endif

    let plugin.old_rev = a:process.rev
    let plugin.new_rev = new_rev

    let type = dein#util#_get_type(plugin.type)
    " TODO has_key(type, 'get_uri')
    let plugin.uri = type.name == 'git' ?
          \ v:lua.get_uri(plugin.repo, plugin) : ''

    let cwd = getcwd()
    try
      call v:lua._cd(plugin.path)

      call dein#call_hook('post_update', plugin)
    finally
      call v:lua._cd(cwd)
    endtry

    if v:lua._build([plugin.name])
      call v:lua.__log(v:lua.__get_plugin_message(plugin, num, max, 'Build failed'))
      call v:lua.__error(plugin.path)
      " Remove.
      call add(a:context.errored_plugins, plugin)
    else
      call add(a:context.synced_plugins, plugin)
    endif
  endif

  let a:process.eof = 1
endfunction
