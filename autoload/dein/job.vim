function! dein#job#import() abort
  return {'start': function('s:start')}
endfunction

function! s:start(args, options) abort
  let job = a:options
  let job_options = {}
  if has_key(a:options, 'cwd')
    let job_options.cwd = a:options.cwd
  endif
  let job_options.on_stdout = function('s:_on_stdout', [job])
  let job_options.on_stderr = function('s:_on_stderr', [job])
  let job_options.on_exit = function('s:_on_exit', [job])
  let job.__job = jobstart(a:args, job_options)
  let job.__exitval = v:null
  let job.args = a:args
  return job
endfunction

function! s:job_handler(job, data) abort
  if !has_key(a:job, 'candidates')
    let a:job.candidates = []
  endif
  let candidates = a:job.candidates
  if empty(candidates)
    call add(candidates, a:data[0])
  else
    let candidates[-1] .= a:data[0]
  endif

  let candidates += a:data[1:]
endfunction
function! s:_on_stdout(job, job_id, data, event) abort
  call s:job_handler(a:job, a:data)
endfunction

function! s:_on_stderr(job, job_id, data, event) abort
  call s:job_handler(a:job, a:data)
endfunction

function! s:_on_exit(job, job_id, exitval, event) abort
  let a:job.exitval = a:exitval
  let a:job.__exitval = a:exitval
endfunction

" Instance -------------------------------------------------------------------
function! dein#job#_job_pid(job) abort
  let obj = g:job_pool[a:job]
  return jobpid(obj.__job)
endfunction

function! dein#job#_job_stop(job) abort
  let obj = g:job_pool[a:job]
  try
    call jobstop(obj.__job)
  catch /^Vim\%((\a\+)\)\=:E900/
    " NOTE:
    " Vim does not raise exception even the job has already closed so fail
    " silently for 'E900: Invalid job id' exception
  endtry
endfunction

function! dein#job#_job_wait(job, ...) abort
  let timeout = a:0 ? a:1 : v:null
  let exitval = timeout is# v:null
        \ ? jobwait([a:job.__job])[0]
        \ : jobwait([a:job.__job], timeout)[0]
  if exitval != -3
    return exitval
  endif
  " Wait until 'on_exit' callback is called
  while a:job.__exitval is# v:null
    sleep 1m
  endwhile
  return a:job.__exitval
endfunction
