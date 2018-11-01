#!/usr/bin/perl
use strict;
use warnings;
use autodie qw(open close);
use utf8;
use feature qw(say);
use File::Basename qw(basename);
use List::Util     qw(first);
use Carp           qw(croak);
use constant ARRAY => ref [];
use constant HASH  => ref {};
BEGIN { # Runs at compile time
    unless (exists $ENV{PERL5LIB} and -e $ENV{PERL5LIB}) {
        # For >v5.26.0, since which @INC has become dotless
        unshift @INC, "./lib/";
    }
}
use My::Moose::Ghostscript;


#
# Outermost lexicals
#
my %prog_info = (
    titl        => basename($0, '.pl'),
    expl        => "Rasterize PS/EPS files",
    vers        => "v1.0.0",
    date_last   => "2018-09-12",
    date_first  => "2018-08-23",
    opts        => { # Command-line options
        rasterize_all => qr/-a\b/i,
        rasters       => qr/-raster=\b/i,
        dpi           => qr/-dpi=\b/i,
        nofm          => qr/-nofm\b/,     # Not parsed; for show_front_matter()
        nopause       => qr/-nopause\b/i, # Not parsed; for pause_shell()
    },
    auth        => {
        name => 'Jaewoong Jang',
        posi => 'PhD student',
        affi => 'University of Tokyo',
        mail => 'jang.comsci@gmail.com',
    },
    usage       => <<'    END_HEREDOC'
    NAME
        eps2raster - Rasterize PS/EPS files

    SYNOPSIS
        perl eps2raster.pl [file ...|-a] [-raster=format ...] [-dpi=int]
                           [-nofm] [-nopause]

    DESCRIPTION
        eps2raster lets the user easily convert PS/EPS files
        to raster images using Ghostscript.
        eps2raster interfaces Ghostscript via yet another interface
        called Ghostscript.pm:
            eps2raster.pl --- Ghostscript.pm --- Ghostscript
        where the Ghostscript.pm is a Moose class that
        the author has written for his Perl program called phitar.

    OPTIONS
        -a
            All PS/EPS files in the current working directory
            are rasterized to the designated raster format.
        -raster=format ...
            Raster formats separated by the comma (,).
            png (default)
            png_transparent
            jpg/jpeg
        -dpi=int
            Resolution. Default 300, sane range 100--600.
        -nofm
            Do not show the front matter at the beginning of the program.
        -nopause
            Do not pause the shell at the end of the program.

    EXAMPLES
        perl eps2raster.pl shibas.ps -dpi=400
        perl eps2raster.pl kuro_shiba.eps mame_shiba.eps -raster=jpg -dpi=600
        perl eps2raster.pl -a -raster=png_transparent,jpg -dpi=200 -nofm

    REQUIREMENTS
        Perl 5, Ghostscript

    SEE ALSO
        perl(1), gs(1)

    AUTHOR
        Jaewoong Jang <jang.comsci@gmail.com>

    COPYRIGHT
        Copyright (c) 2018 Jaewoong Jang

    LICENSE
        This software is available under the MIT license;
        the license information is found in 'LICENSE'.
    END_HEREDOC
);
my $gs = Ghostscript->new();
my @ps_fnames;
my $is_rasterize_all = 0;
my %your_opts = (
    rasters => ['png'], # Default
    dpi     => 300,     # Default
);


#
# Subroutine calls
#
if (@ARGV) {
    show_front_matter(\%prog_info, 'prog', 'auth')
        unless first { /$prog_info{opts}{nofm}/ } @ARGV;
    validate_argv(\%prog_info, \@ARGV);
    parse_argv();
    run_rasterization();
}
elsif (not @ARGV) {
    show_front_matter(\%prog_info, 'usage');
}
show_elapsed_real_time() unless first { /$prog_info{opts}{nofm}/    } @ARGV;
pause_shell()            unless first { /$prog_info{opts}{nopause}/ } @ARGV;


