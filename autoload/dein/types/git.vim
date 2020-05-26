"=============================================================================
" FILE: git.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu at gmail.com>
"          Robert Nelson     <robert@rnelson.ca>
" License: MIT license
"=============================================================================

lua require 'dein/util'
lua require 'dein/types/git'
" Global options definition.
let g:dein#types#git#command_path = 'git'
let g:dein#types#git#default_protocol = 'https'
let g:dein#types#git#clone_depth = 0
let g:dein#types#git#pull_command = 'pull --ff --ff-only'


function! dein#types#git#define() abort
  return s:type
endfunction

let s:type = {
      \ 'name': 'git',
      \ 'command': g:dein#types#git#command_path,
      \ 'executable': executable(g:dein#types#git#command_path),
      \ }

function! s:type.init(repo, options) abort
  if !self.executable
    return {}
  endif

  if a:repo =~# '^/\|^\a:[/\\]' && v:lua.__is_git_dir(a:repo.'/.git')
    " Local repository.
    return { 'type': 'git', 'local': 1 }
  elseif a:repo =~#
        \ '//\%(raw\|gist\)\.githubusercontent\.com/\|/archive/[^/]\+\.zip$'
    return {}
  endif

  let uri = v:lua.get_uri(a:repo, a:options)
  if uri ==# ''
    return {}
  endif

  let directory = substitute(uri, '\.git$', '', '')
  let directory = substitute(directory, '^https:/\+\|^git@', '', '')
  let directory = substitute(directory, ':', '/', 'g')

  lua require 'dein/util'
  return { 'type': 'git',
        \  'path': luaeval('dein._base_path').'/repos/'.directory }
endfunction

function! s:type.get_sync_command(plugin) abort
  if !isdirectory(a:plugin.path)
    let commands = []

    call add(commands, self.command)
    call add(commands, 'clone')
    call add(commands, '--recursive')

    let depth = get(a:plugin, 'type__depth',
          \ g:dein#types#git#clone_depth)
    if depth > 0 && get(a:plugin, 'rev', '') ==# ''
          \ && v:lua.get_uri(a:plugin.repo, a:plugin) !~# '^git@'
      call add(commands, '--depth=' . depth)
    endif

    call add(commands, v:lua.get_uri(a:plugin.repo, a:plugin))
    call add(commands, a:plugin.path)

    return commands
  else
    let git = self.command

    let cmd = g:dein#types#git#pull_command
    let submodule_cmd = git . ' submodule update --init --recursive'
    if v:lua._is_powershell()
      let cmd .= '; if ($?) { ' . submodule_cmd . ' }'
    else
      let and = v:lua._is_fish() ? '; and ' : ' && '
      let cmd .= and . submodule_cmd
    endif

    return git . ' ' . cmd
  endif
endfunction

function! s:type.get_log_command(plugin, new_rev, old_rev) abort
  if !self.executable || a:new_rev ==# '' || a:old_rev ==# ''
    return []
  endif

  " Note: If the a:old_rev is not the ancestor of two branchs. Then do not use
  " %s^.  use %s^ will show one commit message which already shown last time.
  let is_not_ancestor = dein#install#_system(
        \ self.command . ' merge-base '
        \ . a:old_rev . ' ' . a:new_rev) ==# a:old_rev
  return printf(self.command .
        \ ' log %s%s..%s --graph --no-show-signature' .
        \ ' --pretty=format:"%%h [%%cr] %%s"',
        \ a:old_rev, (is_not_ancestor ? '' : '^'), a:new_rev)
endfunction
function! s:type.get_revision_lock_command(plugin) abort
  if !self.executable
    return []
  endif

  let rev = get(a:plugin, 'rev', '')
  if rev =~# '*'
    " Use the released tag (git 1.9.2 or above required)
    let rev = get(split(dein#install#_system(
          \ [self.command, 'tag', '--list',
          \  escape(rev, '*'), '--sort', '-version:refname']),
          \ "\n"), 0, '')
  endif
  if rev ==# ''
    " Fix detach HEAD.
    " Use symbolic-ref feature (git 1.8.7 or above required)
    let rev = dein#install#_system([
          \ self.command, 'symbolic-ref', '--short', 'HEAD'
          \ ])
    if rev =~# 'fatal: '
      " Fix "fatal: ref HEAD is not a symbolic ref" error
      let rev = 'master'
    endif
  endif

  return [self.command, 'checkout', rev, '--']
endfunction
function! s:type.get_rollback_command(plugin, rev) abort
  if !self.executable
    return []
  endif

  return [self.command, 'reset', '--hard', a:rev]
endfunction
function! s:type.get_revision_remote_command(plugin) abort
  if !self.executable
    return []
  endif

  let rev = get(a:plugin, 'rev', '')
  if rev ==# ''
    let rev = 'HEAD'
  endif

  return [self.command, 'ls-remote', 'origin', rev]
endfunction
function! s:type.get_fetch_remote_command(plugin) abort
  if !self.executable
    return []
  endif

  return [self.command, 'fetch', 'origin']
endfunction
