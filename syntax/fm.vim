if exists("b:current_syntax")
  finish
endif

syn match fmId /^\/\d* / conceal

let b:current_syntax = "fm"