declare-option -hidden str filetree_open_files

declare-option str filetree_find_cmd 'find .  -not -type d -and -not -path "*/\.*"'

set-face global FileTreeOpenFiles black,yellow
set-face global FileTreeDirName rgb:606060,default
set-face global FileTreeFileName default,default

define-command filetree -docstring "
Open a scratch buffer with all paths returned by the specified command.
Buffers to the files can be opened using <ret>.
" %{
    eval %{
        try %{ delete-buffer *filetree* }
        set-register / "^\Q./%val{bufname}\E$"
        edit -scratch *filetree*
        set-register '|' %opt{filetree_find_cmd}
        exec '<a-!><ret>'
        exec 'ged'
        # center view on previous file
        try %{ exec '/<ret>vc' }
        addhl buffer dynregex '%opt{filetree_open_files}' 0:FileTreeOpenFiles
        addhl buffer regex '^([^\n]+/)([^/\n]+)$' 1:FileTreeDirName 2:FileTreeFileName
        map buffer normal <ret> :filetree-open-files<ret>
    }
}

define-command -hidden filetree-buflist-to-regex -params ..1 %{
    try %{
        # eval to avoid using a shell scope if *filetree* is not open
        eval -buffer *filetree* %{
            set-option buffer filetree_open_files "%sh{
                r=$(
                    printf '%s\n' \"$kak_buflist\" | tr : '\n' | while read -r i; do
                        [ \"$i\" != \"$1\" ] && printf \"%s%s%s\" \"\Q\" \"$i\" \"\E|\"
                    done
                )
                # strip trailing |
                printf \"^\./(%s)$\" \"${r%|}\"
            }"
        }
    }
}

hook global BufCreate .* %{ filetree-buflist-to-regex }
hook global BufClose  .* %{ filetree-buflist-to-regex %val{hook_param} }

define-command -hidden filetree-open-files %{
    eval -draft -itersel %{
        exec ';<a-x>H'
        # don't -existing, so that this can be used to create files
        eval -draft "edit \"%reg{.}\""
    }
    exec '<space>;<a-x>H'
    eval -try-client %opt{jumpclient} %{ buffer %reg{.} }
    try %{ focus %opt{jumpclient} }
}
