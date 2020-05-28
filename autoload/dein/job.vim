function! dein#job#import() abort
  return {'start': function('s:start')}
endfunction

function! s:start(args, options) abort
  let job = a:options
  let job_options = {}
  if has_key(a:options, 'cwd')
    let job_options.cwd = a:options.cwd
  endif
  if has_key(job, 'on_stdout')
    let job_options.on_stdout = function('s:_on_stdout', [job])
  endif
  if has_key(job, 'on_stderr')
    let job_options.on_stderr = function('s:_on_stderr', [job])
  endif
  let job_options.on_exit = function('s:_on_exit', [job])
  let job.__job = jobstart(a:args, job_options)
  let job.__exitval = v:null
  let job.args = a:args
  return job
endfunction

function! s:_on_stdout(job, job_id, data, event) abort
  call a:job.on_stdout(a:data)
endfunction

function! s:_on_stderr(job, job_id, data, event) abort
  call a:job.on_stderr(a:data)
endfunction

function! s:_on_exit(job, job_id, exitval, event) abort
  let a:job.exitval = a:exitval
endfunction

" Instance -------------------------------------------------------------------
function! dein#job#_job_id(job) abort
  return dein#job#_job_pid(a:job)
endfunction

function! dein#job#_job_pid(job) abort
  return jobpid(a:job.__job)
endfunction

function! dein#job#_job_status(job) abort
  try
    sleep 1m
    call jobpid(a:job.__job)
    return 'run'
  catch /^Vim\%((\a\+)\)\=:E900/
    return 'dead'
  endtry
endfunction

function! dein#job#_job_send(job, data) abort
  return chansend(a:job.__job, a:data)
endfunction

function! dein#job#_job_close(job) abort
  call chanclose(a:job.__job, 'stdin')
endfunction

function! dein#job#_job_stop(job) abort
  try
    call jobstop(a:job.__job)
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
