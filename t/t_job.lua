-- Test class 'Job'
-- Test by running command :luafile %
local info = debug.getinfo(1, "S")
local sfile = info.source:sub(2) -- remove @
local project_root = vim.fn.fnamemodify(sfile, ':p:h:h')

if not package.path:find(project_root) then
    package.path = package.path .. ';' .. project_root .. [[\lua\?.lua]]
end

--print(package.path)
local Job = require 'brew/job'  -- import 'Job' class
print(vim.inspect(Job))

-- Class instantiation
local job1 = Job:start({'ping', 'localhost'}, {on_exit=function(job_id, exitval, event) print("exit code:", exitval) end})
local job2 = Job:start({'ping', 'localhost'})

assert(job2:status())  -- assert job is running
assert(job2:stop()==1)  -- 1 for stop successfully; 0 for invalid id, including jobs have exited or stopped.
assert(job2:status()==false)

assert(job1:stop()==1)
assert(job1:stop()==0)
vim.api.nvim_command('sleep 100m')
assert(job1.__exitval==143)  -- 143 means the process caught a SIGTERM signal, meaning the process was killed.
print(vim.inspect(job1))

-- Check that the options of the job object are not static
job2.options.private_var = nil
job1.options.private_var = 1
assert(job2.options.private_var ~= 1)


-- {cmd} is a String it runs in the 'shell', :h jobstart
local job3 = Job:start('cmd.exe', {
    on_stdout=function(job_id, data, event)
        local str = vim.fn.join(data, "\n")
        print(string.format('job_id: %d, event: %s, data: %s', job_id, event, str))
    end,
    on_exit=function(job_id, exitval, event)
        print(string.format('job_id: %d, event: %s, exitval: %s', job_id, event, exitval))
    end})
job3:send({"echo Hello World", ""})  -- the items will be joined by newlines. :h chansend
job3:send("echo No\n")
job3:send({"echo Yes\n"})  -- 不会执行, 因为 \n 替换为 <NUL>
job3:close()
assert(job3:wait()==0)  -- test job wait

local is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1

local job4
if is_windows then
    job4 = Job:start({'ping', 'localhost'}, {on_stdout=function(job_id, data, event) print(vim.inspect(data)) end})
else
    job4 = Job:start({'ping', 'baidu.com', '-c', '1'}, {on_stdout=function(job_id, data, event) print(vim.inspect(data)) end})
end
assert(job4:status())
assert(job4:wait()==0)  -- test job wait
assert(job4:status()==false)

local job5 = Job:start({'ping', 'localhost', '&&', 'ping', 'localhost'}, {on_exit=function(job_id, exitval, event) print("exit code:", exitval) end})
