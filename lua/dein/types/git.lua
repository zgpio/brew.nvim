-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
require 'dein/util'
-- Global options definition.
-- TODO load user config
dein.types_git_command_path = 'git'
dein.types_git_default_protocol = 'https'
dein.types_git_clone_depth = 0
dein.types_git_pull_command = 'pull --ff --ff-only'
local M = {
  name='git',
  command=dein.types_git_command_path,
  executable=vim.fn.executable(dein.types_git_command_path),
}

local is_windows = _is_windows()
local function is_absolute(path)
  if is_windows then
    return path:find('^[\\/]')~=nil or path:find('^%a:')~=nil
  else
    return path:find('^/')~=nil
  end
end

local function join_paths(path1, path2)
  -- Joins two paths together, handling the case where the second path
  -- is an absolute path.
  if is_absolute(path2) then
    return path2
  end
  local p1, p2
  if is_windows then
    p1 = '[\\/]$'
    p2 = '^[\\/]'
  else
    p1 = '/$'
    p2 = '^/'
  end
  if path1:find(p1) or path2:find(p2) then
    -- the appropriate separator already exists
    return path1 .. path2
  else
    -- note: I'm assuming here that '/' is always valid as a directory
    -- separator on Windows. I know Windows has paths that start with \\?\ that
    -- diasble behavior like that, but I don't know how Vim deals with that.
    return path1 .. '/' .. path2
  end
end
local function is_git_dir(path)
  local git_dir
  if vim.fn.isdirectory(path)==1 then
    git_dir = path
  elseif vim.fn.filereadable(path)==1 then
    -- check if this is a gitdir file
    -- File starts with "gitdir: " and all text after this string is treated
    -- as the path. Any CR or NLs are stripped off the end of the file.
    local buf = vim.fn.join(vim.fn.readfile(path, 'b'), "\n")
    local matches = vim.fn.matchlist(buf, [[\C^gitdir: \(\_.*[^\r\n]\)[\r\n]*$]])
    if vim.fn.empty(matches)==1 then
      return 0
    end
    local p = vim.fn.fnamemodify(path, ':h')
    if vim.fn.fnamemodify(path, ':t') == '' then
      -- if there's no tail, the path probably ends in a directory separator
      p = vim.fn.fnamemodify(p, ':h')
    end
    git_dir = join_paths(p, matches[1])
    if vim.fn.isdirectory(git_dir)==0 then
      return 0
    end
  else
    return 0
  end

  -- Git only considers it to be a git dir if a few required files/dirs exist
  -- and are accessible inside the directory.
  -- Note: we can't actually test file permissions the way we'd like to, since
  -- getfperm() gives the mode string but doesn't tell us whether the user or
  -- group flags apply to us. Instead, just check if dirname/. is a directory.
  -- This should also check if we have search permissions.
  -- I'm assuming here that dirname/. works on windows, since I can't test.
  -- Note: Git also accepts having the GIT_OBJECT_DIRECTORY env var set instead
  -- of using .git/objects, but we don't care about that.
  for _, name in ipairs({'objects', 'refs'}) do
    if vim.fn.isdirectory(join_paths(git_dir, name))==0 then
      return 0
    end
  end

  -- Git also checks if HEAD is a symlink or a properly-formatted file.
  -- We don't really care to actually validate this, so let's just make
  -- sure the file exists and is readable.
  -- Note: it may also be a symlink, which can point to a path that doesn't
  -- necessarily exist yet.
  local head = join_paths(git_dir, 'HEAD')
  if vim.fn.filereadable(head)==0 and vim.fn.getftype(head) ~= 'link' then
    return 0
  end

  -- Sure looks like a git directory. There's a few subtleties where we'll
  -- accept a directory that git itself won't, but I think we can safely ignore
  -- those edge cases.
  return 1
end
function M:get_revision_number_command(plugin)
  if self.executable==0 then
    return {}
  end

  return {self.command, 'rev-parse', 'HEAD'}
end

