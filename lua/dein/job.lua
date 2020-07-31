local Job = {}

-- Class instantiation function
function Job:start(args, opt)
  local o = {}
  setmetatable(o, self)
  self.__index = self

  local options = {}
  local opt = opt or {}
  if opt.cwd then
    options.cwd = opt.cwd
  end
  if opt.on_stdout then
    options.on_stdout = function(job_id, data, event) opt.on_stdout(data) end
  end
  if opt.on_stderr then
    options.on_stderr = function(job_id, data, event)
      opt.on_stderr(data)
    end
  end
  if opt.on_exit then
    options.on_exit = function(job_id, exitval, event)
      o.__exitval = exitval
      opt.on_exit(exitval)
    end
  else
    options.on_exit = function(job_id, exitval, event)
      o.__exitval = exitval
    end
  end
  o.options = options
  -- NOTE vim functions lua callback supported after nvim PR #12507
  o.id = vim.fn.jobstart(args, o.options)
  o.pid = vim.fn.jobpid(o.id)
  o.__exitval = nil
  o.args = args

  return o
end

-- NOTE :h jobwait
function Job:status()
    -- vim.api.nvim_command('sleep 1m')
    return vim.fn.jobwait({self.id}, 0)[1] == -1
end

function Job:send(data)
  return vim.fn.chansend(self.id, data)
end

function Job:close()
  vim.fn.chanclose(self.id, 'stdin')
end

function Job:stop()
  return vim.fn.jobstop(self.id)
end

function Job:wait(timeout)
  local exitval
  if timeout then
      exitval = vim.fn.jobwait({self.id}, timeout)[1]
  else
      exitval = vim.fn.jobwait({self.id})[1]
  end

  if exitval ~= -3 then
    return exitval
  end
  -- Wait until 'on_exit' callback is called
  while self.__exitval==nil do
    vim.api.nvim_command('sleep 1m')
  end
  return self.__exitval
end

return Job
