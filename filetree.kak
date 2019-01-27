decl -docstring "Name of the client in which all source code jumps will be executed" str jumpclient
decl str filetree_find_cmd 'find . -not -type d -and -not -path "*/.*"'

decl -hidden regex filetree_open_files

face global FileTreeOpenFiles black,yellow
face global FileTreeDirName rgb:606060,default
face global FileTreeFileName default,default

def filetree -docstring "
Open a scratch buffer with all paths returned by the specified command.
Buffers to the files can be opened using <ret>.
" %{
    eval -save-regs t %{
        reg t %sh{
            fifo=$(mktemp -u)
            mkfifo "$fifo"
            (eval "$kak_opt_filetree_find_cmd" > "$fifo") < /dev/null > /dev/null 2>&1 &
            printf '%s' "$fifo"
        }
        try %{ delete-buffer *filetree* }
        edit -fifo %reg{t} *filetree*
        hook -always -once buffer BufCloseFifo .* "nop %%sh{ rm '%reg{t}' }; exec ged"
        addhl buffer/ dynregex '%opt{filetree_open_files}' 0:FileTreeOpenFiles
        addhl buffer/ regex '^([^\n]+/)([^/\n]+)$' 1:FileTreeDirName 2:FileTreeFileName
        map buffer normal <ret> ': filetree-open-files<ret>'
    }
}

def -hidden filetree-buflist-to-regex -params 0..1 %{
    # try to avoid using a shell scope if *filetree* is not open
    try %{ eval -buffer *filetree* %{
        set buffer filetree_open_files %sh{
            discarded_bufname=$1
            eval set -- "$kak_buflist"
            first=1
            for bufname do
                if [ "$bufname" != "$discarded_bufname" ]; then
                    if [ "$first" -eq 1 ]; then
                        first=0
                    else
                        printf '|'
                    fi
                    # \E is not foolproof as a buffer name may contain it, unfortunately
                    # ideally we'd escape each regex special character but that's difficult
                    printf '%s%s%s' '^\Q' "./${bufname}" '\E$'
                fi
            done
        }
    }}
}

hook global BufCreate .* %{ filetree-buflist-to-regex }
hook global BufClose  .* %{ filetree-buflist-to-regex %val{hook_param} }

def -hidden filetree-open-files %{
    exec '<a-s>'
    eval -draft -itersel %{
        exec ';<a-x>H'
        # don't -existing, so that this can be used to create files
        eval -draft %{ edit %reg{.} }
    }
    exec '<space>;<a-x>H'
    eval -try-client %opt{jumpclient} %{ buffer %reg{.} }
    try %{ focus %opt{jumpclient} }
}
