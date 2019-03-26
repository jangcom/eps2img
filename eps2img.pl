#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use autodie        qw(open close);
use feature        qw(say);
use File::Basename qw(basename);
use Carp           qw(croak);
use constant ARRAY  => ref [];
use constant HASH   => ref {};
BEGIN { unshift @INC, "./lib"; } # @INC's become dotless since v5.26000
use My::Moose::Image;


our $VERSION = '1.03';
our $LAST    = '2019-03-26';
our $FIRST   = '2018-08-23';


#----------------------------------My::Toolset----------------------------------
sub show_front_matter {
    # """Display the front matter."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $prog_info_href = shift;
    croak "The 1st arg of [$sub_name] must be a hash ref!"
        unless ref $prog_info_href eq HASH;
    
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
    my @fm;
    my $k = 0;
    my $border_len = $lead_symb ? 69 : 70;
    my %borders = (
        '+' => $lead_symb.('+' x $border_len).$newline,
        '*' => $lead_symb.('*' x $border_len).$newline,
    );
    
    # Top rule
    if ($is_prog or $is_auth) {
        $fm[$k++] = $borders{'+'};
    }
    
    # Program info, except the usage
    if ($is_prog) {
        $fm[$k++] = sprintf(
            "%s%s - %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{titl},
            $prog_info_href->{expl},
            $newline,
        );
        $fm[$k++] = sprintf(
            "%sVersion %s (%s)%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{vers},
            $prog_info_href->{date_last},
            $newline,
        );
    }
    
    # Timestamp
    if ($is_timestamp) {
        my %datetimes = construct_timestamps('-');
        $fm[$k++] = sprintf(
            "%sCurrent time: %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $datetimes{ymdhms},
            $newline
        );
    }
    
    # Author info
    if ($is_auth) {
        $fm[$k++] = $lead_symb.$newline if $is_prog;
        $fm[$k++] = sprintf(
            "%s%s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{auth}{$_},
            $newline
        ) for qw(name posi affi mail);
    }
    
    # Bottom rule
    if ($is_prog or $is_auth) {
        $fm[$k++] = $borders{'+'};
    }
    
    # Program usage: Leading symbols are not used.
    if ($is_usage) {
        $fm[$k++] = $newline if $is_prog or $is_auth;
        $fm[$k++] = $prog_info_href->{usage};
    }
    
    # Feed a blank line at the end of the front matter.
    if (not $is_no_trailing_blkline) {
        $fm[$k++] = $newline;
    }
    
    #
    # Print the front matter.
    #
    if ($is_copy) {
        return @fm;
    }
    else {
        print for @fm;
        return;
    }
}


sub validate_argv {
    # """Validate @ARGV against %cmd_opts."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $argv_aref     = shift;
    my $cmd_opts_href = shift;
    
    croak "The 1st arg of [$sub_name] must be an array ref!"
        unless ref $argv_aref eq ARRAY;
    croak "The 2nd arg of [$sub_name] must be a hash ref!"
        unless ref $cmd_opts_href eq HASH;
    
    # For yn prompts
    my $the_prog = (caller(0))[1];
    my $yn;
    my $yn_msg = "    | Want to see the usage of $the_prog? [y/n]> ";
    
    #
    # Terminate the program if the number of required arguments passed
    # is not sufficient.
    #
    my $argv_req_num = shift; # (OPTIONAL) Number of required args
    if (defined $argv_req_num) {
        my $argv_req_num_passed = grep $_ !~ /-/, @$argv_aref;
        if ($argv_req_num_passed < $argv_req_num) {
            printf(
                "\n    | You have input %s nondash args,".
                " but we need %s nondash args.\n",
                $argv_req_num_passed,
                $argv_req_num,
            );
            print $yn_msg;
            while ($yn = <STDIN>) {
                system "perldoc $the_prog" if $yn =~ /\by\b/i;
                exit if $yn =~ /\b[yn]\b/i;
                print $yn_msg;
            }
        }
    }
    
    #
    # Count the number of correctly passed command-line options.
    #
    
    # Non-fnames
    my $num_corr_cmd_opts = 0;
    foreach my $arg (@$argv_aref) {
        foreach my $v (values %$cmd_opts_href) {
            if ($arg =~ /$v/i) {
                $num_corr_cmd_opts++;
                next;
            }
        }
    }
    
    # Fname-likes
    my $num_corr_fnames = 0;
    $num_corr_fnames = grep $_ !~ /^-/, @$argv_aref;
    $num_corr_cmd_opts += $num_corr_fnames;
    
    # Warn if "no" correct command-line options have been passed.
    if (not $num_corr_cmd_opts) {
        print "\n    | None of the command-line options was correct.\n";
        print $yn_msg;
        while ($yn = <STDIN>) {
            system "perldoc $the_prog" if $yn =~ /\by\b/i;
            exit if $yn =~ /\b[yn]\b/i;
            print $yn_msg;
        }
    }
    
    return;
}


