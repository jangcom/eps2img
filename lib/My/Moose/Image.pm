#
# Moose class for Image
#
# Copyright (c) 2018 Jaewoong Jang
# This script is available under the MIT license;
# the license information is found in 'LICENSE'.
#
package Image;

use Moose;
use namespace::autoclean;
use feature qw(say state);
use constant ARRAY => ref [];
use constant HASH  => ref {};

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
my %_exe_settings = ( # (key) attribute => (val) default
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
    interaction_params => sub { # use.htm#Interaction-related_parameters
        {
            safer      => '-dSAFER',
            batch      => '-dBATCH',
            nopause    => '-dNOPAUSE',
            quiet      => '-dQUIET',
            epscrop    => '-dEPSCrop',
            epsfitpage => '-dEPSFitPage',
            # Combos
            trio       => '-dSAFER -dBATCH -dNOPAUSE',
            quartet    => '-dSAFER -dBATCH -dNOPAUSE -dQUIET',
            quintet    => '-dSAFER -dBATCH -dNOPAUSE -dQUIET -dEPSCrop',
        }
    },
    paper_sizes => sub { # use.htm#Known_paper_sizess
        {
            usletter => 'letter', # 8.5" by 11.0"; the default
            a4       => 'a4',     # 8.3" by 11.7"
        }
    },
    s_devices => sub { # Devices.htm
        {
            # I. Image file formats
            # I-1. Portable Network Graphics (PNG)
            png16m   => 'png16m',   # 24-bit RGB
            pnggray  => 'pnggray',  #  8-bit grayscale
            pngalpha => 'pngalpha', # 32-bit RGBA; transparency provided
            # I-2. Joint Photographic Experts Group (JPEG)
            jpg      => 'jpeg',
            jpggray  => 'jpeggray',
            # II. High level formats
            # I-1. Portable Document Format (PDF)
            pdfwrite => 'pdfwrite',
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
has 'inkscape_export' => (
    is      => 'ro',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    default => sub {
        {
            emf => '-M', # Alternative: --export-emf. Available only on MSWin.
            wmf => '-m', # Alternative: --export-wmf. Available only on MSWin.
        }
    },
);

#
# Convert PostScript files to raster and vector images.
#
sub convert {
    #
    # Note on subroutine generalization
    #
    # 2018-08-23
    # > Initially created for "phitar.pl", this routine has now been generalized.
    #   Use "eps2img.pl" for rasterizing PS/EPS files.
    #
    # 2018-12-24
    # > Class name changed: Ghostscript.pm --> Image.pm
    # > In addition to Ghostscript, Inkscape is used to
    #   convert .eps files to .emf and .wmf files.
    #
    
    my $self = shift;
    
    # Determine the roles of passed arguments.
    my @fname_flag_pairs; # Pairs of a PS/EPS filename and an optional flag
    my @your_args;        # User-provided arguments
    my %phitar_flags;     # phitar-only: flags for naming subdirs
    foreach (@_) {
        push @fname_flag_pairs,    $_ if     ref $_ eq ARRAY;
        push @your_args,           $_ if not ref $_ eq ARRAY;
        %phitar_flags = %{$_}         if     ref $_ eq HASH;
    }
    my($bname, $out_dir);            # Used for directory naming (phitar)
    my($converted_fname, $ps_fname); # Storages of an output and an input
    my %has_been_used = map { $_ => 0 } qw (gs inkscape); # Notif purposes
    
    # Routine execution options - General
    my @your_interaction_params;
    my $is_rotate     = 0;
    my $is_multipaged = 0;
    foreach (@your_args) {
        #
        # Ghostscript
        #
        $self->Ctrls->set_raster_dpi((split /=/)[1]) if /^(raster_)?dpi\s*=/i;
        $self->Ctrls->set_png_switch('on')           if /^(png|all)$/i;
        $self->Ctrls->set_png_trn_switch('on')       if /^(png_trn|all)$/i;
        $self->Ctrls->set_jpg_switch('on')           if /^(jpe?g|all)$/i;
        $self->Ctrls->set_pdf_switch('on')           if /^(pdf|all)$/i;
        $has_been_used{gs} = 1 if $self->Ctrls->png_switch     =~ /on/i;
        $has_been_used{gs} = 1 if $self->Ctrls->png_trn_switch =~ /on/i;
        $has_been_used{gs} = 1 if $self->Ctrls->jpg_switch     =~ /on/i;
        $has_been_used{gs} = 1 if $self->Ctrls->pdf_switch     =~ /on/i;
        
        push @your_interaction_params,
            $self->interaction_params->{quiet}      if /^quiet$/i;
        push @your_interaction_params,
            $self->interaction_params->{epscrop}    if /^epscrop$/i;
        push @your_interaction_params,
            $self->interaction_params->{epsfitpage} if /^epsfitpage$/i;
        
        $is_rotate     = 1 if /^rotate$/i;
        $is_multipaged = 1 if /^multipaged$/i;
        
        #
        # Inkscape
        #
        $self->Ctrls->set_emf_switch('on') if /^(emf|all)$/i;
        $self->Ctrls->set_wmf_switch('on') if /^(wmf|all)$/i;
        $has_been_used{inkscape} = 1 if $self->Ctrls->emf_switch =~ /on/i;
        $has_been_used{inkscape} = 1 if $self->Ctrls->wmf_switch =~ /on/i;
    }
    $has_been_used{gs_and_inkscape} =
        $has_been_used{gs} + $has_been_used{inkscape};
    
    # [Ghostscript] Execution options - "phitar" only
    my $is_phitar  = 0;
    $is_phitar     = 1 if (split /\/|\\/, (caller)[1])[-1] =~ /phitar([.]pl)?/i;
    $is_rotate     = 1 if $is_phitar;
    $is_multipaged = 1 if $is_phitar; # ANGEL-generated .eps files are actually
                                      # mulitpage PS files!
    
    #
    # [Ghostscript] Storages for command-line execution
    #
    my($other_than_the_trio, $the_cmd);
    $other_than_the_trio = ($is_phitar and $self->Ctrls->mute =~ /on/i) ?
        $self->interaction_params->{quiet} :
        "@your_interaction_params";
    
    # For regexes
    my $fname_sep     = $self->FileIO->fname_sep;
    my $dir_delim     = $self->FileIO->path_delim;
    my $env_var_delim = $self->FileIO->env_var_delim;
    my @path_env_vars;
    
    #
    # [Ghostscript] Output devices
    #
    
    # [Ghostscript] Common command-line options
    state $common_cmd_opts = sprintf(
        "-dTextAlphaBits=%s".
        " -dGraphicsAlphaBits=%s".
        " -r%s",
        $self->Ctrls->text_alpha_bits,
        $self->Ctrls->graphics_alpha_bits,
        $self->Ctrls->raster_dpi
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
                $common_cmd_opts
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
                $common_cmd_opts
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
                $common_cmd_opts
            ),
        },
        pdf => {
            switch     => $self->Ctrls->pdf_switch,
            fformat    => 'pdf',
            fname_flag => '',
            cmd_opts   => sprintf(
                "-sDEVICE=%s",
                $self->s_devices->{pdfwrite}
            ),
        },
    };
    
    # [Inkscape] Output parameters
    state $inkscape_out_formats = {
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
    state $chk_env_var = 1; # NOT reinitialized at the next call
    if ($chk_env_var == 1 and $^O =~ /MSWin32/i) {
        #
        # Ghostscript
        #
        
        # Path to the executables (/bin)
        # (i) When the env var has already been set:
        if ($ENV{PATH} =~ /gs[0-9]+[.]?[0-9]+(\/|\\)bin/i) {
            @path_env_vars = split /$env_var_delim/, $ENV{PATH};
            
            # Find the path to the executables.
            foreach (@path_env_vars) {
                $self->set_path_to_exes(gs => $_)
                    if /gs[0-9]+[.]?[0-9]+(\/|\\)bin/i;
            }
            
            # Capture the name of the gs executable.
            opendir my $gs_bin_fh, $self->path_to_exes->{gs};
            foreach (readdir $gs_bin_fh) {
                $self->set_exes(gs => $_) if /gswin(32|64)c\b/i;
            }
            closedir $gs_bin_fh;
        }
        # (ii) When the env var has yet to been set:
        elsif ($ENV{PATH} !~ /gs[0-9]+[.]?[0-9]+(\/|\\)bin/i) {
            say $self->Cmt->borders->{'*'};
            say "\aPath env var for the Ghostscript 'bin' dir NOT found!";
            say $self->Cmt->borders->{'*'};
        }
        
        # Path to /lib
        # When the env var has yet to been set:
        if ($ENV{PATH} !~ /gs[0-9]+[.]?[0-9]+(\/|\\)lib/i) {
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
                $self->set_exes(inkscape => $_) if /inkscape\b/i;
            }
            closedir $inkscape_fh;
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
    # Notify the beginning of the routine.
    #
    # The conditional block is executed only once "per call of inner_iterator()"
    # by using "a scalar reference (an object attribute called 'is_first_run')"
    # that is reinitialized at every run of the inner_iterator() of phitar.
    #
    if ($self->Ctrls->is_first_run) {
        # Notify the beginning.
        say "";
        say $self->Cmt->borders->{'='};
        printf(
            "%s [%s] converting\n".
            "%s the PS images using [%s]...\n",
            $self->Cmt->symb, join('::', (caller(0))[0, 3]),
            $self->Cmt->symb, (
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
            # 'w_rcc-vhgt0p10-frad1p00-fgap0p15-track-xz.eps',
            # slicing the filename by $fname_sep with the indices of [0..3]
            # will result in 'w_rcc-vhgt0p10-frad1p00-fgap0p15'.
            # When the numbers followed by the geometry strings are removed,
            # the directory name will be '.\w_rcc-vhgt-frad-fgap'.
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
            $out_dir =~ s/_-/-/g; # For $t_shared->Ctrls->shortname =~ /off/i
            $out_dir =~ s/--/-/g; # For $t_shared->Ctrls->shortname =~ /off/i
            
            #
            # (2) Append the tally flag to the directory name.
            #
            # If the tally flag was '-track-xz', the above dir name will be:
            # '.\w_rcc-vhgt-frad-fgap-track-xz'.
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
        $self->add_rasters_dirs($out_dir); # Must be outside the conditional.
        
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
            foreach my $k (keys %{$gs_out_devices}) {
                next if $gs_out_devices->{$k}{switch} =~ /off/i;
                
                # Define the name of the "output" file.
                $converted_fname =
                    $out_dir.
                    ($is_phitar ? $self->FileIO->path_delim : '').
                    $bname.
                    ($is_multipaged ? $self->FileIO->fname_sep."%03d" : '').
                    $gs_out_devices->{$k}{fname_flag}. # Nonempty: pngalpha
                    $self->FileIO->fname_ext_delim.
                    $self->FileIO->fname_exts->{$gs_out_devices->{$k}{fformat}};
                
                # Run the executable.
                $the_cmd = sprintf(
                    "%s".
                    " %s".
                    " %s".
                    " %s".
                    " -sOutputFile=%s".
                    (
                        # A command of PS, not GS: must be placed before
                        # some dashed option such as -f (or @).
                        # For details, see "General switches" of the 'use.htm'.
                        $is_rotate ? (
                            " -c \"<</Orientation ".
                            $self->Ctrls->orientation.
                            ">> setpagedevice\""
                        ) : ""
                    ).
                    " -f %s",
                    $self->exes->{gs},
                    $self->interaction_params->{trio},
                    $other_than_the_trio,
                    $gs_out_devices->{$k}{cmd_opts},
                    $converted_fname,
                    $ps_fname
                );
                system $the_cmd;
                
                # Notify the completion.
                $k =~ /pdf/i ? printf(
                    "[%s] --> %s converted.\n",
                    $ps_fname, "\U$k"
                ) : printf(
                    "[%s] --> %s rasterized. (DPI: %s)\n",
                    $ps_fname, "\U$k", $self->Ctrls->raster_dpi
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
                    " %s",
                    $self->exes->{inkscape},
                    $ps_fname,
                    $inkscape_out_formats->{$k}{cmd_opts},
                    $converted_fname
                );
                system $the_cmd;
                
                # Notify the completion.
                printf(
                    "[%s] --> %s converted.\n",
                    $ps_fname, "\U$k"
                );
            }
        }
    }
    
    # Remove duplicated to-be-animated paths (for ImageMagick and FFmpeg).
    @{$self->rasters_dirs} = $self->uniq_rasters_dirs;
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

# Additional switches
my %_additional_switches = (
    # Ghostscript
    png_switch     => 'off',
    png_trn_switch => 'off', # Transparent PNG
    jpg_switch     => 'off',
    pdf_switch     => 'off',
    # Ghostscript executable skipping switch for
    # the subsequently executed programs ImageMagick and FFmpeg
    skipping_switch => 'off',
    
    # Inkscape
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