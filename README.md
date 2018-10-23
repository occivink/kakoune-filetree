# kakoune-filetree

[Kakoune](http://kakoune.org) plugin to view and navigate files.

[![Demo](https://asciinema.org/a/160945.png)](https://asciinema.org/a/160945)

## Setup

Add `filetree.kak` to your `autoload` directory: `~/.config/kak/autoload/`, or source it manually.

## Usage

Simply call `:filetree`. A new buffer will be open with all files found below (relative to Kakoune’s directory), one by line. The files that are open in buffers are highlighted with a special face.

From the `*filetree*` buffer, you can open files by pressing <kbd>Return</kbd>. You can also use this to create files: enter a new filename in the buffer, and open it with <kbd>Return</kbd>.

## Customization

The option `filetree_find_cmd` is the command that is run to generate the list of files. It defaults to `find . -not -type d -and -not -path "*/.*"` (only print files, exclude hidden ones).

There are a few faces that can be changed:
* `FileTreeOpenFiles`: Used for files that have an open buffers (`black,yellow`)
* `FileTreeDirName`: Used for the directory part of filepaths (`rgb:606060,default`)
* `FileTreeFileName`: Used for the basename of filepaths (`default,default`)

If you want `:filetree` to take a directory as argument, I suggest writing a thin wrapper that sets the option before calling `:filetree`. Since the option can be set to *anything* this is not something that can be added to the script in a generic way.

## License

[Unlicense](http://unlicense.org)