sub show_elapsed_real_time {
    # """Show the elapsed real time."""
    
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
    @opts = grep !$dels{$_}, @opts;
    
    # Optional strings printing
    print for @opts;
    
    # Elapsed real time printing
    my $elapsed_real_time = sprintf("Elapsed real time: [%s s]", time - $^T);
    
    # Return values
    if ($is_return_copy) {
        return $elapsed_real_time;
    }
    else {
        say $elapsed_real_time;
        return;
    }
}


sub pause_shell {
    # """Pause the shell."""
    
    my $notif = $_[0] ? $_[0] : "Press enter to exit...";
    
    print $notif;
    while (<STDIN>) { last; }
    
    return;
}


sub rm_duplicates {
    # """Remove duplicate items from an array."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $aref = shift;
    
    croak "The 1st arg of [$sub_name] must be an array ref!"
        unless ref $aref eq ARRAY;
    
    my(%seen, @uniqued);
    @uniqued = grep !$seen{$_}++, @$aref;
    @$aref = @uniqued;
    
    return;
}
#-------------------------------------------------------------------------------


sub parse_argv {
    # """@ARGV parser"""
    
    my(
        $argv_aref,
        $cmd_opts_href,
        $run_opts_href,
    ) = @_;
    my %cmd_opts = %$cmd_opts_href; # For regexes
    
    # Parser: Overwrite default run options if requested by the user.
    my $field_sep = ',';
    foreach (@$argv_aref) {
        # PS/EPS filenames
        if (/[.]e?ps$/i and -e) {
            push @{$run_opts_href->{ps_fnames}}, $_;
        }
        
        # Convert all PS/EPS files in the CWD.
        if (/$cmd_opts{ps_all}/) {
            push @{$run_opts_href->{ps_fnames}}, glob '*.eps *.ps';
        }
        
        # Output formats
        if (/$cmd_opts{out_fmts}/i) {
            s/$cmd_opts{out_fmts}//i;
            @{$run_opts_href->{out_fmts}} = split /$field_sep/;
        }
        
        # Raster DPI
        if (/$cmd_opts{raster_dpi}/i) {
            ($run_opts_href->{raster_dpi} = $_) =~ s/$cmd_opts{raster_dpi}//i;
        }
        
        # The front matter won't be displayed at the beginning of the program.
        if (/$cmd_opts{nofm}/) {
            $run_opts_href->{is_nofm} = 1;
        }
        
        # The shell won't be paused at the end of the program.
        if (/$cmd_opts{nopause}/) {
            $run_opts_href->{is_nopause} = 1;
        }
    }
    rm_duplicates($run_opts_href->{ps_fnames});
    
    return;
}


sub convert_images {
    # """Run the convert method of Image."""
    
    my $run_opts_href = shift;
    my $image = Image->new();
    
    # Notification
    printf(
        "The following PS/EPS file%s will be converted:\n",
        $run_opts_href->{ps_fnames}[1] ? 's' : ''
    );
    say "[$_]" for @{$run_opts_href->{ps_fnames}};
    
    # Image conversion
    foreach my $ps (@{$run_opts_href->{ps_fnames}}) {
        $image->convert(
            ('raster_dpi='.$run_opts_href->{raster_dpi}),
            @{$run_opts_href->{out_fmts}}, # Elements as separate args
            [$ps, ''],
            'quiet',
            'epscrop',
        );
    }
    
    return;
}


