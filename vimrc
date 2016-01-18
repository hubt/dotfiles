set nocp
set wildmode=longest,list
set wildignore=*.class,*.o
set shiftwidth=4
set expandtab
set showmatch
" set wrapmargin=8
set terse
set wrapscan
set nomagic
set showmode
set errorbells
set incsearch
" map r :set wrapmargin=0
" map w :set wrapmargin=8
set wrap linebreak nolist
map ^I 
map f {!}fmt}
map q {!}fmt}
map k :.,$-3d
map a :set autoindent
map n :set noautoindent
" map e :,$! /bin/sh -c 'pgp -feast 2>/dev/tty||sleep 4'
" map s :,$! /bin/sh -c 'pgp -fast +clear 2>/dev/tty'
" map y :/^-----BEG/,/^-----END/! /bin/sh -c 'pgp -f 2>/dev/tty||sleep 4'
map d :.,$d
map v :,/^-----END/w !pgp -m
" map c :r ~/per/resume.ascii :r ~/per/cover
map g mb'aO/*'bo*/
map F ['aO/*'bo*/
map # :'a,.s!^!#!g
map c y'a

if has("gui_running")
    set co=80
    set lines=50
    set guifont=Lucida_Console:h7:cANSI
    behave mswin
endif

syntax on
colorscheme desert
hi Normal guifg=white guibg=black
hi Search term=bold ctermbg=1
hi Comment ctermfg=6 
