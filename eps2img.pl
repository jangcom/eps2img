#!/usr/bin/env perl
use strict;
use warnings;
use autodie;
use utf8;
use Carp qw(croak);
use DateTime;
use feature qw(say);
use File::Basename qw(basename);
use constant ARRAY => ref [];
use constant HASH  => ref {};
BEGIN { unshift @INC, "./lib"; }  # @INC's become dotless since v5.26000
use My::Moose::Image;


our $VERSION = '1.06';
our $LAST    = '2020-05-03';
our $FIRST   = '2018-08-23';


#----------------------------------My::Toolset----------------------------------
sub show_front_matter {
    # """Display the front matter."""
    my $prog_info_href = shift;
    my $sub_name = join('::', (caller(0))[0, 3]);
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
    my $lead_symb = '';
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
            "%s%s v%s (%s)%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{titl},
            $prog_info_href->{vers},
            $prog_info_href->{date_last},
            $newline,
        );
        $fm[$k++] = sprintf(
            "%sPerl %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $^V,
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
            $newline,
        );
    }

    # Author info
    if ($is_auth) {
        $fm[$k++] = $lead_symb.$newline if $is_prog;
        $fm[$k++] = sprintf(
            "%s%s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{auth}{$_},
            $newline,
        ) for (
            'name',
#            'posi',
#            'affi',
            'mail',
        );
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
    my $argv_aref     = shift;
    my $cmd_opts_href = shift;
    my $sub_name = join('::', (caller(0))[0, 3]);
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
    my $argv_req_num = shift;  # (OPTIONAL) Number of required args
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
    my @del;  # Garbage can
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


sub construct_timestamps {
    # """Construct timestamps."""

    # Optional setting for the date component separator
    my $date_sep  = '';

    # Terminate the program if the argument passed
    # is not allowed to be a delimiter.
    my @delims = ('-', '_');
    if ($_[0]) {
        $date_sep = $_[0];
        my $is_correct_delim = grep $date_sep eq $_, @delims;
        croak "The date delimiter must be one of: [".join(', ', @delims)."]"
            unless $is_correct_delim;
    }

    # Construct and return a datetime hash.
    my $dt  = DateTime->now(time_zone => 'local');
    my $ymd = $dt->ymd($date_sep);
    my $hms = $dt->hms($date_sep ? ':' : '');
    (my $hm = $hms) =~ s/[0-9]{2}$//;

    my %datetimes = (
        none   => '',  # Used for timestamp suppressing
        ymd    => $ymd,
        hms    => $hms,
        hm     => $hm,
        ymdhms => sprintf("%s%s%s", $ymd, ($date_sep ? ' ' : '_'), $hms),
        ymdhm  => sprintf("%s%s%s", $ymd, ($date_sep ? ' ' : '_'), $hm),
    );

    return %datetimes;
}


sub rm_duplicates {
    # """Remove duplicate items from an array."""
    my $aref = shift;
    my $sub_name = join('::', (caller(0))[0, 3]);
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
    my %cmd_opts = %$cmd_opts_href;  # For regexes

    # Parser: Overwrite the default run options if requested by the user.
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
        # PDF version
        if (/$cmd_opts{pdfversion}/i) {
            s/$cmd_opts{pdfversion}//i;
            unless (/\b1[.][0-9]\b/) {
                printf(
                    "Incorrect pdfversion; defaulting to [%s].\n\n",
                    $run_opts_href->{pdfversion},
                );
                next;
            }
            $run_opts_href->{pdfversion} = $_;
        }
        # -dEPSCrop (Ghostscript) toggle
        if (/$cmd_opts{nocrop}/) {
            $run_opts_href->{is_nocrop} = 1;
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
    if (not @{$run_opts_href->{ps_fnames}}) {
        print "No PS/EPS file found.\n";
        return;
    }
    printf(
        "The following PS/EPS file%s will be converted:\n",
        $run_opts_href->{ps_fnames}[1] ? 's' : ''
    );
    say "[$_]" for @{$run_opts_href->{ps_fnames}};

    # Image conversion
    foreach my $ps (@{$run_opts_href->{ps_fnames}}) {
        $image->convert(
            ('raster_dpi='.$run_opts_href->{raster_dpi}),
            @{$run_opts_href->{out_fmts}},  # Elements as separate args
            [$ps, ''],
            'quiet',
            $run_opts_href->{is_nocrop} ? '' : 'epscrop',
            'pdfversion='.$run_opts_href->{pdfversion},
        );
    }

    return;
}


sub eps2img {
    # """eps2img main routine"""
    if (@ARGV) {
        my %prog_info = (
            titl       => basename($0, '.pl'),
            expl       => 'Convert PS/EPS files to raster and vector images',
            vers       => $VERSION,
            date_last  => $LAST,
            date_first => $FIRST,
            auth       => {
                name => 'Jaewoong Jang',
#                posi => '',
#                affi => '',
                mail => 'jangj@korea.ac.kr',
            },
        );
        my %cmd_opts = (  # Command-line opts
            # Supports backward compatibility
            out_fmts   => qr/-?-(o(ut)?|fmt)\s*=\s*/i,
            raster_dpi => qr/-?-(raster_)?dpi\s*=\s*/i,
            pdfversion => qr/-?-pdf(?:version)?\s*=\s*/,
            nocrop     => qr/-?-nocrop\b/i,
            nopause    => qr/-?-nopause\b/i,
            ps_all     => qr/-?-a(ll)?\b/i,
        );
        my %run_opts = (  # Program run opts
            out_fmts   => ['png', 'pdf'],
            raster_dpi => 300,
            pdfversion => '1.4',
            is_nocrop  => 0,
            is_nopause => 0,
            ps_fnames  => [],
        );

        # ARGV validation and parsing
        validate_argv(\@ARGV, \%cmd_opts);
        parse_argv(\@ARGV, \%cmd_opts, \%run_opts);

        # Notif
        show_front_matter(\%prog_info, 'prog', 'auth');

        # Main
        convert_images(\%run_opts);

        # Notif
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

    perl eps2img.pl [--fmt=format ...] [--dpi=int] [--pdfversion=version]
                    [--nocrop] [--nopause] [-a] file [file ...]

=head1 DESCRIPTION

    eps2img facilitates converting PS/EPS files to raster and vector images.
    If you want to animate the rasterized images, consider using img2ani,
    a sister program also written by the author. See "SEE ALSO" below.

=head1 OPTIONS

    --fmt=format ... (separator: ,) [default: png,pdf]
        Output formats.
        all
        png
        png_trn
        jpg/jpeg
        pdf
        svg
        emf
        wmf

    --dpi=int [default: 300]
        Raster resolutions. Sane range 100--600.

    --pdfversion=version [default: 1.4]
        The version of converted PDF files.
        The available PDF version is dependent on your Ghostscript version.

    --nocrop
        EPS files will not be cropped when rasterized.

    --nopause
        The shell will not be paused at the end of the program.

    -a, --all
        All PS/EPS files in the current working directory
        will be converted to the designated output formats.

    file (separator: ,)
        PS/EPS files to be converted.

=head1 EXAMPLES

    perl eps2img.pl kuro_shiba.eps mame_shiba.eps --fmt=jpg --dpi=600
    perl eps2img.pl -a --fmt=all
    perl eps2img.pl ./samples/tiger.eps --fmt=pdf --pdfversion=1.7

=head1 REQUIREMENTS

    Perl 5
        Moose, namespace::autoclean
    Ghostscript, Inkscape

=head1 SEE ALSO

L<eps2img on GitHub|https://github.com/jangcom/eps2img>

Want to animate the rasterized images? Check out the sister program:
L<img2ani on GitHub|https://github.com/jangcom/img2ani>

=head1 AUTHOR

Jaewoong Jang <jangj@korea.ac.kr>

=head1 COPYRIGHT

Copyright (c) 2018-2020 Jaewoong Jang

=head1 LICENSE

This software is available under the MIT license;
the license information is found in 'LICENSE'.

=cut
