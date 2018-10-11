decl -docstring "Name of the client in which all source code jumps will be executed" str jumpclient
decl str filetree_find_cmd 'find . -not -type d -and -not -path "*/\.*"'

decl -hidden str filetree_open_files

face global FileTreeOpenFiles black,yellow
face global FileTreeDirName rgb:606060,default
face global FileTreeFileName default,default

def filetree -docstring "
Open a scratch buffer with all paths returned by the specified command.
Buffers to the files can be opened using <ret>.
" %{
    eval %sh{
        out=$(mktemp --directory)
        fifo=$out/fifo
        mkfifo $fifo
        (eval "$kak_opt_filetree_find_cmd" > $fifo) < /dev/null > /dev/null 2>&1 &
        echo "
            try %{ delete-buffer *filetree* }
            edit -fifo $fifo *filetree*
            # Center view on previous file
            hook -once window NormalIdle '' %{ eval -save-regs / %{
                reg / %{^\Q./$kak_bufname\E$}
                try %{ exec /<ret> }
            }}
            hook -always -once buffer BufCloseFifo '' %{ nop %sh{ rm $out/fifo; rmdir $out } }
        "
    }
    addhl buffer/ dynregex '%opt{filetree_open_files}' 0:FileTreeOpenFiles
    addhl buffer/ regex '^([^\n]+/)([^/\n]+)$' 1:FileTreeDirName 2:FileTreeFileName
    map buffer normal <ret> :filetree-open-files<ret>
}

def -hidden filetree-buflist-to-regex -params 0..1 %{
    # Try eval to avoid using a shell scope if *filetree* is not open
    try %{ eval -buffer *filetree* %{
        set buffer filetree_open_files %sh{
            discarded_bufname=$1
            eval "set -- $kak_buflist"
            for bufname in "$@"; do
                test "$bufname" != "$discarded_bufname" &&
                    printf '^\\Q./%s\\E$\n' "$bufname"
            done |
            paste --serial --delimiters '|'
        }
    }}
}

hook global BufCreate .* %{ filetree-buflist-to-regex }
hook global BufClose  .* %{ filetree-buflist-to-regex %val{hook_param} }

def -hidden filetree-open-files %{
    exec '<a-s>'
    eval -draft -itersel %{
        exec ';<a-x>H'
        # Don’t -existing, so that this can be used to create files
        eval -draft %{ edit %reg{.} }
    }
    exec '<space>;<a-x>H'
    eval -try-client %opt{jumpclient} %{ buffer %reg{.} }
    try %{ focus %opt{jumpclient} }
}
