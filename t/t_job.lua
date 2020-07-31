-- Test class 'Job'
local Job = require 'dein/job'  -- import 'Job' class
print(vim.inspect(Job))

-- Class instantiation
local job1 = Job:start({'ping', 'neovim.io'}, {on_exit=function(exitval) print("exit code:", exitval) end})
local job2 = Job:start({'ping', 'baidu.com'})

assert(job2:status())
assert(job2:stop()==1)
assert(job2:status()==false)

assert(job1:stop()==1)
assert(job1:stop()==0)
vim.api.nvim_command('sleep 100m')
assert(job1.__exitval==143)
print(vim.inspect(job1))

job2.options.private_var = nil
job1.options.private_var = 1
assert(job2.options.private_var ~= 1)


local job3 = Job:start({'cat'}, {on_stdout=function(data)
  local str = vim.fn.join(data, " ")
  print(str)
end})
job3:send({"Hello", "World"})


local job4 = Job:start({'ping', 'baidu.com', '-c', '1'}, {on_stdout=function(data) print(vim.inspect(data)) end})
assert(job4:status())
assert(job4:wait()==0)
assert(job4:status()==false)
