#!/usr/bin/perl
use strict;
use warnings;
use autodie qw(open close);
use utf8;
use feature qw(say);
use File::Basename qw(basename);
BEGIN { # Runs at compile time
    chomp(my $onedrive_path = `echo %OneDrive%`);
    unless (exists $ENV{PERL5LIB} and -e $ENV{PERL5LIB}) {
        my %lib_paths = (
            cwd      => ".", # @INC's become dotless since v5.26000
            onedrive => "$onedrive_path/cs/langs/perl",
        );
        unshift @INC, "$lib_paths{$_}/lib" for keys %lib_paths;
    }
}
use My::Toolset qw(:coding :rm);
use My::Moose::Image;


our $VERSION = '1.02';
our $LAST    = '2019-03-23';
our $FIRST   = '2018-08-23';


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
    # Run the convert method of Image.
    
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
            titl        => basename($0, '.pl'),
            expl        => 'Convert PS/EPS files to raster and vector images',
            vers        => $VERSION,
            date_last   => $LAST,
            date_first  => $FIRST,
            auth        => {
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
        printf(
            "%s version: %s (%s)\n",
            $My::Toolset::PACKNAME,
            $My::Toolset::VERSION,
            $My::Toolset::LAST,
        );
        printf(
            "%s version: %s (%s)\n",
            $Image::PACKNAME,
            $Image::VERSION,
            $Image::LAST,
        );
        
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