sub eps2img {
    # ""eps2img main routine"
    
    if (@ARGV) {
        my %prog_info = (
            titl       => basename($0, '.pl'),
            expl       => 'Convert PS/EPS files to raster and vector images',
            vers       => $VERSION,
            date_last  => $LAST,
            date_first => $FIRST,
            auth       => {
                name => 'Jaewoong Jang',
                posi => 'PhD student',
                affi => 'University of Tokyo',
                mail => 'jan9@korea.ac.kr',
            },
        );
        my %cmd_opts = ( # Command-line opts
            ps_all     => qr/-?-a(ll)?/i,
            out_fmts   => qr/-?-o(ut)?\s*=\s*/i,
            raster_dpi => qr/-?-(raster_)?dpi\s*=\s*/i,
            nofm       => qr/-?-nofm/i,
            nopause    => qr/-?-nopause/i,
        );
        my %run_opts = ( # Program run opts
            ps_fnames  => [],
            out_fmts   => ['png'],
            raster_dpi => 300,
            is_nofm    => 0,
            is_nopause => 0,
        );
        
        # ARGV validation and parsing
        validate_argv(\@ARGV, \%cmd_opts);
        parse_argv(\@ARGV, \%cmd_opts, \%run_opts);
        
        # Notification - beginning
        show_front_matter(\%prog_info, 'prog', 'auth', 'no_trailing_blkline')
            unless $run_opts{is_nofm};
        
        # Main
        convert_images(\%run_opts);
        
        # Notification - end
        show_elapsed_real_time("\n");
        pause_shell() unless $run_opts{is_nopause};
    }
    
    system("perldoc \"$0\"") if not @ARGV;
    
    return;
}


eps2img();
__END__

=head1 NAME

eps2img - Convert PS/EPS files to raster and vector images

=head1 SYNOPSIS

    perl eps2img.pl [ps_file ...|-all] [-out=format ...] [-raster_dpi=int]
                    [-nofm] [-nopause]

=head1 DESCRIPTION

    eps2img wraps Ghostscript and Inkscape to ease
    converting PS/EPS files to raster and vector images.
    eps2img uses Image.pm, a Moose class written by the author:
        eps2img.pl --- Image.pm --- Ghostscript, Inkscape

=head1 OPTIONS

    ps_file ...
        PS/EPS files to be converted. Multiple files should be
        separated by the space character.

    -all|-a
        All PS/EPS files in the current working directory
        will be converted to the designated output formats.

    -out|-o=format ...
        Output image formats. Multiple formats should be
        separated by the comma (,).
        all     (all formats below)
        png     (default)
        png_trn (transparent)
        jpg/jpeg
        pdf
        emf
        wmf

    -raster_dpi|-dpi=int
        Raster (.png and .jpg) resolution.
        Default 300, sane range 100--600.

    -nofm
        The front matter will not be displayed at the beginning of the program.

    -nopause
        The shell will not be paused at the end of the program.
        Use it for a batch run.

=head1 EXAMPLES

    perl eps2img.pl ./examples/tiger.ps -raster_dpi=400
    perl eps2img.pl kuro_shiba.eps mame_shiba.eps -o=jpg -raster_dpi=600
    perl eps2img.pl -a -o=png_trn,jpg -raster_dpi=200 -nofm
    perl eps2img.pl -a -o=all

=head1 REQUIREMENTS

    Perl 5
        Moose, namespace::autoclean
    Ghostscript, Inkscape

=head1 SEE ALSO

perl(1), moose(3), gs(1), inkscape(1)

=head1 AUTHOR

Jaewoong Jang <jan9@korea.ac.kr>

=head1 COPYRIGHT

Copyright (c) 2018-2019 Jaewoong Jang

=head1 LICENSE

This software is available under the MIT license;
the license information is found in 'LICENSE'.

=cut
