#
# Moose class for Image
#
# Copyright (c) 2018-2023 Jaewoong Jang
# This script is available under the MIT license;
# the license information is found in 'LICENSE'.
#
package Image;

use Moose;
use namespace::autoclean;
use autodie;
use feature qw(say state);
use List::Util qw(first);
use constant ARRAY => ref [];
use constant HASH  => ref {};

our $PACKNAME = __PACKAGE__;
our $VERSION  = '1.06';
our $LAST     = '2023-11-14';
our $FIRST    = '2018-08-19';

has 'Cmt' => (
    is      => 'ro',
    isa     => 'Image::Cmt',
    lazy    => 1,
    default => sub { Image::Cmt->new() },
);

has 'Ctrls' => (
    is      => 'ro',
    isa     => 'Image::Ctrls',
    lazy    => 1,
    default => sub { Image::Ctrls->new() },
);

has 'FileIO' => (
    is      => 'ro',
    isa     => 'Image::FileIO',
    lazy    => 1,
    default => sub { Image::FileIO->new() },
);

#
# Executable settings
#
my %_exe_settings = (  # (key) attribute => (val) default
    exes => sub {
        {
            # Ghostscript executables depend on the platforms and integer bits.
            # Unix-like        => gs
            # 32-bit gs, MSWin => gswin32c (gswin32 for GUI)
            # 64-bit gs, MSWin => gswin64c (gswin64 for GUI)
            gs       => 'gs',
            inkscape => 'inkscape',
        }
    },
    path_to_exes => sub{
        {
            gs       => '',
            inkscape => '',
        }
    },
);

has $_ => (
    traits  => ['Hash'],
    is      => 'ro',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    default => $_exe_settings{$_},
    handles => {
        'set_'.$_ => 'set',
    },
) for keys %_exe_settings;

#
# Ghostscript command-line options
#
my %_gs_cmd_opts = (
    interaction_params => sub {  # use.htm#Interaction-related_parameters
        {
            safer      => '-dSAFER',
            batch      => '-dBATCH',
            nopause    => '-dNOPAUSE',
            quiet      => '-dQUIET',
            epscrop    => '-dEPSCrop',
            epsfitpage => '-dEPSFitPage',
            usecropbox => '-dUseCropBox',
            # Combos
            trio       => '-dSAFER -dBATCH -dNOPAUSE',
            quartet    => '-dSAFER -dBATCH -dNOPAUSE -dQUIET',
            quintet    => '-dSAFER -dBATCH -dNOPAUSE -dQUIET -dEPSCrop',
        }
    },
    pdfversion => sub {  # Added 2019-04-23
        {
            key => '-dCompatibilityLevel',
            val => '1.4',
        }
    },
    paper_sizes => sub {  # use.htm#Known_paper_sizess
        {
            usletter => 'letter',  # 8.5" by 11.0"; the default
            a4       => 'a4',      # 8.3" by 11.7"
        }
    },
    s_devices => sub {  # Devices.htm
        {
            # I. Image file formats
            # I-1. Portable Network Graphics (PNG)
            png16m   => 'png16m',    # 24-bit RGB
            pnggray  => 'pnggray',   #  8-bit grayscale
            pngalpha => 'pngalpha',  # 32-bit RGBA; transparency provided
            # I-2. Joint Photographic Experts Group (JPEG)
            jpg      => 'jpeg',
            jpggray  => 'jpeggray',
            # II. High level formats
            # I-1. Portable Document Format (PDF)
            pdfwrite => 'pdfwrite',
            # III. Misc.
            bbox     => 'bbox',  # Read in bbox info
        }
    },
);

has $_ => (
    is      => 'ro',
    lazy    => 1,
    default => $_gs_cmd_opts{$_},
) for keys %_gs_cmd_opts;

# Directories containing to-be-animated raster images
has 'rasters_dirs' => (
    traits  => ['Array'],
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub { [] },
    handles => {
        add_rasters_dirs  => 'push',
        uniq_rasters_dirs => 'uniq',
    },
);

#
# Inkscape command-line options
#
my %_inkscape_cmd_opts = (
    inkscape_export => sub {
        {
            # https://inkscape.org/doc/inkscape-man.html#OPTIONS
            svg => '-l',  # Alt: --export-plain-svg
            emf => '-M',  # Alt: --export-emf
            wmf => '-m',  # Alt: --export-wmf
        }
    },
);

