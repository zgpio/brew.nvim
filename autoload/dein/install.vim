lua require 'dein/util'
lua require 'dein/install'

if !exists('g:__Job')
  let g:__Job = dein#job#import()
endif
" call luaeval('dein_log:write(vim.inspect(_A), "\n")', [string(s:Job)])
" lua dein_log:flush()

func dein#install#_timer_handler(timer)
  call v:lua._polling()
endf

function! dein#install#_execute(command) abort
  let s:job_execute.candidates = []

  let job = g:__Job.start(
        \ v:lua.__convert_args(a:command),
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

let g:job_pool = []
function! dein#install#__init_job(process, context, cmd) abort
  let a:process.job = len(g:job_pool)
  call add(g:job_pool, g:__Job.start(v:lua.__convert_args(a:cmd), {}))
  let a:process.id = dein#job#_job_pid(a:process.job)
  let g:job_pool[a:process.job].candidates = []
  return a:process
endfunction
