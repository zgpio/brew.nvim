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