#
# Subroutine definitions
#
sub parse_argv {
    my @_argv = @ARGV;
    
    foreach (@_argv) {
        # DPI
        if (/$prog_info{opts}{dpi}/i) {
            ($your_opts{dpi} = $_) =~ s/$prog_info{opts}{dpi}//i;
        }
        
        # Raster formats
        if (/$prog_info{opts}{rasters}/i) {
            s/$prog_info{opts}{rasters}//i;
            @{$your_opts{rasters}} = (split /,/);
        }
        
        # PS/EPS filenames
        if (/[.]e?ps$/i and -e) {
            push @ps_fnames, $_;
            next;
        }
        
        # All-rasterization option
        if (/$prog_info{opts}{rasterize_all}/) {
            $is_rasterize_all = 1;
            next;
        }
    }
}


sub run_rasterization {
    if ($is_rasterize_all) {
        say "All the PS/EPS files will be rasterized.";
        push @ps_fnames, $_ for glob '*.eps';
        push @ps_fnames, $_ for glob '*.ps';
    }
    
    rm_duplicates(\@ps_fnames);
    
    foreach my $ps (@ps_fnames) {
        $gs->rasterize(
            ('dpi='.$your_opts{dpi}),
            @{$your_opts{rasters}}, # Elements as separate args
            [$ps, ''],
            'quiet',
            'epscrop',
        );
    }
}


#
# Subroutines from My::Toolset
#
sub show_front_matter {
    my $hash_ref = shift; # Arg 1: To be %_prog_info
    
    #
    # Data type validation and deref: Arg 1
    #
    my $_sub_name = join('::', (caller(0))[0, 3]);
    croak "The 1st arg to [$_sub_name] must be a hash ref!"
        unless ref $hash_ref eq HASH;
    my %_prog_info = %$hash_ref;
    
    # Subroutine optional arguments
    my(
        $is_prog,
        $is_auth,
        $is_usage,
        $is_timestamp,
        $is_no_trailing_blkline,
        $is_no_newline,
        $is_copy,
    );
    my $lead_symb    = '';
    foreach (@_) {
        $is_prog                = 1  if /prog/i;
        $is_auth                = 1  if /auth/i;
        $is_usage               = 1  if /usage/i;
        $is_timestamp           = 1  if /timestamp/i;
        $is_no_trailing_blkline = 1  if /no_trailing_blkline/i;
        $is_no_newline          = 1  if /no_newline/i;
        $is_copy                = 1  if /copy/i;
        # A single non-alphanumeric character
        $lead_symb              = $_ if /^[^a-zA-Z0-9]$/;
    }
    my $newline = $is_no_newline ? "" : "\n";
    
    #
    # Fill in the front matter array.
    #
    my @_fm;
    my $k = 0;
    my $border_len = $lead_symb ? 69 : 70;
    my %borders = (
        '+' => $lead_symb.('+' x $border_len).$newline,
        '*' => $lead_symb.('*' x $border_len).$newline,
    );
    
    # Top rule
    if ($is_prog or $is_auth) {
        $_fm[$k++] = $borders{'+'};
    }
    
    # Program info, except the usage
    if ($is_prog) {
        $_fm[$k++] = sprintf(
            "%s%s %s: %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $_prog_info{titl},
            $_prog_info{vers},
            $_prog_info{expl},
            $newline
        );
        $_fm[$k++] = sprintf(
            "%s%s%s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            'Last update:'.($is_timestamp ? '  ': ' '),
            $_prog_info{date_last},
            $newline
        );
    }
    
    # Timestamp
    if ($is_timestamp) {
        my %_datetimes = construct_timestamps('-');
        $_fm[$k++] = sprintf(
            "%sCurrent time: %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $_datetimes{ymdhms},
            $newline
        );
    }
    
    # Author info
    if ($is_auth) {
        $_fm[$k++] = $lead_symb.$newline if $is_prog;
        $_fm[$k++] = sprintf(
            "%s%s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $_prog_info{auth}{$_},
            $newline
        ) for qw(name posi affi mail);
    }
    
    # Bottom rule
    if ($is_prog or $is_auth) {
        $_fm[$k++] = $borders{'+'};
    }
    
    # Program usage: Leading symbols are not used.
    if ($is_usage) {
        $_fm[$k++] = $newline if $is_prog or $is_auth;
        $_fm[$k++] = $_prog_info{usage};
    }
    
    # Feed a blank line at the end of the front matter.
    if (not $is_no_trailing_blkline) {
        $_fm[$k++] = $newline;
    }
    
    #
    # Print the front matter.
    #
    if ($is_copy) {
        return @_fm;
    }
    elsif (not $is_copy) {
        print for @_fm;
    }
}


