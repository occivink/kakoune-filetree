use strict;
use warnings;

my $operation = $ARGV[0];
if (not defined($operation)) {
    exit(3);
}
shift;

sub read_line_by_line {
    my $callback = $_[0];

    my $padding_size = 0;
    my @dir_stack;
    my $line_count = 0;

    my $prev_depth = 0;
    while (my $input = <STDIN>) {
        chomp($input);
        if ($input eq "") {
            last;
        } elsif ($line_count == 0) {
            if ($input ne './') {
                push(@dir_stack, substr($input, 0, -1));
            }
            $line_count = 1;
            next;
        }

        my $depth = 1;
        if ($line_count == 1) {
            # need to infer the width of the pipes, based on the first line
            if ($input !~ m/\G(└|├)((─)* )/gc) {
                exit(1);
            }
            # the pipe character is actually length '3'
            $padding_size = (length($2) - 1) / 3;
        } else {
            while ($input =~ m/\G(│| ) {$padding_size} /gco) {
                $depth += 1;
            }
            if ($input !~ m/\G(└|├)(─)* /gc) {
                exit(1);
            }
        }
        $line_count += 1;

        if ($depth <= $prev_depth) {
            my $remove = $prev_depth - $depth + 1;
            splice(@dir_stack, -$remove);
        } elsif ($depth > $prev_depth + 1) {
            # does not make sense to grow by >1 level
            exit(1);
        }
        $input =~ m|\G(.*?)(/?)$|gc;
        my $component = $1;
        my $is_dir = ($2 eq '/');
        $prev_depth = $depth;
        push(@dir_stack, $component);
        $callback->(join('/', @dir_stack), $is_dir, $line_count);
    }
}

if ($operation eq "flatten-all") {
    sub callback1 {
        print("$_[0]\n");
    }
    read_line_by_line(\&callback1);
} elsif ($operation eq "flatten-nodirs") {
    sub callback2 {
        if (not $_[1]) {
            print("$_[0]\n");
        }
    }
    read_line_by_line(\&callback2);
} elsif ($operation eq "match-buffers") {
    my %map;
    for my $buf (@ARGV) {
        $map{$buf} = 1;
    }
    sub callback3 {
        my $path = $_[0];
        if (exists($map{$path})) {
            my $line = $_[2];
            print("'$line.1,$line.1' ");
            delete $map{$path};
        }
    }
    read_line_by_line(\&callback3);
} elsif ($operation eq "process") {

    my $repetition = int($ENV{"kak_opt_filetree_indentation_level"} or 3);
    my $first = 1;

    while (my $input = <STDIN>) {
        chomp($input);
        if ($input eq "") {
            print("\n");
            last;
        }
        my $out = "";
        if ($first == 1) {
            $first = 0;
        } else {
            while ($input =~ m/\G(?:(│)\xc2\xa0\xc2\xa0|( )  ) /gc) {
                $out .= ($1 or $2) . ' ' x ($repetition + 1);
            }
            if ($input !~ m/\G(└|├)(─)─ /gc) {
                exit(1);
            }
            $out .= $1 . $2 x $repetition . ' ';
        }
        my $type = '';
        if ($input =~ m/\G\[([-sdl]).{9}\]  /gc) {
            $type = $1;
        }
        if ($type eq 'l') {
            $input =~ m/\G(.*) -> .*?$/gc;
            $out .= $1;
        } else {
            $input =~ m/\G(.*)$/gc;
            $out .= $1;
        }
        if ($type eq 'd') {
            $out .= '/';
        }
        print("$out\n");
    }

    my $last = <STDIN>;
    print("$last");

} else {
    exit(2);
}
