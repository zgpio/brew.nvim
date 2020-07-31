lua require 'dein/util'
lua require 'dein/install'

if !exists('g:__Job')
  let g:__Job = dein#job#import()
endif
" call luaeval('dein_log:write(vim.inspect(_A), "\n")', [string(s:Job)])
" lua dein_log:flush()

let g:job_pool = []
function! dein#install#__init_job(process, context, cmd) abort
  let a:process.job = len(g:job_pool)
  call add(g:job_pool, g:__Job.start(v:lua.__convert_args(a:cmd), {}))
  let a:process.id = dein#job#_job_pid(a:process.job)
  let g:job_pool[a:process.job].candidates = []
  return a:process
endfunction
