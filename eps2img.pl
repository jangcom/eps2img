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
use My::Toolset qw(:coding :rm);
use My::Moose::Image;
our $VERSION = '1.07';
our $LAST    = '2021-10-12';
our $FIRST   = '2018-08-23';


sub parse_argv {
    # """@ARGV parser"""
    my (
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

Copyright (c) 2018-2021 Jaewoong Jang

=head1 LICENSE

This software is available under the MIT license;
the license information is found in 'LICENSE'.

=cut
