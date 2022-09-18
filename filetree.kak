declare-option -docstring "Name of the client in which all source code jumps will be executed" str jumpclient
declare-option -docstring "name of the client in which utilities display information" str toolsclient

declare-option -docstring "Command used to populate the *filetree* buffer" \
    str filetree_find_cmd 'find . -not -type d -and -not -path "*/.*"'

declare-option -hidden str filetree_directory
declare-option -hidden regex filetree_open_files

face global FileTreeOpenFiles black,yellow
face global FileTreeDirName rgb:606060,default
face global FileTreeFileName default,default

define-command filetree-switch-or-start -docstring "
Switch to the *filetree* buffer.
If the *filetree* buffer does not exist, or the kakoune directory has changed,
it is generated from scratch.
" %{
    try %{
        eval -try-client %opt{toolsclient} %{
            buffer *filetree*
            eval %sh{ [ "$kak_opt_filetree_directory" != "$(pwd)" ] && printf 'fail' }
        }
    } catch %{
        filetree
    }
}

define-command filetree-edit -params 1.. -docstring "
Edit the specified file. The completions are provided by the *filetree* buffer.
" %{
    edit %arg{@}
}

try %{ # complete-command has not yet been released => try block
    complete-command -menu filetree-edit shell-script-candidates %{
        echo "try %{ eval -buffer *filetree* %{ write '$kak_response_fifo' } } catch %{ echo -to-file '$kak_response_fifo' '' }" > "$kak_command_fifo"
        cat "$kak_response_fifo"
    }
}

define-command filetree -docstring "
Open a scratch *filetree* buffer with all paths returned by the specified command.
Buffers to the files can be opened using <ret>.
" %{
    eval -try-client %opt{toolsclient} -save-regs t %{
        set-register t %sh{
            fifo=$(mktemp -u)
            mkfifo "$fifo"
            (eval "$kak_opt_filetree_find_cmd" > "$fifo") < /dev/null > /dev/null 2>&1 &
            printf '%s' "$fifo"
        }
        try %{ delete-buffer *filetree* }
        edit -fifo %reg{t} *filetree*
        set-option buffer filetree_directory %sh{ pwd }
        # no need for complex escaping, since 'mktemp' should generate a safe path
        hook -always -once buffer BufCloseFifo .* "nop %%sh{ rm '%reg{t}' }; exec ged"
        add-highlighter buffer/ dynregex '%opt{filetree_open_files}' 0:FileTreeOpenFiles
        add-highlighter buffer/ regex '^([^\n]+/)([^/\n]+)$' 1:FileTreeDirName 2:FileTreeFileName
        map buffer normal <ret> ': filetree-open-files<ret>'
    }
}

define-command -hidden filetree-buflist-to-regex -params ..1 %{
    try %{
        # eval to avoid using a shell scope if *filetree* is not open
        eval -buffer *filetree* %{
            set-option buffer filetree_open_files %sh{
                exclude="$1"
                eval set -- "$kak_quoted_buflist"
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

define-command -hidden filetree-open-files %{
    exec '<a-s>'
    eval -draft -itersel %{
        exec ';xH'
        # don't -existing, so that this can be used to create files
        eval -draft %{ edit %reg{.} }
    }
    eval -save-regs 'f' %{
        exec ',;xH'
        set-register f %reg{.}
        eval -try-client %opt{jumpclient} buffer '%reg{f}'
    }
    try %{ focus %opt{jumpclient} }
}
