local Job = {}

-- Class instantiation function
function Job:start(cmd, opt)
  local o = {}
  setmetatable(o, self)
  self.__index = self

  local options = {}
  opt = opt or {}
  if opt.cwd then
    options.cwd = opt.cwd
  end
  if opt.env then
    options.env = opt.env
  end
  if opt.on_init then
      opt.on_init(o)
  end
  if opt.on_stdout then
    options.on_stdout = function(job_id, data, event) opt.on_stdout(job_id, data, event) end
  end
  if opt.on_stderr then
    options.on_stderr = function(job_id, data, event) opt.on_stderr(job_id, data, event) end
  end
  if opt.on_exit then
    options.on_exit = function(job_id, exitval, event)
      o.__exitval = exitval
      opt.on_exit(job_id, exitval, event)
    end
  else
    options.on_exit = function(job_id, exitval, event)
      o.__exitval = exitval
    end
  end
  o.options = options
  -- NOTE vim functions lua callback supported after nvim PR #12507
  o.id = vim.fn.jobstart(cmd, o.options)
  o.pid = vim.fn.jobpid(o.id)
  o.__exitval = nil
  o.cmd = cmd

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
