augroup vimwiki
  if !exists('g:zettel_synced')
    let g:zettel_synced = 0
  else
    finish
  endif

  " g:zettel_dir is defined by vim_zettel
  if !exists('g:zettel_dir')
    let g:zettel_dir = vimwiki#vars#get_wikilocal('path') "VimwikiGet('path',g:vimwiki_current_idx)
  endif

  " make the Git branch used for synchronization configurable
  if !exists('g:vimwiki_sync_branch')
    let g:vimwiki_sync_branch = "HEAD"
  endif

  " enable disabling of Taskwarrior synchronization
  if !exists("g:sync_taskwarrior")
    let g:sync_taskwarrior = 1
  endif

  " don't try to start synchronization if the opend file is not in vimwiki
  " path
  let current_dir = expand("%:p:h")
  if !current_dir ==# fnamemodify(g:zettel_dir, ":h")
    finish
  endif

  if !exists('g:vimwiki_sync_commit_message')
    let g:vimwiki_sync_commit_message = 'Auto commit + push. %c'
  endif

  " don't sync temporary wiki
  if vimwiki#vars#get_wikilocal('is_temporary_wiki') == 1
    finish
  endif
  

  " execute vim function. because vimwiki can be started from any directory,
  " we must use pushd and popd commands to execute git commands in wiki root
  " dir. silent is used to disable necessity to press <enter> after each
  " command. the downside is that the command output is not displayed at all.
  " One idea: what about running git asynchronously?
  function! s:git_action(action)
    execute ':silent !' . a:action 
    " prevent screen artifacts
    redraw!
  endfunction

  " function! s:action(action)
  "   let response = substitute(system(a:action), '\n\+$', '', '')
  "   echo strtrans(response)
  "   let result = confirm("Sure?")
  "   execute "echo confirmed"
  "   " confirm('',"Yes No Question? (&Yes\n&No)",1) == 1 ? "echo do somthing" : "echo do something else"
  "   " prevent screen artifacts
  "   redraw!
  " endfunction

  " function! Rebase()
  "   let answer = confirm('Do thing?', "&Yes\n&No", 1)
  "   if answer == 1
  "     call system("do_thing")
  "     redraw
  "     echo "Did thing!"
  "   endif
  " endfunction

  function! My_exit_cbNvim(job_id, data, event)
    echom "[vimiwiki sync] Sync done"
    execute 'checktime'
  endfunction

  function! My_exit_cb(channel,msg )
    echom "[vimiwiki sync] Sync done"
    execute 'checktime'
  endfunction

  function! My_close_cb(channel)
    " it seems this callback is necessary to really pull the repo
  endfunction


  " pull changes from git origin and sync task warrior for taskwiki
  " using asynchronous jobs
  " we should add some error handling
  function! s:pull_changes()
    if g:zettel_synced==0
      echom "[vimwiki sync] pulling changes"

      let g:zettel_synced = 1
      let gitCommand = "git -C " . g:zettel_dir . " pull --rebase origin " . g:vimwiki_sync_branch
      let s:gitCallbacksNvim = {'on_exit': "My_exit_cbNvim"}
      let s:gitCallbacksVim = {"exit_cb": "My_exit_cb", "close_cb": "My_close_cb"}

      if has("nvim")
        let gitjob = jobstart(gitCommand, s:gitCallbacksNvim)
        if g:sync_taskwarrior==1
          let taskjob = jobstart("task sync")
        endif
      else
        let gitjob = job_start(gitCommand, s:gitCallbacksVim)
        if g:sync_taskwarrior==1
          let taskjob = job_start("task sync")
        endif
      endif

    endif
  endfunction

  " push changes
  " it seems that Vim terminates before it is executed, so it needs to be
  " fixed
  function! s:push_changes()
    let gitCommand = "git -C " . g:zettel_dir . " push origin " . g:vimwiki_sync_branch
    if has("nvim")
      let gitjob = jobstart(gitCommand)
      if g:sync_taskwarrior==1
        let taskjob = jobstart("task sync")
      endif
    else
      let gitjob = job_start(gitCommand)
      if g:sync_taskwarrior==1
        let taskjob = job_start("task sync")
      endif
    endif

  endfunction

  " function! s:fetch_and_get_commit_count()
  "   let gitcommand = "git -C " . g:zettel_dir . " fetch; git -C " . g:zettel_dir . " rev-list @..@{u} --count)"
  "   let gitCallbacks = {"exit_cb": "My_exit_cb", "close_cb": "My_close_cb"}

  "   if has("nvim")
  "     let gitjob = jobstart(gitCommand)
  "   else
  "     let gitjob = job_start(gitCommand)
  "   endif

  "   if g:sync_taskwarrior==1
  "     let taskjob = jobstart("task sync")
  "   endif
  " endfunction
  "
  " TODO
  " - Refactor functions with repeated operational code that cannot change
  "   independently
  " - Issues jobstart when called from BuRead, BufEnter, FocusGained witout
  "   opening vim from scratch do not seem to work. The only auto way to sync is
  "   opening the wiki.
  " - VimLeave and FocusLost should do the same, any other event to push?
  "
  " - VimEnter, BufRead, BufEnter FocusGained:
  "   fetch from origin
  "   if (local is behind origin and there are no local changes)
  "     try automatic rebase
  "     reload file and let me know in prompt
  "   else
  "     ask what to do
  "
  "   local commits behind origin: git rev-list @..@{u} --count
  "   local changes not commited: git status --porcelain | wc -l
  "
  " - VimLeave, FocusLost
  "   if no local commits ahead origin, do nothing
  "   otherwise push to origin
  "
  "   local commits ahead origin: git rev-list @{u}..@ --count

  " sync changes at the start
  au! VimEnter * call <sid>pull_changes()
  au! BufRead * call <sid>pull_changes()
  au! BufEnter * call <sid>pull_changes()
  " auto commit changes on each file change
  au! BufWritePost * call <sid>git_action("git -C " . g:zettel_dir . " add . ; git -C " . g:zettel_dir . " commit -m \"" . strftime(g:vimwiki_sync_commit_message) . "\"")
  " push changes only on at the end
  au! VimLeave * call <sid>git_action("[ $(git -C " . g:zettel_dir . " rev-list @{u}..@ --count) = 0 ] && : || git -C " . g:zettel_dir . " push origin " . g:vimwiki_sync_branch)

  " au! FocusGained * call <sid>action("git -C " . g:zettel_dir . " fetch; [ $(git -C " . g:zettel_dir . " rev-list @..@{u} --count) = 0 ] && echo nothing to merge || echo There are remote changes to merge")
  " If we do not have local commits to push, do nothing (no-op in bash is ':' ), otherwise push.
  au! FocusLost * call <sid>git_action("[ $(git -C " . g:zettel_dir . " rev-list @{u}..@ --count) = 0 ] && : || git -C " . g:zettel_dir . " push origin " . g:vimwiki_sync_branch)
  " au! VimLeave * call <sid>push_changes()
  """""""" Simplyfied version""""
  " au! VimEnter * silent !git pull --rebase; :e
  " au! BufWritePost * silent !git add .; git commit -m "vimwiki-git-sync Auto commit + push."; git push
augroup END
