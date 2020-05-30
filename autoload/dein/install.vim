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
if !exists('g:__Job')
  let g:__Job = dein#job#import()
endif
" call luaeval('dein_log:write(vim.inspect(_A), "\n")', [string(s:Job)])
" lua dein_log:flush()

func dein#install#_timer_handler(timer)
  call dein#install#_polling()
endf

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

function! dein#install#_status() abort
  return v:shell_error
endfunction

function! dein#install#_execute(command) abort
  let s:job_execute.candidates = []

  let job = g:__Job.start(
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
    " FIXME: temporary fix
    let new_context = v:lua.__sync(plugin, a:context)
    let a:context.number = new_context.number
    let a:context.processes = new_context.processes
    let a:context.errored_plugins = new_context.errored_plugins

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
    call dein#job#_job_stop(a:process.job)
    let status = -1
  endif

  return [is_timeout, is_skip, status]
endfunction
let g:job_pool = []
function! dein#install#__init_job(process, context, cmd) abort
  let a:process.job = len(g:job_pool)
  call add(g:job_pool, g:__Job.start(s:convert_args(a:cmd), {}))
  let a:process.id = dein#job#_job_pid(a:process.job)
  let g:job_pool[a:process.job].candidates = []
  return a:process
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
