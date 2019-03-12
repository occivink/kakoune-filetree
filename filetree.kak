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

def -hidden filetree-buflist-to-regex -params ..1 %{
    try %{
        # eval to avoid using a shell scope if *filetree* is not open
        eval -buffer *filetree* %{
            set-option buffer filetree_open_files %sh{
                exclude="$1"
                eval set -- "$kak_buflist"
                first=1
                printf '^\./('
                for buffer do
                    if [ "$buffer" = "$exclude" ]; then
                        continue
                    fi
                    if [ "$first" -eq 1 ]; then
                        first=0
                    else
                        printf '|'
                    fi
                    printf "%s%s%s" '\Q' "$buffer" '\E'
                done
                printf ')$'
            }
        }
    }
}

hook global BufCreate .* %{ filetree-buflist-to-regex }
hook global BufClose  .* %{ filetree-buflist-to-regex %val{bufname} }

def -hidden filetree-open-files %{
    exec '<a-s>'
    eval -draft -itersel %{
        exec ';<a-x>H'
        # don't -existing, so that this can be used to create files
        eval -draft %{ edit %reg{.} }
    }
    eval -save-regs 'f' %{
        exec '<space>;<a-x>H'
        reg f %reg{.}
        eval -try-client %opt{jumpclient} %{ buffer %reg{f} }
    }
    try %{ focus %opt{jumpclient} }
}