function M:get_uri(repo, options)
  if repo:find('^/') or repo:find('^%a:[/\\]') then
    if is_git_dir(repo..'/.git')==1 then
      return repo
    else
      return ''
    end
  end

  local protocol, host, name, rest
  if repo:find('^git@') then
    -- Parse "git@host:name" pattern
    protocol = 'ssh'
    host = vim.fn.matchstr(repo:sub(5), '[^:]*')
    name = repo:sub(5 + vim.fn.len(host) + 1)
  else
    protocol = vim.fn.matchstr(repo, [[^.\{-}\ze://]])
    rest = repo:sub(vim.fn.len(protocol)+1)
    name = vim.fn.substitute(rest, '^://[^/]*/', '', '')
    host = vim.fn.substitute(vim.fn.matchstr(rest, [[^://\zs[^/]*\ze/]]), ':.*$', '', '')
  end
  if host == '' then
    host = 'github.com'
  end

  if protocol == ''
         or vim.fn.match(repo, [[\<\%(gh\|github\|bb\|bitbucket\):\S\+]])~=-1
         or options.type__protocol then
    protocol = options.type__protocol or dein.types_git_default_protocol
  end

  if protocol ~= 'https' and protocol ~= 'ssh' then
    _error(string.format('Repo: %s The protocol "%s" is unsecure and invalid.',
           repo, protocol))
    return ''
  end

  local uri
  if repo:find('/')==nil then
    _error(string.format('vim-scripts.org is deprecated.'
      .. ' You can use "vim-scripts/%s" instead.', repo))
    return ''
  else
    if (protocol == 'ssh' and (host == 'github.com' or host == 'bitbucket.com' or host == 'bitbucket.org')) then
      uri = 'git@' .. host .. ':' .. name
    else
      uri = protocol .. '://' .. host .. '/' .. name
    end
  end

  return uri
end
function M:get_sync_command(plugin)
  if vim.fn.isdirectory(plugin.path)==0 then
    local commands = {self.command, 'clone', '--recursive'}

    local depth = plugin.type__depth or dein.types_git_clone_depth
    if depth > 0 and (plugin.rev or '') == '' and self:get_uri(plugin.repo, plugin):find('^git@')==nil then
      table.insert(commands, '--depth=' .. depth)
    end

    table.insert(commands, self:get_uri(plugin.repo, plugin))
    table.insert(commands, plugin.path)

    return commands
  else
    local gcmd = self.command

    local cmd = dein.types_git_pull_command
    local submodule_cmd = gcmd .. ' submodule update --init --recursive'
    if _is_powershell() then
      cmd = cmd .. '; if ($?) { ' .. submodule_cmd .. ' }'
    else
      local AND = _is_fish() and '; and ' or ' && '
      cmd = cmd .. AND .. submodule_cmd
    end

    return gcmd .. ' ' .. cmd
  end
end
function M:get_revision_lock_command(plugin)
  if self.executable==0 then
    return {}
  end

  local rev = plugin.rev or ''
  if rev:find('*') then
    -- Use the released tag (git 1.9.2 or above required)
    rev = vim.fn.get(vim.fn.split(_system(
           {self.command, 'tag', '--list', vim.fn.escape(rev, '*'), '--sort', '-version:refname'}),
           "\n"), 0, '')
  end
  if rev == '' then
    -- Fix detach HEAD.
    -- Use symbolic-ref feature (git 1.8.7 or above required)
    rev = _system({
           self.command, 'symbolic-ref', '--short', 'HEAD'
           })
    if rev:find('fatal: ') then
      -- Fix "fatal: ref HEAD is not a symbolic ref" error
      rev = 'master'
    end
  end

  return {self.command, 'checkout', rev, '--'}
end
function M:get_rollback_command(plugin, rev)
  if self.executable==0 then
    return {}
  end

  return {self.command, 'reset', '--hard', rev}
end
function M:get_revision_remote_command(plugin)
  if self.executable==0 then
    return {}
  end

  local rev = plugin.rev or ''
  if rev == '' then
    rev = 'HEAD'
  end

  return {self.command, 'ls-remote', 'origin', rev}
end
function M:get_fetch_remote_command(plugin)
  if self.executable==0 then
    return {}
  end

  return {self.command, 'fetch', 'origin'}
end
function M:get_log_command(plugin, new_rev, old_rev)
  if self.executable==0 or new_rev == '' or old_rev == '' then
    return {}
  end

  -- Note: If the a:old_rev is not the ancestor of two branchs. Then do not use
  -- %s^.  use %s^ will show one commit message which already shown last time.
  local is_not_ancestor = _system(
         self.command .. ' merge-base '
         .. old_rev .. ' ' .. new_rev) == old_rev
  local t = is_not_ancestor and '' or '^'
  return string.format(self.command ..
         ' log %s%s..%s --graph --no-show-signature' ..
         ' --pretty=format:"%%h [%%cr] %%s"',
         old_rev, t, new_rev)
end
function M:init(repo, options)
  if self.executable==0 then
    return {}
  end

  if (repo:find('^/') or repo:find('^%a:[/\\]')) and is_git_dir(repo..'/.git') then
    -- Local repository.
    return { ['type']='git', ['local']=1 }
  elseif vim.fn.match(repo, [[//\%(raw\|gist\)\.githubusercontent\.com/\|/archive/[^/]\+\.zip$]])~=-1 then
    return {}
  end

  local uri = self:get_uri(repo, options)
  if uri == '' then
    return {}
  end

  local directory = vim.fn.substitute(uri, [[\.git$]], '', '')
  directory = vim.fn.substitute(directory, [[^https:/\+\|^git@]], '', '')
  directory = vim.fn.substitute(directory, ':', '/', 'g')

  return { ['type']='git', ['path']=dein._base_path..'/repos/'..directory }
end

if _TEST then
  -- Note: we prefix it with an underscore, such that the test function and real function have
  -- different names. Otherwise an accidental call in the code to `M.FirstToUpper` would
  -- succeed in tests, but later fail unexpectedly in production
  M._join_paths = join_paths
  M._is_absolute = is_absolute
  M._is_git_dir = is_git_dir
end

return M
