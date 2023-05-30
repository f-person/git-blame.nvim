let g:gitblame_highlight_group = get(g:, 'gitblame_highlight_group', "Comment")
let g:gitblame_enabled = get(g:, 'gitblame_enabled', 1)
let g:gitblame_message_template = get(g:, 'gitblame_message_template', '  <author> • <date> • <summary>')
let g:gitblame_message_when_not_committed = get(g:, 'gitblame_message_when_not_committed','  Not Committed Yet')
let g:gitblame_date_format = get(g:, 'gitblame_date_format', '%c')
let g:gitblame_display_virtual_text = get(g:, 'gitblame_display_virtual_text', 1)
let g:gitblame_ignored_filetypes = get(g:, 'gitblame_ignored_filetypes', [])
let g:gitblame_delay = get(g:, 'gitblame_delay', 0)
let g:gitblame_virtual_text_column = get(g:, 'gitblame_virtual_text_column', v:null)

execute "highlight default link gitblame " .. g:gitblame_highlight_group

function! GitBlameInit()
	if g:gitblame_enabled == 0
		return
	endif

	lua require('gitblame').init()

	augroup gitblame
		autocmd!
		autocmd CursorMoved  * lua require('gitblame').schedule_show_info_display()
		autocmd CursorMovedI * lua require('gitblame').clear_virtual_text()
		autocmd InsertEnter * lua require('gitblame').clear_virtual_text()
		autocmd TextChanged  * lua require('gitblame').handle_text_changed()
		autocmd InsertLeave  * lua require('gitblame').handle_insert_leave()
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
endfunction

function! GitBlameDisable()
	autocmd! gitblame
	lua require('gitblame').disable()
endfunction

function! GitBlameToggle()
	if g:gitblame_enabled == 0
		call GitBlameEnable()
	else
		call GitBlameDisable()
	endif
endfunction

function! GitBlameOpenFileURL()
    lua require('gitblame').open_file_url()
endfunction

function! GitBlameOpenCommitURL() 
    lua require('gitblame').open_commit_url()
endfunction

function! GitBlameCopySHA()
    lua require('gitblame').copy_sha_to_clipboard()
endfunction

function! GitBlameCopyCommitURL()
    lua require('gitblame').copy_commit_url_to_clipboard()
endfunction

function! GitBlameCopyFileURL()
    lua require('gitblame').copy_file_url_to_clipboard()
endfunction

:command! -nargs=0 GitBlameToggle call GitBlameToggle()
:command! -nargs=0 GitBlameEnable call GitBlameEnable()
:command! -nargs=0 GitBlameDisable call GitBlameDisable()
:command! -nargs=0 GitBlameOpenCommitURL call GitBlameOpenCommitURL()
:command! -nargs=0 GitBlameOpenFileURL call GitBlameOpenFileURL()
:command! -nargs=0 GitBlameCopySHA call GitBlameCopySHA()
:command! -nargs=0 GitBlameCopyCommitURL call GitBlameCopyCommitURL()
:command! -nargs=0 GitBlameCopyFileURL call GitBlameCopyFileURL()

call GitBlameInit()
