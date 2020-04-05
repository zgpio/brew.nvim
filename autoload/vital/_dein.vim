function! vital#_dein#new() abort
  return vital#dein#new()
endfunction

function! vital#_dein#function(funcname) abort
  silent! return function(a:funcname)
endfunction