has $_ => (
    traits  => ['Hash'],
    is      => 'ro',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    default => $_inkscape_cmd_opts{$_},
    handles => {
        'set_'.$_ => 'set',
    },
) for keys %_inkscape_cmd_opts;


sub convert {
    # """Convert PostScript files to raster and vector images."""

    #
    # Note on subroutine generalization
    #
    # 2018-12-24
    # > Class name changed: Ghostscript.pm --> Image.pm
    # > In addition to Ghostscript, Inkscape is used to
    #   convert .eps files to .emf and .wmf files.
    #
    # 2018-08-23
    # > Initially created for phitar, this routine has now been generalized.
    #   Use eps2img for rasterizing PS/EPS files.
    #
    my $self = shift;

    # Determine the roles of passed arguments.
    my @fname_flag_pairs;  # Pairs of a PS/EPS filename and an optional flag
    my @your_args;         # User-provided arguments
    my %phitar_hooks;      # phitar-only
    foreach (@_) {
        push @fname_flag_pairs, $_ if     ref $_ eq ARRAY;
        push @your_args,        $_ if not ref $_ eq ARRAY;
        %phitar_hooks = %{$_}      if     ref $_ eq HASH;
    }
    my($bname, $out_dir);             # Used for directory naming (phitar)
    my($converted_fname, $ps_fname);  # Storages of an output and an input
    my %has_been_used = map { $_ => 0 } qw (gs inkscape);  # Notif purposes

    # Routine execution options - General
    my @your_interaction_params;
    my $is_multipage      = 0;
    my $is_crop           = grep $_ =~ /^crop/i, @your_args;
    my $is_legacy_epscrop = grep $_ =~ /^legacy_epscrop/i, @your_args;
    push @your_interaction_params,
        $self->interaction_params->{epscrop} if $is_legacy_epscrop;
    my $is_rotate         = 0;
    my $is_verbose        = grep $_ =~ /^verbose/i, @your_args;
    foreach (@your_args) {
        #
        # Ghostscript
        #
        $self->Ctrls->set_raster_dpi((split /=/)[1]) if /^(raster_)?dpi\s*=/i;
        $self->Ctrls->set_png_switch('on')           if /^(png|all)$/i;
        $self->Ctrls->set_png_trn_switch('on')       if /^(png_trn|all)$/i;
        $self->Ctrls->set_jpg_switch('on')           if /^(jpe?g|all)$/i;
        $self->Ctrls->set_pdf_switch('on')           if /^(pdf|all)$/i;
        $has_been_used{gs} = 1 if(
            $self->Ctrls->png_switch        =~ /on/i
            or $self->Ctrls->png_trn_switch =~ /on/i
            or $self->Ctrls->jpg_switch     =~ /on/i
            or $self->Ctrls->pdf_switch     =~ /on/i
        );

        push @your_interaction_params,
            $self->interaction_params->{quiet}      if /^quiet$/i;
        push @your_interaction_params,
            $self->interaction_params->{epsfitpage} if /^epsfitpage$/i;
        if (/^pdfversion\s*=\s*/i) {
            ($self->pdfversion->{val} = $_) =~ s/pdfversion\s*=\s*//;
            push @your_interaction_params, sprintf(
                "%s=%s",
                $self->pdfversion->{key},
                $self->pdfversion->{val},
            );
        }
        $is_rotate = 1 if /^rotate$/i;

        #
        # Inkscape
        #
        $self->Ctrls->set_svg_switch('on') if /^(svg|all)$/i;
        $self->Ctrls->set_emf_switch('on') if /^(emf|all)$/i;
        $self->Ctrls->set_wmf_switch('on') if /^(wmf|all)$/i;
        $has_been_used{inkscape} = 1 if $self->Ctrls->svg_switch =~ /on/i;
        $has_been_used{inkscape} = 1 if $self->Ctrls->emf_switch =~ /on/i;
        $has_been_used{inkscape} = 1 if $self->Ctrls->wmf_switch =~ /on/i;
    }
    $has_been_used{gs_and_inkscape} =
        $has_been_used{gs} + $has_been_used{inkscape};

    # [Ghostscript] Execution options - "phitar" only
    my $is_phitar  = 0;
    $is_phitar = 1 if (split /\/|\\/, (caller)[1])[-1] =~ /phitar([.]pl)?/i;
    $is_rotate = 1 if (
        $is_phitar
        and $phitar_hooks{orientation}
        and $phitar_hooks{orientation} =~ /\bland\b/i
    );

    #
    # [Ghostscript] Storages for command-line execution
    #
    my($other_than_the_trio, $the_cmd);
    if ($is_phitar) {
        $other_than_the_trio = sprintf(
            "%s%s",
            # -dUseCropBox is necessary to crop the whitespace of
            # images rasterized from ANGEL-generated PS files.
            # https://stackoverflow.com/questions/
            # 38171343/ghostscript-converting-pdf-to-png-with-wrong-output-size
            $self->interaction_params->{usecropbox},
            $self->Ctrls->mute =~ /on/i ?
                ' '.$self->interaction_params->{quiet} : '',
        );
    }
    if ($is_crop and not $is_legacy_epscrop) {
        $other_than_the_trio = sprintf(
            "%s %s",
            $self->interaction_params->{usecropbox},
            "@your_interaction_params",
        );
    }
    else {
        $other_than_the_trio = "@your_interaction_params";
    }

    # For regexes
    my $fname_sep     = $self->FileIO->fname_sep;
    my $dir_delim     = $self->FileIO->path_delim;
    my $env_var_delim = $self->FileIO->env_var_delim;
    my @path_env_vars;

    # Construct comment borders.
    $self->Cmt->set_borders(
        leading_symb => $self->Cmt->symb,
        border_symbs => ['*', '=', '-'],
    );

    #
    # Examine environment variable settings and acquire
    # the names of the executables.
    # For Ghostscript running on MS Windows,
    # the name of the executable varies also with
    # the integer-bit of the installation.
    #
    # The conditional block is executed only once "during the program run"
    # by using "a state variable".
    #
    # [Ghostscript]
    # use.htm#o_option
    # use.htm#Summary_of_environment_variables
    #
    state $chk_env_var = 1;  # NOT reinitialized at the next call
    if ($chk_env_var == 1 and $^O =~ /MSWin32/i) {
        #
        # Ghostscript
        #

        # Path to the executables (/bin)
        # (i) When the env var has already been set:
        if ($ENV{PATH} =~ /gs(?:[0-9.]+)?[\/\\]bin/i) {
            @path_env_vars = split /$env_var_delim/, $ENV{PATH};

            # Find the path to the executables.
            foreach (@path_env_vars) {
                $self->set_path_to_exes(gs => $_)
                    if /gs(?:[0-9.]+)?[\/\\]bin/i;
            }

            # Capture the name of the gs executable.
            opendir my $gs_bin_fh, $self->path_to_exes->{gs};
            foreach (readdir $gs_bin_fh) {
                $self->set_exes(gs => $_) if /gswin(32|64)c\b/i;
            }
            closedir $gs_bin_fh;
        }
        # (ii) When the env var has yet to been set:
        elsif ($ENV{PATH} !~ /gs(?:[0-9.]+)?[\/\\]bin/i) {
            say $self->Cmt->borders->{'*'};
            say "\aPath env var for the Ghostscript 'bin' dir NOT found!";
            say $self->Cmt->borders->{'*'};
        }

        # Path to /lib
        # When the env var has yet to been set:
        if ($ENV{PATH} !~ /gs(?:[0-9.]+)?[\/\\]lib/i) {
            say $self->Cmt->borders->{'*'};
            say "\aPath var for the Ghostscript 'lib' dir NOT found!";
            say $self->Cmt->borders->{'*'};
        }

        #
        # Inkscape
        #

        # Path to the executable
        # (i) When the env var has already been set:
        if ($ENV{PATH} =~ /inkscape/i) {
            @path_env_vars = split /$env_var_delim/, $ENV{PATH};

            # Find the path to the executables.
            foreach (@path_env_vars) {
                $self->set_path_to_exes(inkscape => $_) if /inkscape/i;
            }

            # Capture the name of the Inkscape executable.
            opendir my $inkscape_fh, $self->path_to_exes->{inkscape};
            foreach (readdir $inkscape_fh) {
                $self->set_exes(inkscape => $_) if /inkscape[.]exe\b/i;
            }
            closedir $inkscape_fh;

            # Inkscape forward compatibility (>= v1.x.x)
            my $_inkscape_exe = $self->exes->{inkscape};
            my $_inkscape_ver = `$_inkscape_exe --version`;
            $_inkscape_ver =~ s/.*Inkscape\s*([0-9.\-]+).*/$1/i;
            my $is_inkscape_aft_ver1 = (split /[.]/, $_inkscape_ver)[0];
            if ($is_inkscape_aft_ver1) {
                $self->set_inkscape_export(
                    $_ => (
                        "--export-type=$_".
                        " --export-area-drawing".
                        # Without the command below, "_out" will be generated.
                        " --export-overwrite"
                    ),
                ) for keys %{$self->inkscape_export};
            }
        }
        # (ii) When the env var has yet to been set:
        elsif ($ENV{PATH} !~ /inkscape/i) {
            say $self->Cmt->borders->{'*'};
            say "\aPath env var for Inkscape NOT found!";
            say $self->Cmt->borders->{'*'};
        }

        #
        # Make this block not performed at the next call.
        #
        $chk_env_var = 0;
    }

    #
    # [Ghostscript] Output devices
    #

    # [Ghostscript] Command-line options for raster images
    state $raster_cmd_opts = sprintf(
        "-dTextAlphaBits=%s".
        " -dGraphicsAlphaBits=%s".
        " -r%s",
        $self->Ctrls->text_alpha_bits,
        $self->Ctrls->graphics_alpha_bits,
        $self->Ctrls->raster_dpi
    );

    # [Ghostscript] Command-line options for PostScript (mainly Distiller opts)
    state $ps_cmd_opts = sprintf(
        "-dPDFSETTINGS#/%s".
        " -dMaxSubsetPct=%d".
        " -dSubsetFonts=%s".
        " -dEmbedAllFonts=%s",
        $self->Ctrls->pdf_settings,
        $self->Ctrls->max_subset_pct,
        $self->Ctrls->subset_fonts,
        $self->Ctrls->embed_all_fonts,
    );

    # [Ghostscript] Device parameters
    state $gs_out_devices = {
        png => {
            switch     => $self->Ctrls->png_switch,
            fformat    => 'png',
            fname_flag => '',
            cmd_opts   => sprintf(
                "-sDEVICE=%s".
                " %s",
                $self->s_devices->{png16m},
                $raster_cmd_opts,
            ),
        },
        png_trn => {
            switch     => $self->Ctrls->png_trn_switch,
            fformat    => 'png',
            fname_flag => $self->FileIO->fname_space.'trn',
            cmd_opts   => sprintf(
                "-sDEVICE=%s".
                " %s",
                $self->s_devices->{pngalpha},
                $raster_cmd_opts,
            ),
        },
        jpg => {
            switch     => $self->Ctrls->jpg_switch,
            fformat    => 'jpg',
            fname_flag => '',
            cmd_opts   => sprintf(
                "-sDEVICE=%s".
                " %s",
                $self->s_devices->{jpg},
                $raster_cmd_opts,
            ),
        },
        pdf => {
            switch     => $self->Ctrls->pdf_switch,
            fformat    => 'pdf',
            fname_flag => '',
            cmd_opts   => sprintf(
                "-sDEVICE=%s".
                " %s",
                $self->s_devices->{pdfwrite},
                $ps_cmd_opts,
            ),
        },
    };

    # [Inkscape] Output parameters
    state $inkscape_out_formats = {
        svg => {
            switch     => $self->Ctrls->svg_switch,
            fformat    => 'svg',
            fname_flag => '',
            cmd_opts   => sprintf("%s", $self->inkscape_export->{svg}),
        },
        emf => {
            switch     => $self->Ctrls->emf_switch,
            fformat    => 'emf',
            fname_flag => '',
            cmd_opts   => sprintf("%s", $self->inkscape_export->{emf}),
        },
        wmf => {
            switch     => $self->Ctrls->wmf_switch,
            fformat    => 'wmf',
            fname_flag => '',
            cmd_opts   => sprintf("%s", $self->inkscape_export->{wmf}),
        },
    };

    #
    # Notify the beginning of the routine.
    #
    # The conditional block is run only once "per call of inner_iterator()"
    # by using "a scalar reference (an object attribute called 'is_first_run')"
    # that is reinitialized at every run of the inner_iterator() of phitar.
    #
    if ($self->Ctrls->is_first_run) {
        # Notify the beginning.
        say "";
        say $self->Cmt->borders->{'='};
        printf(
            "%s [%s] converting\n".
            "%s the PS image%s using [%s]...\n",
            $self->Cmt->symb, join('::', (caller(0))[0, 3]),
            $self->Cmt->symb, $fname_flag_pairs[1] ? 's' : '', (
                $has_been_used{gs_and_inkscape} == 2 ?
                    $self->exes->{gs}.' and '.$self->exes->{inkscape} :
                $has_been_used{gs}       ? $self->exes->{gs} :
                $has_been_used{inkscape} ? $self->exes->{inkscape} :
                                           ''
            )
        );
        say $self->Cmt->borders->{'='};

        # Make this block not performed until the next run of inner_iterator().
        # (reinitialized at the beginning of each inner_iterator().)
        $self->Ctrls->set_is_first_run(0);
    }

    # Iterate over the argument pairs.
    foreach my $pair (@fname_flag_pairs) {
        # Skip an empty array ref for conditionals of
        # neutron-specific bremsstrahlung converter,
        # plain molybdenum target, and
        # neutron-specific molybdenum target.
        # To see in what cases empty array refs are passed,
        # look up "->convert" in the main program.
        next if not @{$pair};

        # Remove the filename extension for correct splicing below.
        # (the $pair->[0] given by phitar is a filename of .ang;
        # take the bare name only.)
        ($bname = $pair->[0]) =~ s/[.][a-zA-Z]+$//;

        #
        # Create a dir into which the converted image files will be stored.
        #

        # Initialization: The CWD.
        $out_dir  = '.'.$self->FileIO->path_delim;

        #
        # Directory naming for "phitar"
        #
        if ($is_phitar) {
            #
            # (1) Split the filename using the filename separator
            #     and remove numbers.
            #
            # For example, if the .eps filename was
            # 'wrcc-vhgt0p10-frad1p00-fgap0p15-track-xz.eps',
            # slicing the filename by $fname_sep with the indices of [0..3]
            # will result in 'wrcc-vhgt0p10-frad1p00-fgap0p15'.
            # When the numbers followed by the geometry strings are removed,
            # the directory name will be '.\wrcc-vhgt-frad-fgap'.
            #
            # For TRC molybdenum target, we need one more geometry var, thus
            # the indices should be from 0 to 4. For example,
            # 'mo_trc-vhgt0p50-fbrad0p15-ftrad0p60-fgap0p15-track-xz.eps'
            # will result in
            # 'mo_trc-vhgt-fbrad-ftrad-fgap'.
            #
            $out_dir .= $_.$fname_sep for (split /$fname_sep/, $bname)[
                (split /$fname_sep/, $bname)[0] =~ /trc/i ? 0..4 :
                                                            0..3
            ];
            $out_dir =~ s/[0-9]+p?[0-9]+//g;
            $out_dir =~ s/_-/-/g;  # For $t_shared->Ctrls->shortname =~ /off/i
            $out_dir =~ s/--/-/g;  # For $t_shared->Ctrls->shortname =~ /off/i

            #
            # (2) Append the tally flag to the directory name.
            #
            # If the tally flag was '-track-xz', the above dir name will be:
            # '.\wrcc-vhgt-frad-fgap-track-xz'.
            $out_dir .= $pair->[1];

            #
            # (3) Create the directory if it had not existed.
            #
            if (not -e $out_dir) {
                mkdir $out_dir;

                say "";
                say "[$out_dir] mkdir-ed.";
                say " ".('^' x length($out_dir));
            }
        }

        # [Ghostscript]
        # Buffer directories containing to-be-animated raster images.
        if ($self->Ctrls->skipping_switch =~ /on/i) {
            print "Collecting [$out_dir] for raster images...";
        }
        $self->add_rasters_dirs($out_dir);  # Must be outside the conditional

        # [Ghostscript]
        # Skip running Ghostscript but provide the raster image buffer;
        # must therefore be placed after the directory buffering above.
        # Used when ImageMagick switch is turned on while
        # no rasterization is to be performed.
        if ($self->Ctrls->skipping_switch =~ /on/i) {
            print " Done!\n";
            next;
        }

        #
        # Convert the given PS files to designated output image formats.
        #

        # Define the name of the "input" PS file.
        # A PS file, if exists, take precedence over an EPS one.
        $ps_fname = (-e $bname.'.'.$self->FileIO->fname_exts->{ps}) ?
            $bname.'.'.$self->FileIO->fname_exts->{ps} :
            $bname.'.'.$self->FileIO->fname_exts->{eps};

        # Begin the conversion.
        if (-e $ps_fname) {
            #
            # Ghostscript
            # > For the switches (-c and -f in particular), refer to:
            #   use.htm#General_switches
            # > Iterate over the "Ghostscript output devices".
            #

            # Determine if the PS file consists of more than one page.
            open my $ps_fh, '<', $ps_fname;
            my $num_pages = first {/^\s*%%Pages:\s*(?:[0-9]+)\s*/ix} <$ps_fh>;
            close $ps_fh;
            $num_pages =~ s/^\s*%%Pages:\s*([0-9]+)\s*/$1/ if $num_pages;
            $is_multipage = ($num_pages and $num_pages >= 2) ? 1 : 0;

            # Preprocessing for multipage PS files
            # > Mulitpage PS files cannot be cropped via the command -dEPSCrop.
            #   The workaround is as follows:
            #   (1) Obtain the bbox info using the bbox device of Ghostscript.
            #   (2) Convert .eps to .pdf with "-dUseCropBox" used and using
            #       the bbox info obtained at (1).
            #   (3) Convert the cropped .pdf to .png, .jpg, ...

            # Initializations
            my $is_pdfed = 0;
            my $pdf_fname =
                $out_dir.
                ($is_phitar ? $self->FileIO->path_delim : '').
                $bname.
                $gs_out_devices->{pdf}{fname_flag}.
                $self->FileIO->fname_ext_delim.
                $self->FileIO->fname_exts->{$gs_out_devices->{pdf}{fformat}};
            (my $pdf_fname_temp = $pdf_fname) =~ s/[.]pdf$/_.pdf/i;

            if (
                $self->Ctrls->pdf_switch =~ /on/i and
                (
                    $is_multipage or
                    $is_phitar or
                    ($is_crop and not $is_legacy_epscrop)
                )
            ) {
                # (1) Obtain the bbox info.
                $the_cmd = sprintf(
                    "%s".
                    " %s".
                    " -sDEVICE=%s".
                    " %s",
                    $self->exes->{gs},
                    $self->interaction_params->{quartet},  # trio + dQUIET
                    $self->s_devices->{bbox},
                    $ps_fname,
                );
                my @bbox_info = `$the_cmd 2>&1`;  # Redirect stderr to stdout.
                my($bbox, $hiresbbox);
                foreach (@bbox_info) {
                    chomp;
                    if (/^%%BoundingBox:/) {
                        $bbox = (split /: /)[1];
                    }
                    if (/^%%HiResBoundingBox:/) {
                        $hiresbbox = (split /: /)[1];
                    }
                }

                # (2) .eps to .pdf with "-dUseCropBox" and possible rotation
                # (2-1) .eps to .pdf with "-dUseCropBox"
                $the_cmd = sprintf(
                    "%s".
                    " %s".
                    " %s".
                    " %s".
                    " -sOutputFile=%s".
                    " -c \"%s\"".
                    " -f %s",  # -f also terminates the tokens of -c above
                    $self->exes->{gs},
                    $self->interaction_params->{quartet},
                    $self->interaction_params->{usecropbox},
                    $gs_out_devices->{pdf}{cmd_opts},
                    $pdf_fname_temp,
                    "[/CropBox [$hiresbbox] /PAGES pdfmark",
                    $ps_fname,
                );
                say $the_cmd if $is_verbose;
                system $the_cmd;

                # (2-2) Rotate the cropped PDF if necessary (simultaneous
                # use of CropBox and Orientation should be avoided; otherwise
                # the before-cropped bbox will be used in the PDF).
                if ($is_rotate) {
                    $the_cmd = sprintf(
                        "%s".
                        " %s".
                        " -sDEVICE=%s".
                        " -sOutputFile=%s".
                        " -c \"%s\"".
                        " -f %s",
                        $self->exes->{gs},
                        $self->interaction_params->{quartet},
                        $self->s_devices->{pdfwrite},
                        $pdf_fname,
                        (
                            ' <</Orientation '.
                            $self->Ctrls->orientation.
                            '>> setpagedevice'
                        ),
                        $pdf_fname_temp,
                    );
                    say $the_cmd if $is_verbose;
                    system $the_cmd;
                    unlink $pdf_fname_temp;
                }

                # Renaming hook for (2-1)
                rename($pdf_fname_temp, $pdf_fname) if -e $pdf_fname_temp;

                # Notification
                printf(
                    "[%s (%s page%s)] --> %s (v%s) converted.\n",
                    $ps_fname,
                    $num_pages,
                    $num_pages >= 2 ? 's' : '',
                    "\Updf",
                    $self->pdfversion->{val},
                );

                $is_pdfed = 1;  # Hook
            }

            # PDF/EPS conversion to other formats
            # (i)  Multipage PS or called via phitar: pdf is converted
            # (ii) Single-page real EPS: eps is converted
            my $to_be_converted = $is_pdfed ? $pdf_fname : $ps_fname;

            # pdf-->pdf same fnames will erase the content;
            # single-page ANGEL-generated PS files should not be PDF-converted.
            my %devices = map { $_ => 1 } keys %{$gs_out_devices};
            delete $devices{pdf} if ($is_pdfed and $num_pages == 1);

            foreach my $k (sort keys %devices) {
                next if $gs_out_devices->{$k}{switch} =~ /off/i;

                # Define the name of the "output" file.
                $converted_fname =
                    $out_dir.
                    ($is_phitar ? $self->FileIO->path_delim : '').
                    $bname.
                    ($is_multipage ? $self->FileIO->fname_sep."%03d" : '').
                    $gs_out_devices->{$k}{fname_flag}.  # Nonempty: pngalpha
                    $self->FileIO->fname_ext_delim.
                    $self->FileIO->fname_exts->{
                        $gs_out_devices->{$k}{fformat}
                    };

                # Run the executable.
                $the_cmd = sprintf(
                    "%s".
                    " %s".
                    " %s".
                    " %s".
                    " -sOutputFile=%s".  # Alt: -o %s
                    "%s".
                    " -f %s",  # -f also terminates the tokens of -c above
                    $self->exes->{gs},
                    $self->interaction_params->{trio},
                    $other_than_the_trio,
                    $gs_out_devices->{$k}{cmd_opts},
                    $converted_fname,
                    # > A command of PS, not of GS: must be placed before
                    #   some switches such as -f (or @).
                    #   For details, see "General switches" of the use.htm.
                    # > $is_pdfed: already rotated
                    ($is_rotate and not $is_pdfed) ? (
                        ' -c "<</Orientation '.
                        $self->Ctrls->orientation.
                        '>> setpagedevice"'
                    ) : '',
                    $to_be_converted,
                );
                say $the_cmd if $is_verbose;
                system $the_cmd;

                # Notify the completion.
                $k =~ /pdf/i ? printf(
                    "[%s] --> %s (v%s) converted.\n",
                    $to_be_converted,
                    "\U$k",
                    $self->pdfversion->{val},
                ) : printf(
                    "[%s] --> %s rasterized. (DPI: %s)\n",
                    $to_be_converted,
                    "\U$k",
                    $self->Ctrls->raster_dpi,
                );
            }

            #
            # Inkscape
            # > Iterate over the "Ghostscript output devices".
            #
            foreach my $k (keys %{$inkscape_out_formats}) {
                next if $inkscape_out_formats->{$k}{switch} =~ /off/i;

                # Define the name of the "output" file.
                $converted_fname =
                    $out_dir.
                    ($is_phitar ? $self->FileIO->path_delim : '').
                    $bname.
                    $inkscape_out_formats->{$k}{fname_flag}.
                    $self->FileIO->fname_ext_delim.
                    $self->FileIO->fname_exts->{
                        $inkscape_out_formats->{$k}{fformat}
                    };
                # Run the executable.
                $the_cmd = sprintf(
                    "%s".
                    " %s".
                    " %s".
                    " --export-filename=%s",
                    $self->exes->{inkscape},
                    $to_be_converted,
                    $inkscape_out_formats->{$k}{cmd_opts},
                    $converted_fname,
                );
                say $the_cmd if $is_verbose;
                system $the_cmd;

                # Notify the completion.
                printf(
                    "[%s] --> %s converted.\n",
                    $to_be_converted, "\U$k"
                );
            }
        }
    }

    # Remove duplicated to-be-animated paths (for ImageMagick and FFmpeg).
    @{$self->rasters_dirs} = $self->uniq_rasters_dirs;

    return;
}

