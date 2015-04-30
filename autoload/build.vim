" Copyright (c) 2015 Alexander Heinrich <alxhnr@nudelpost.de> {{{
"
" This software is provided 'as-is', without any express or implied
" warranty. In no event will the authors be held liable for any damages
" arising from the use of this software.
"
" Permission is granted to anyone to use this software for any purpose,
" including commercial applications, and to alter it and redistribute it
" freely, subject to the following restrictions:
"
"    1. The origin of this software must not be misrepresented; you must
"       not claim that you wrote the original software. If you use this
"       software in a product, an acknowledgment in the product
"       documentation would be appreciated but is not required.
"
"    2. Altered source versions must be plainly marked as such, and must
"       not be misrepresented as being the original software.
"
"    3. This notice may not be removed or altered from any source
"       distribution.
" }}}

" Informations about various builds systems. {{{
let s:build_systems =
  \ {
  \   'make':
  \   {
  \     'file'    : 'Makefile,makefile',
  \     'command' : 'make',
  \     'target-args':
  \     {
  \       'build' : 'all',
  \     },
  \   },
  \   'CMake':
  \   {
  \     'file'    : 'CMakeLists.txt',
  \     'command' : 'cmake',
  \     'target-args':
  \     {
  \       'build' : 'all',
  \     },
  \   },
  \   'dub':
  \   {
  \     'file'    : 'dub.json',
  \     'command' : 'dub',
  \   },
  \ }
" }}}

" Build commands for some languages. {{{
let s:language_cmds =
  \ {
  \   'c':
  \   {
  \     'clean' : 'rm "%HEAD%"',
  \     'build' : 'gcc -std=c11 -Wall -Wextra "%NAME%" -o "%HEAD%"',
  \     'run'   : './"%HEAD%"',
  \   },
  \   'cpp':
  \   {
  \     'clean' : 'rm "%HEAD%"',
  \     'build' : 'g++ -std=c++11 -Wall -Wextra "%NAME%" -o "%HEAD%"',
  \     'run'   : './"%HEAD%"',
  \   },
  \   'd':
  \   {
  \     'clean' : 'rm "%HEAD%" "%HEAD%.o"',
  \     'build' : 'dmd "%NAME%"',
  \     'run'   : './"%HEAD%"',
  \   },
  \   'java':
  \   {
  \     'clean'  : 'rm "%HEAD%.class"',
  \     'build'  : 'javac -Xlint "%NAME%"',
  \     'run'    : 'java "%HEAD%"',
  \   },
  \   'tex':
  \   {
  \     'clean'  : 'rm "%HEAD%".{aux,log,nav,out,pdf,snm,toc}',
  \     'build'  : 'pdflatex -file-line-error -halt-on-error "%NAME%"',
  \     'run'    : 'xdg-open "%HEAD%.pdf"',
  \   },
  \   'ocaml':
  \   {
  \     'run' : 'ocaml "%NAME%"',
  \   },
  \ }

" Add support for some scripting languages.
for lang in split('sh,lua,python,scheme', ',')
  let s:language_cmds[lang] = { 'run' : 'chmod +x "%NAME%" && ./"%NAME%"' }
endfor
" }}}