sub show_elapsed_real_time {
    my @opts = @_ if @_;
    
    # Parse optional arguments.
    my $is_return_copy = 0;
    my @del; # Garbage can
    foreach (@opts) {
        if (/copy/i) {
            $is_return_copy = 1;
            # Discard the 'copy' string to exclude it from
            # the optional strings that are to be printed.
            push @del, $_;
        }
    }
    my %dels = map { $_ => 1 } @del;
    @opts    = grep !$dels{$_}, @opts;
    
    # Optional strings printing
    print for @opts;
    
    # Elapsed real time printing
    my $elapsed_real_time = sprintf("Elapsed real time: [%s s]", time - $^T);
    
    # Return values
    say    $elapsed_real_time if not $is_return_copy;
    return $elapsed_real_time if     $is_return_copy;
}


sub validate_argv {
    my $hash_ref  = shift; # Arg 1: To be %_prog_info
    my $array_ref = shift; # Arg 2: To be @_argv
    my $num_of_req_argv;   # Arg 3: (Optional) Number of required args
    $num_of_req_argv = shift if defined $_[0];
    
    #
    # Data type validation and deref: Arg 1
    #
    my $_sub_name = join('::', (caller(0))[0, 3]);
    croak "The 1st arg to [$_sub_name] must be a hash ref!"
        unless ref $hash_ref eq HASH;
    my %_prog_info = %$hash_ref;
    
    #
    # Data type validation and deref: Arg 2
    #
    croak "The 2nd arg to [$_sub_name] must be an array ref!"
        unless ref $array_ref eq ARRAY;
    my @_argv = @$array_ref;
    
    #
    # Terminate the program if the number of required arguments passed
    # is not sufficient.
    # (performed only when the 3rd optional argument is given)
    #
    if ($num_of_req_argv) {
        my $num_of_req_argv_passed = grep $_ !~ /-/, @_argv;
        if ($num_of_req_argv_passed < $num_of_req_argv) {
            say $_prog_info{usage};
            say "    | You have input $num_of_req_argv_passed required args,".
                " but we need $num_of_req_argv.";
            say "    | Please refer to the usage above.";
            exit;
        }
    }
    
    #
    # Count the number of correctly passed options.
    #
    
    # Non-fnames
    my $num_of_corr_opts = 0;
    foreach my $arg (@_argv) {
        foreach my $v (values %{$_prog_info{opts}}) {
            if ($arg =~ /$v/i) {
                $num_of_corr_opts++;
                next;
            }
        }
    }
    
    # Fname-likes
    my $num_of_fnames = 0;
    $num_of_fnames = grep $_ !~ /^-/, @_argv;
    $num_of_corr_opts += $num_of_fnames;
    
    # Warn if "no" correct options have been passed.
    if ($num_of_corr_opts == 0) {
        say $_prog_info{usage};
        say "    | None of the command-line options was correct.";
        say "    | Please refer to the usage above.";
        exit;
    }
}


sub pause_shell {
    print "Press enter to exit...";
    while (<STDIN>) { last; }
}


sub rm_duplicates {
    my $array_ref = shift;
    my $_sub_name = join('::', (caller(0))[0, 3]);
    croak "The 1st arg to [$_sub_name] must be an array ref!"
        unless ref $array_ref eq ARRAY;
    
    my(%seen, @uniqued);
    @uniqued = grep !$seen{$_}++, @{$array_ref};
    
    @{$array_ref} = @uniqued;
}
#eof