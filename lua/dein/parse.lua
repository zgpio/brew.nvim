-- vim: set sw=2 sts=4 et tw=78 foldmethod=indent:
require 'dein/util'
-- Global options definition.
dein.enable_name_conversion = dein.enable_name_conversion or false
dein.default_options = dein.default_options or {}

local function unique(items)
  local flags = {}
  local rv = {}
  for i=1,#items do
     if not flags[items[i]] then
        table.insert(rv, items[i])
        flags[items[i]] = true
     end
  end
  return rv
end
local function __check_type(repo, options)
  local plugin = {}
  require 'dein/types/git'
  for _, t in ipairs(vim.tbl_values(_get_types())) do
    plugin = t:init(repo, options)
    if vim.fn.empty(plugin)==0 then
      break
    end
  end

  if vim.fn.empty(plugin)==1 then
    plugin['type'] = 'none'
    plugin['local'] = 1
    plugin.path = ''
    if vim.fn.isdirectory(repo)==1 then
      plugin.path = repo
    end
  end

  return plugin
end
local function _dict(plug)
  local plugin = vim.tbl_extend('force', { rtp='', sourced=false }, plug)

  if plugin.name == nil then
    plugin.name = _name_conversion(plugin.repo)
  end

  if plugin.normalized_name == nil then
    plugin.normalized_name = vim.fn.substitute(
          vim.fn.fnamemodify(plugin.name, ':r'),
          [[\c^n\?vim[_-]\|[_-]n\?vim$]], '', 'g')
  end

  if plug.name==nil and dein.enable_name_conversion then
    -- Use normalized name.
    plugin.name = plugin.normalized_name
  end

  if plugin.path==nil then
    if plugin.path:find('^%a:[/\\]') or plugin.path:find('^/') then
      plugin.path = plugin.repo
    else
      plugin.path = dein._base_path..'/repos/'..plugin.name
    end
  end

  plugin.path = _chomp(_expand(plugin.path))
  if (plugin.rev or '') ~= '' then
    -- Add revision path
    plugin.path = plugin.path ..'_'.. vim.fn.substitute(plugin.rev, '[^[:alnum:].-]', '_', 'g')
  end

  -- Check relative path
  if (plug.rtp==nil or plug.rtp ~= '')
         and not (plugin.rtp:find('^[~/]') or plugin.rtp:find('^%a+:')) then
    plugin.rtp = plugin.path..'/'..plugin.rtp
  end
  -- TODO ?_? dein use [0:]
  if plugin.rtp == '~' then
    plugin.rtp = _expand(plugin.rtp)
  end
  plugin.rtp = _chomp(plugin.rtp)
  if dein._is_sudo and not (plugin.trusted==1) then
    plugin.rtp = ''
  end

  if plugin.script_type ~= nil then
    -- Add script_type.
    plugin.path = plugin.path..'/'.. plugin.script_type
  end

  if plugin.depends~=nil and type(plugin.depends) ~= 'table' then
    plugin.depends = {plugin.depends}
  end

  -- Deprecated check.
  for _, key in ipairs({'directory', 'base'}) do
    if plugin[key] ~= nil then
      _error('plugin name = ' .. plugin.name)
      _error(vim.fn.string(key) .. ' is deprecated.')
    end
  end

  if plugin.lazy==nil then
    plugin.lazy = plugin.on_i ~= nil
          or plugin.on_idle ~= nil
          or plugin.on_ft ~= nil
          or plugin.on_cmd ~= nil
          or plugin.on_func ~= nil
          or plugin.on_map ~= nil
          or plugin.on_path ~= nil
          or plugin.on_if ~= nil
          or plugin.on_event ~= nil
          or plugin.on_source ~= nil
    if plugin.lazy then plugin.lazy = 1 else plugin.lazy = 0 end
  end

  if plug.merged==nil then
    plugin.merged = plugin.lazy==0
      and plugin.normalized_name ~= 'dein'
      and plugin['local']==nil
      and plugin.build==nil
      and plugin['if']==nil
      and plugin.hook_post_update==nil
      and vim.fn.stridx(plugin.rtp, dein._base_path) == 0
    plugin.merged = plugin.merged and 1 or 0
  end

  if plugin['if']~=nil and type(plugin['if']) == 'string' then
    plugin['if'] = vim.api.nvim_eval(plug['if'])
  end

  -- Hooks
  for _, hook in ipairs({
    'hook_add', 'hook_source',
    'hook_post_source', 'hook_post_update',
    }) do
    if plugin[hook] ~= nil and type(plugin[hook]) == 'string' then
      plugin[hook] = vim.fn.substitute(plugin[hook], [=[\n\s*\\\|\%(^\|\n\)\s*"[^\n]*]=], '', 'g')
    end
  end

  return plugin
end
function _init(repo, options)
  repo = _expand(repo)
  options.type = options.type or 'git'
  local typ = _get_type(options.type)
  local plugin = typ:init(repo, options)
  if vim.fn.empty(plugin)==1 then
    plugin = __check_type(repo, options)
  end
  plugin = vim.tbl_extend('force', plugin, options)
  if not vim.tbl_isempty(dein.default_options) then
    plugin = vim.tbl_extend('keep', plugin, dein.default_options)
  end
  plugin.repo = repo
  if vim.fn.empty(options)==0 then
    plugin.orig_opts = vim.deepcopy(options)
  end
  return plugin
end
function _add(repo, options, overwrite)
  if nil == overwrite then
      overwrite = true
  end
  local _plugins = dein._plugins
  local plugin = _dict(_init(repo, options))
  local plugin_check = (_plugins[plugin.name] or {})
  overwrite = options.overwrite or overwrite
  if (plugin_check.sourced or 0)==1 or (plugin['if'] or 1)==0 then
    -- Skip already loaded or not enabled plugin.
    return {}
  end

  -- Duplicated plugins check
  if vim.fn.empty(plugin_check)==0 then
    if not overwrite then
      -- Only warning when starting
      if vim.fn.has('vim_starting')==1 then
        _error(vim.fn.printf('Plugin name "%s" is already defined.', plugin.name))
      end
      return {}
    end

    -- Overwrite
    -- Note: reparse is needed.
    options = vim.tbl_extend('keep', options,
      (dein._plugins[plugin.name]['orig_opts'] or {}))
    plugin = _dict(_init(repo, options))
  end

  if plugin.rtp ~= '' then
    if plugin.lazy==1 then
      plugin = parse_lazy(plugin)
    end
    if plugin.hook_add~=nil then
      _execute_hook(plugin, plugin.hook_add)
    end
    if plugin.ftplugin~=nil then
      merge_ftplugin(plugin.ftplugin)
    end
  end

  _plugins[plugin.name] = plugin
  dein._plugins = _plugins
  return plugin
end
function parse_lazy(plugin)
  -- Auto convert2list.
  for _, key in ipairs({'on_ft', 'on_path', 'on_cmd', 'on_func', 'on_map',
      'on_source', 'on_event'}) do
    if plugin[key] ~= nil and type(plugin[key]) ~= 'table' then
        plugin[key] = {plugin[key]}
    end
  end

  if plugin.on_i ~= nil and plugin.on_i ~= 0 then
    plugin.on_event = {'InsertEnter'}
  end
  if plugin.on_idle ~= nil and plugin.on_idle ~= 0 then
    plugin.on_event = {'FocusLost', 'CursorHold'}
  end
  local event_plugins = dein._event_plugins
  -- TODO: https://github.com/neovim/neovim/issues/12048
  assert(event_plugins[true]==nil)
  if plugin.on_event ~= nil then
    for _, event in ipairs(plugin.on_event) do
      if event_plugins[event] == nil then
        event_plugins[event] = {plugin.name}
      else
        table.insert(event_plugins[event], plugin.name)
        event_plugins[event] = unique(event_plugins[event])
      end
    end
  end
  dein._event_plugins = event_plugins

  if plugin.on_cmd ~= nil then
    generate_dummy_commands(plugin)
  end
  if plugin.on_map ~= nil then
    generate_dummy_mappings(plugin)
  end
  return plugin
end

function generate_dummy_commands(plugin)
  plugin.dummy_commands = {}
  for _, name in ipairs(plugin.on_cmd) do
    -- Define dummy commands.
    local raw_cmd = 'command -complete=customlist,v:lua._dummy_complete -bang -bar -range -nargs=* ' .. name
      .. vim.fn.printf(" call v:lua._on_cmd(%s, %s, <q-args>, expand('<bang>'), expand('<line1>'), expand('<line2>'))",
       vim.fn.string(name), vim.fn.string(plugin.name))

    table.insert(plugin.dummy_commands, {name, raw_cmd})
    vim.api.nvim_command('silent! '..raw_cmd)
  end
end

function table.slice(tbl, first, last, step)
  local sliced = {}
  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced+1] = tbl[i]
  end
  return sliced
end

function generate_dummy_mappings(plugin)
  plugin.dummy_mappings = {}
  local items = {}
  if vim.tbl_islist(plugin.on_map) then
    for _, map in ipairs(plugin.on_map) do
      if vim.tbl_islist(map) then
        table.insert(items, {vim.split(map[1], ''), table.slice(map, 2)})
      else
        table.insert(items, {{'n', 'x'}, {map}})
      end
    end
  else
    for mode, map in pairs(plugin.on_map) do
      if vim.tbl_islist(map) then
        table.insert(items, {vim.split(mode, ''), map})
      else
        table.insert(items, {vim.split(mode, ''), {map}})
      end
    end
  end

  for _, item in ipairs(items) do
    local modes, mappings = unpack(item)
    if mappings[1] == '<Plug>' then
      -- Use plugin name.
      mappings = {'<Plug>(' .. plugin.normalized_name}
      if plugin.normalized_name:find('-') then
        -- The plugin mappings may use "_" instead of "-".
        table.insert(mappings, '<Plug>(' .. plugin.normalized_name:gsub('-', '_'))
      end
    end

    for _, mapping in ipairs(mappings) do
      -- Define dummy mappings.
      local prefix = string.format('v:lua._on_map("%s", "%s",',
        mapping:gsub('<', '<lt>'), plugin.name)
      for _, mode in ipairs(modes) do
        local t
        if mode == 'c' then
          t = [[ \<C-r>=]]
        elseif mode == 'i' then
          t = [[ \<C-o>:call ]]
        else
          t = vim.api.nvim_eval([[" :\<C-u>call "]])
        end
        local raw_map = mode..'noremap <unique><silent> '..mapping
            .. t .. prefix .. '"'.. mode.. '"'.. ')<CR>'
        table.insert(plugin.dummy_mappings, {mode, mapping, raw_map})
        vim.api.nvim_command('silent! '..raw_map)
      end
    end
  end
end

function merge_ftplugin(ftplugin)
  local _ftplugin = dein._ftplugin
  -- TODO
  assert(_ftplugin[true]==nil)
  for ft, val in pairs(ftplugin) do
    if _ftplugin[ft] == nil then
      _ftplugin[ft] = val
    else
      _ftplugin[ft] = _ftplugin[ft] .. '\n' .. val
    end
  end
  _ftplugin = vim.tbl_map(
    function(v)
      return vim.fn.substitute(v, [=[\n\s*\\\|\%(^\|\n\)\s*"[^\n]*]=], '', 'g')
    end,
    _ftplugin
  )
  dein._ftplugin = _ftplugin
end

local types
function _get_type(name)
  return (_get_types()[name] or {})
end
function _get_types()
  if types == nil then
    -- Load types.
    types = {}
    local fl = vim.split(vim.fn.globpath(vim.o.rtp, 'lua/dein/types/*.lua', 1), '\n')
    for _, typ in ipairs(vim.tbl_map(
      function(v)
        return require('dein/types/'..vim.fn.fnamemodify(v, ':t:r'))
      end, fl)) do
      if not vim.tbl_isempty(typ) then
        types[typ.name] = typ
      end
    end
  end
  return types
end
function _name_conversion(path)
  return vim.fn.fnamemodify(vim.fn.get(vim.split(path, ':'), -1, ''), [[:s?/$??:t:s?\c\.git\s*$??]])
end

function _local(localdir, options, includes)
  local base = vim.fn.fnamemodify(_expand(localdir), ':p')
  local directories = {}
  for _, glob in ipairs(includes) do
    local dirs = vim.tbl_filter(
      function(v) return vim.fn.isdirectory(v)==1 end,
      _globlist(base .. glob)
    )
    dirs = vim.tbl_map(
      function(v)
        return vim.fn.substitute(_substitute_path(vim.fn.fnamemodify(v, ':p')), '/$', '', '')
      end,
      dirs
    )
    directories = vim.fn.extend(directories, dirs)
  end

  for _, dir in ipairs(_uniq(directories)) do
    options = vim.tbl_extend('force', {
      ['repo']=dir,
      ['local']=1,
      ['path']=dir,
      ['name']=vim.fn.fnamemodify(dir, ':t')
    }, options)

    if dein._plugins[options.name] then
      vim.fn['dein#config'](options.name, options)
    else
      _add(dir, options)
    end
  end
end
function _load_toml(filename, default)
  local toml
  try {
    function()
      filename = _expand(filename)
      local text = vim.fn.join(vim.fn.readfile(filename), "\n")
      -- fileencoding is always utf8
      text = vim.fn.iconv(text, 'utf8', vim.o.encoding)
      TOML = require "toml"
      toml = TOML.parse(text)
    end,
    catch {
      -- TODO catch /Text.TOML:/
      function(e)
        print(e)
        _error('Invalid toml format: ' .. filename)
        _error(vim.v.exception)
        return 1
      end
    }
  }

  if type(toml)~='table' or vim.tbl_islist(toml) then
    _error('Invalid toml file: ' .. filename)
    return 1
  end

  -- Parse.
  if toml.hook_add then
    local pattern = [[\n\s*\\\|\%(^\|\n\)\s*"[^\n]*]]
    dein._hook_add = dein._hook_add .. "\n" .. vim.fn.substitute(toml.hook_add, pattern, '', 'g')
  end
  if toml.ftplugin then
    merge_ftplugin(toml.ftplugin)
  end

  if toml.plugins then
    for _, plugin in ipairs(toml.plugins) do
      if not plugin.repo then
        _error('No repository plugin data: ' .. filename)
        return 1
      end

      local options = vim.tbl_extend('keep', plugin, default)
      _add(plugin.repo, options)
    end
  end

  -- Add to dein._vimrcs
  table.insert(dein._vimrcs, _expand(filename))
end
function _load_dict(dict, default)
  for repo, options in pairs(dict) do
    _add(repo, vim.fn.extend(vim.fn.copy(options), default, 'keep'))
  end
end