" Gets the value associated with 'key' for the given build system. It
" checks g:build#systems first, then searches the item in the fallback
" build system dict.
function! s:get_buildsys_item(bs_name, key) " {{{
  if exists('g:build#systems') && has_key(g:build#systems, a:bs_name)
    \ && has_key(g:build#systems[a:bs_name], a:key)
    return g:build#systems[a:bs_name][a:key]
  else
    return s:build_systems[a:bs_name][a:key]
  endif
endfunction " }}}

" Returns true, if a target argument exists for the given target in the
" given build system dict.
function! s:has_target_args(build_systems, bs_name, target) " {{{
  return has_key(a:build_systems, a:bs_name)
  \ && has_key(a:build_systems[a:bs_name], 'target-args')
  \ && has_key(a:build_systems[a:bs_name]['target-args'], a:target)
endfunction " }}}

" Returns the arguments for the given target. If no args exist in
" g:build#systems and the fallback dict, it will return target itself.
function! s:get_target_args(target) " {{{
  if exists('g:build#systems')
    \ && s:has_target_args(g:build#systems, b:build_system_name, a:target)
    let l:build_info = g:build#systems[b:build_system_name]
    return l:build_info['target-args'][a:target]
  elseif s:has_target_args(s:build_systems, b:build_system_name, a:target)
    return s:build_systems[b:build_system_name]['target-args'][a:target]
  else
    return a:target
  endif
endfunction " }}}

" Return true, if the given dict contains the specified build target for
" the current file type.
function! s:has_lang_target(cmd_dict, target) " {{{
  return has_key(a:cmd_dict, &filetype)
    \ && has_key(a:cmd_dict[&filetype], a:target)
endfunction " }}}

" Builds the target for the current file with rules from the given dict.
" This function expects a valid dict with all entries needed to build the
" current file. It takes an extra argument string for the build command.
function! s:build_lang_target(cmd_dict, target, extra_args) " {{{
  " Substitute all placeholders.
  let l:cmd = a:cmd_dict[&filetype][a:target]
  let l:cmd = substitute(l:cmd, '%PATH%', expand('%:p:h'), 'g')
  let l:cmd = substitute(l:cmd, '%NAME%', expand('%:t'),   'g')
  let l:cmd = substitute(l:cmd, '%HEAD%', expand('%:t:r'), 'g')

  let l:old_makeprg = &l:makeprg
  let &l:makeprg = l:cmd
  execute 'lchdir! ' . escape(expand('%:p:h'), '\ ')
  execute g:build#make_cmd . ' ' . a:extra_args
  lchdir! -
  let &l:makeprg = l:old_makeprg
endfunction " }}}

" Setups variables, makeprg and changes the current directory.
function! build#setup() " {{{
  let l:current_path = expand('%:p')
  if !strlen(l:current_path)
    return
  endif

  let l:known_systems = keys(s:build_systems)
  if exists('g:build#systems')
    let l:known_systems += keys(g:build#systems)
    call uniq(sort(l:known_systems))
  endif

  " Search all directories from the current files pwd upwards for known
  " build files.
  while l:current_path !~ '\v^(\/|\.)$'
    let l:current_path = fnamemodify(l:current_path, ':h')
    for l:build_name in l:known_systems
      for l:build_file in
        \ split(s:get_buildsys_item(l:build_name, 'file'), ',')
        if filereadable(l:current_path . '/' . l:build_file)
          let b:build_path = l:current_path
          let b:build_system_name = l:build_name
          let &l:makeprg = s:get_buildsys_item(l:build_name, 'command')

          if exists('g:build#autochdir') && g:build#autochdir
            execute 'lchdir! ' . escape(b:build_path, '\ ')
          endif
          return
        endif
      endfor
    endfor
  endwhile

  unlet! b:build_path
  unlet! b:build_system_name
endfunction " }}}

" Try to build the given target for the current file. If the current file
" does not belong to any project, it tries to build the file itself. It
" takes arbitrary arguments, which will be passed to the build command.
function! build#target(target, ...) " {{{
  if exists('b:build_path')
    execute 'lchdir! ' . escape(b:build_path, '\ ')
    execute g:build#make_cmd . ' ' . s:get_target_args(a:target)
      \ . ' ' . join(a:000)
    lchdir! -
  elseif !strlen(expand('%:t'))
    echo 'build.vim: the current file has no name'
  elseif exists('g:build#languages')
    \ && s:has_lang_target(g:build#languages, a:target)
    call s:build_lang_target(g:build#languages, a:target, join(a:000))
  elseif s:has_lang_target(s:language_cmds, a:target)
    call s:build_lang_target(s:language_cmds, a:target, join(a:000))
  else
    echo 'Unable to ' . a:target . " '" . expand('%:t') . "'"
  endif
endfunction " }}}
