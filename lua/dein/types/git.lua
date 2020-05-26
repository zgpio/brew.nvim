-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
local is_windows = _is_windows()
if is_windows then
  function __is_absolute(path)
    return path:find('^[\\/]')~=nil or path:find('^%a:')~=nil
  end
else
  function __is_absolute(path)
    return path:find('^/')~=nil
  end
end

function __join_paths(path1, path2)
  -- Joins two paths together, handling the case where the second path
  -- is an absolute path.
  if __is_absolute(path2) then
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
function __is_git_dir(path)
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
    git_dir = __join_paths(p, matches[1])
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
    if vim.fn.isdirectory(__join_paths(git_dir, name))==0 then
      return 0
    end
  end

  -- Git also checks if HEAD is a symlink or a properly-formatted file.
  -- We don't really care to actually validate this, so let's just make
  -- sure the file exists and is readable.
  -- Note: it may also be a symlink, which can point to a path that doesn't
  -- necessarily exist yet.
  local head = __join_paths(git_dir, 'HEAD')
  if vim.fn.filereadable(head)==0 and vim.fn.getftype(head) ~= 'link' then
    return 0
  end

  -- Sure looks like a git directory. There's a few subtleties where we'll
  -- accept a directory that git itself won't, but I think we can safely ignore
  -- those edge cases.
  return 1
end
function get_revision_number_command(git, plugin)
  if git.executable==0 then
    return {}
  end

  return {git.command, 'rev-parse', 'HEAD'}
end
