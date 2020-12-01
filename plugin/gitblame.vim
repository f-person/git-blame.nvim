highlight default link gitblame Comment
let g:gitblame_enabled = get(g:, 'gitblame_enabled', 1)
let g:gitblame_message_template = get(g:, 'gitblame_message_template', '  <author> • <date> • <summary>')

function! GitBlameInit()
	if g:gitblame_enabled == 0
		return
	endif

	lua require('gitblame').init()

	augroup gitblame
		autocmd!
		autocmd CursorMoved  * lua require('gitblame').show_blame_info()
		autocmd CursorMovedI * lua require('gitblame').clear_virtual_text()
		autocmd TextChanged  * lua require('gitblame').load_blames()
		autocmd InsertLeave  * lua require('gitblame').load_blames()
		autocmd InsertLeave  * lua require('gitblame').show_blame_info()
		autocmd BufEnter     * lua require('gitblame').handle_buf_enter()
		autocmd BufDelete    * lua require('gitblame').cleanup_file_data()
	augroup END
endfunction

function! GitBlameEnable()
	if g:gitblame_enabled == 1
		return
	endif

	let g:gitblame_enabled = 1
	call GitBlameInit()
	lua require('gitblame').check_file_in_git_repo()
	lua require('gitblame').show_blame_info()
endfunction

function! GitBlameDisable()
	if g:gitblame_enabled == 0
		return
	endif

	let g:gitblame_enabled = 0
	autocmd! gitblame
	lua require('gitblame').clear_virtual_text()
	lua require('gitblame').clear_files_data()
endfunction

function! GitBlameToggle()
	if g:gitblame_enabled == 0
		call GitBlameEnable()
	else
		call GitBlameDisable()
	endif
endfunction

:command! -nargs=0 GitBlameToggle call GitBlameToggle()
:command! -nargs=0 GitBlameEnable call GitBlameEnable()
:command! -nargs=0 GitBlameDisable call GitBlameDisable()

call GitBlameInit()