__PACKAGE__->meta->make_immutable;
1;


package Image::Cmt;

use Moose;
use namespace::autoclean;
with 'My::Moose::Cmt';

__PACKAGE__->meta->make_immutable;
1;


package Image::Ctrls;

use Moose;
use namespace::autoclean;
with 'My::Moose::Ctrls';

#
# Rasterization parameters
#
my %_rasterization_params = (
    # Subsample antialiasing
    # > Must be >=4
    # > Refer to: use.htm#Suppress%Rendering_parameters
    text_alpha_bits     => 4,
    graphics_alpha_bits => 4,

    # Resolution by dots per inch
    # To see the image quality difference wrto dpi,
    # refer to the raster images found in: \cs\graphics\gs\
    raster_dpi => 150,

    # Output image orientation
    # > For the 'setpagedevice' command of PostScript
    # [0] Portrait
    # [1] Seascape
    # [2] Upside down
    # [3] Landscape
    orientation => 3,
);

has $_ => (
    is      => 'ro',
    isa     => 'Int',
    lazy    => 1,
    default => $_rasterization_params{$_},
    writer  => 'set_'.$_,
) for keys %_rasterization_params;

#
# Adobe Distiller parameters (mainly for the pdfwrite device)
#
my %_distiller_params = (
    # References
    # [1] epstopdf.pl
    #     https://ctan.org/pkg/epstopdf?lang=en
    # [2] SO
    #     https://superuser.com/questions/435410/
    #     where-are-ghostscript-options-switches-documented

    # dPDFSETTINGS
    # Presets the "distiller parameters" to one of four predefined settings:
    # [/screen]   selects low-resolution output similar to
    #             the Acrobat Distiller "Screen Optimized" setting.
    # [/ebook]    selects medium-resolution output similar to
    #             the Acrobat Distiller "eBook" setting.
    # [/printer]  selects output similar to
    #             the Acrobat Distiller "Print Optimized" setting.
    # [/prepress] selects output similar to
    #             Acrobat Distiller "Prepress Optimized" setting.
    # [/default]  selects output intended to be useful across a wide variety
    #             of uses, possibly at the expense of a larger output file.
    pdf_settings => 'prepress',

    # dMaxSubsetPct
    # An Acrobat Distiller 5 parameter
    # Type: integer
    # UI name: Subset embedded fonts when percent of characters used
    #          is less than: value %
    # Default value: 100
    # 
    # The maximum percentage of glyphs in a font that can be used
    # before the entire font is embedded instead of a subset.
    # The allowable range is 1 through 100.
    # 
    # Distiller only uses this value if SubsetFonts is true.
    # For example, a value of 30 means that a font will be
    # embedded in full (not subset) if more than 30% of glyphs are used;
    # a value of 100 means all fonts will be subset no matter how many glyphs
    # are used (because you cannot use more than 100% of glyphs).
    max_subset_pct => 100,

    # dSubsetFonts
    subset_fonts => 'true',

    # dEmbedAllFonts
    embed_all_fonts => 'true',
);

has $_ => (
    is      => 'ro',
    isa     => 'Int|Str',
    lazy    => 1,
    default => $_distiller_params{$_},
    writer  => 'set_'.$_,
) for keys %_distiller_params;

# Additional switches
my %_additional_switches = (
    # Ghostscript
    png_switch     => 'off',
    png_trn_switch => 'off',  # Transparent PNG
    jpg_switch     => 'off',
    pdf_switch     => 'off',
    # Ghostscript executable skipping switch for
    # the subsequently executed programs ImageMagick and FFmpeg
    skipping_switch => 'off',

    # Inkscape
    svg_switch => 'off',
    emf_switch => 'off',
    wmf_switch => 'off',
);

has $_ => (
    is      => 'ro',
    isa     => 'My::Moose::Ctrls::OnOff',
    lazy    => 1,
    default => $_additional_switches{$_},
    writer  => 'set_'.$_,
) for keys %_additional_switches;

__PACKAGE__->meta->make_immutable;
1;


package Image::FileIO;

use Moose;
use namespace::autoclean;
with 'My::Moose::FileIO';

__PACKAGE__->meta->make_immutable;
1;
__END__
