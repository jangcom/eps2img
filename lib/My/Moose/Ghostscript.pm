#
# A Moose class to interface Artifex Software's Ghostscript
#
# Copyright (c) 2018 Jaewoong Jang
# This script is available under the MIT license;
# the license information is found in 'LICENSE'.
#
package Ghostscript;

use Moose;
use namespace::autoclean;
use feature qw(say state);
use constant ARRAY => ref [];

has 'Cmt' => (
    is      => 'rw',
    isa     => 'Ghostscript::Cmt',
    lazy    => 1,
    default => sub { Ghostscript::Cmt->new() },
);

has 'Ctrls' => (
    is      => 'rw',
    isa     => 'Ghostscript::Ctrls',
    lazy    => 1,
    default => sub { Ghostscript::Ctrls->new() },
);

has 'FileIO' => (
    is      => 'rw',
    isa     => 'Ghostscript::FileIO',
    lazy    => 1,
    default => sub { Ghostscript::FileIO->new() },
);

#
# Executable settings
#
has 'exe' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    # Executables vary depending on platforms and integer bits.
    # Unix-like        => gs
    # 32-bit gs, MSWin => gswin32c (gswin32 for GUI)
    # 64-bit gs, MSWin => gswin64c (gswin64 for GUI)
    default => 'gs',
);

sub set_exe {
    my $self = shift;
    
    $self->exe($_[0]) if defined $_[0];
}

has 'path_to_exes' => (
    is  => 'rw',
    isa => 'Str',
);

sub set_path_to_exes {
    my $self = shift;
    
    $self->path_to_exes($_[0]) if defined $_[0];
};

#
# Ghostscript options list
#
has 'interaction_params' => (
    is      => 'ro',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    builder => '_build_interaction_params',
);

sub _build_interaction_params { # use.htm#Interaction-related_parameters
    return {
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
}

has 'paper_sizes' => (
    is      => 'ro',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    builder => '_build_paper_sizes',
);

sub _build_paper_sizes { # use.htm#Known_paper_sizess
    return {
        usletter => 'letter', # 8.5" by 11.0"; the default
        a4       => 'a4',     # 8.3" by 11.7"
    }
}

# Output devices
has 's_devices' => (
    is      => 'ro',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    builder => '_build_s_devices',
);

sub _build_s_devices { # Devices.htm
    return {
        # Portable Network Graphics (PNG)
        png16m   => 'png16m',   # 24-bit RGB
        pnggray  => 'pnggray',  #  8-bit grayscale
        pngalpha => 'pngalpha', # 32-bit RGBA; transparency provided
        
        # Joint Photographic Experts Group (JPEG)
        jpg     => 'jpeg',
        jpggray => 'jpeggray',
    }
}

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
# Rasterize PS images.
#
# Note on subroutine generalization
# 2018-08-23
# Initially created for "phitar.pl", this routine has now been generalized.
# Use "eps2raster.pl" for rasterizing PS/EPS files.
#
sub rasterize {
    my $self = shift;
    
    # Determine the roles of passed arguments.
    my @fname_flag_pairs; # Pairs of a PS/EPS filename and an optional flag
    my @your_args;        # User-provided arguments
    foreach (@_) {
        push @fname_flag_pairs, $_ if     ref $_ eq ARRAY;
        push @your_args,        $_ if not ref $_ eq ARRAY;
    }
    my($bname, $out_dir);         # Will be used for directory naming (phitar)
    my($raster_fname, $ps_fname); # Storages of an output and an input
    
    # Routine execution options - General
    my @your_interaction_params;
    my $is_rotate     = 0;
    my $is_multipaged = 0;
    foreach (@your_args) {
        $self->Ctrls->set_dpi((split /=/)[1])          if /^dpi=/i;
        $self->Ctrls->set_png_switch('on')             if /^png$/i;
        $self->Ctrls->set_png_transparent_switch('on') if /^png_transparent$/i;
        $self->Ctrls->set_jpg_switch('on')             if /^jpe?g$/i;
        
        push @your_interaction_params,
            $self->interaction_params->{quiet}      if /^quiet$/i;
        push @your_interaction_params,
            $self->interaction_params->{epscrop}    if /^epscrop$/i;
        push @your_interaction_params,
            $self->interaction_params->{epsfitpage} if /^epsfitpage$/i;
        
        $is_rotate     = 1 if /^rotate$/i;
        $is_multipaged = 1 if /^multipaged$/i;
    }
    
    # Routine execution options - "phitar" only
    my $is_phitar  = 0;
    $is_phitar     = 1 if (split /\/|\\/, (caller)[1])[-1] =~ /phitar([.]pl)?/i;
    $is_rotate     = 1 if $is_phitar;
    $is_multipaged = 1 if $is_phitar; # ANGEL-generated .eps files are actually
                                      # mulitpage PS files!
    
    #
    # Storages for command-line execution of Ghostscript
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
    # Ghostscript output devices
    #
    
    # Common command-line options
    state $common_cmd_opts = sprintf(
        "-dTextAlphaBits=%s".
        " -dGraphicsAlphaBits=%s".
        " -r%s",
        $self->Ctrls->text_alpha_bits,
        $self->Ctrls->graphics_alpha_bits,
        $self->Ctrls->dpi
    );
    
    # Device parameters
    state $gs_out_devices = {
        png => {
            switch      => $self->Ctrls->png_switch,
            fformat     => 'png',
            fname_flag  => '',
            cmd_opts    => sprintf(
                "-sDEVICE=%s".
                " %s",
                $self->s_devices->{png16m},
                $common_cmd_opts
            ),
        },
        png_transparent => {
            switch      => $self->Ctrls->png_transparent_switch,
            fformat     => 'png',
            fname_flag  => $self->FileIO->fname_space.'transparent',
            cmd_opts    => sprintf(
                "-sDEVICE=%s".
                " %s",
                $self->s_devices->{pngalpha},
                $common_cmd_opts
            ),
        },
        jpg => {
            switch      => $self->Ctrls->jpg_switch,
            fformat     => 'jpg',
            fname_flag  => '',
            cmd_opts    => sprintf(
                "-sDEVICE=%s".
                " %s",
                $self->s_devices->{jpg},
                $common_cmd_opts
            ),
        },
    };
    
    # Construct comment borders.
    $self->Cmt->set_borders(
        leading_symb => $self->Cmt->symb,
        border_symbs => ['*', '=', '-'],
    );
    
    #
    # Examine environment variable settings and acquire the name of
    # the executable, which, when the OS is MS Windows, varies also with
    # the integer-bit of the Ghostscript installation.
    #
    # The conditional block is executed only once "during the program run"
    # by using "a state variable".
    #
    # use.htm#o_option
    # use.htm#Summary_of_environment_variables
    #
    state $chk_env_var = 1; # NOT reinitialized at the next call
    if ($chk_env_var == 1 and $^O =~ /MSWin32/i) {
        # Path to /bin
        # (i) When the env var has already been set:
        if ($ENV{PATH} =~ /gs[0-9]+[.]?[0-9]+(\/|\\)bin/i) {
            @path_env_vars = split /$env_var_delim/, $ENV{PATH};
            
            # Find the path to the executables.
            foreach (@path_env_vars) {
                $self->set_path_to_exes($_)
                    if /gs[0-9]+[.]?[0-9]+(\/|\\)bin/i;
            }
            
            # Capture the name of the gs executable.
            opendir my $gs_bin_fh, $self->path_to_exes;
            foreach (readdir $gs_bin_fh) {
                $self->set_exe($_) if /gswin(32|64)c\b/i;
            }
            closedir $gs_bin_fh;
        }
        # (ii) When the env var has yet to been set:
        elsif ($ENV{PATH} !~ /gs[0-9]+[.]?[0-9]+(\/|\\)bin/i) {
            say $self->Cmt->borders->{'*'};
            say "\aEnv var for the Ghostscript 'bin' dir NOT found!";
            say $self->Cmt->borders->{'*'};
        }
        
        # Path to /lib
        # When the env var has yet to been set:
        if ($ENV{PATH} !~ /gs[0-9]+[.]?[0-9]+(\/|\\)lib/i) {
            say $self->Cmt->borders->{'*'};
            say "\aEnv var for the Ghostscript 'lib' dir NOT found!";
            say $self->Cmt->borders->{'*'};
        }
        
        # Make this block not performed at the next call.
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
            "%s [%s] rasterizing\n".
            "%s the PS images using [%s]...\n",
            $self->Cmt->symb, join('::', (caller(0))[0, 3]),
            $self->Cmt->symb, $self->exe
        );
        say $self->Cmt->borders->{'='};
        
        # Make this block not performed until the next run of inner_iterator().
        # (reinitialized at the beginning of each inner_iterator().)
        $self->Ctrls->set_is_first_run(0);
    }
    
    # Iterate over the argument pairs.
    foreach my $pair (@fname_flag_pairs) {
        # Skip an empty array ref for conditionals of
        # W neutron-specific, Mo plain, and Mo neutron-specific.
        # To see in what cases empty array refs are passed,
        # look up "->rasterize" in the main program.
        next if not @{$pair};
        
        # Remove the filename extension for correct splicing below.
        # (the $pair->[0] given by phitar is a filename of .ang;
        # take the bare name only.)
        ($bname = $pair->[0]) =~ s/[.][a-zA-Z]+$//;
        
        #
        # Create a dir into which the rasterized image files will be stored.
        #
        
        # Initialization: The CWD.
        $out_dir  = '.'.$self->FileIO->path_delim;
        
        #
        # Directory naming for "phitar"
        #
        if ($is_phitar) {
            #
            # (1) Split the filename using the filename separator.
            #
            # For example, if the eps filename was
            # 'w_rcc-v_hgt-0p10-f_rad-1p0-track-xz.eps',
            # the array slicing with the $fname_sep prepending
            # will result in 'w_rcc-v_hgt-f_rad', and therefore
            # the directory name will be:
            # '.\w_rcc-v_hgt-f_rad'.
            $out_dir .= $_.$fname_sep for (split /$fname_sep/, $bname)[0, 1, 3];
            
            #
            # (2) Append the tally flag to the directory name.
            #
            # If the tally flag was '-track-xz', the above dir name will be:
            # '.\w_rcc-v_hgt-f_rad-track-xz'.
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
        
        # Buffer directories containing to-be-animated raster images.
        if ($self->Ctrls->skipping_switch =~ /on/i) {
            print "Collecting [$out_dir] for raster images...";
        }
        $self->add_rasters_dirs($out_dir); # Must be outside the conditional.
        
        # Skip running Ghostscript but provide the raster image buffer;
        # must therefore be placed after the directory buffering above.
        # Used when ImageMagick switch is turned on while
        # no rasterization is to be performed.
        if ($self->Ctrls->skipping_switch =~ /on/i) {
            print " Done!\n";
            next;
        }
        
        #
        # Perform rasterization via Ghostscript.
        #
        # For the switches (-c and -f in particular), refer to:
        # use.htm#General_switches
        #
        
        # Define the name of the "input" PS file.
        # A PS file, if exists, take precedence over an EPS one.
        $ps_fname = (-e $bname.'.'.$self->FileIO->fname_ext->{ps}) ?
            $bname.'.'.$self->FileIO->fname_ext->{ps} :
            $bname.'.'.$self->FileIO->fname_ext->{eps};
        
        if (-e $ps_fname) {
            # Iterate over the "Ghostscript output devices".
            foreach my $k (keys %{$gs_out_devices}) {
                next if $gs_out_devices->{$k}{switch} =~ /off/i;
                
                # Define the name of the "output" raster file.
                $raster_fname =
                    $out_dir.
                    ($is_phitar ? $self->FileIO->path_delim : '').
                    $bname.
                    ($is_multipaged ? $self->FileIO->fname_sep."%03d" : '').
                    $gs_out_devices->{$k}{fname_flag}. # Nonempty: pngalpha
                    $self->FileIO->fname_ext_delim.
                    $self->FileIO->fname_ext->{$gs_out_devices->{$k}{fformat}};
                
                # Run the Ghostscript executable.
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
                    $self->exe,
                    $self->interaction_params->{trio},
                    $other_than_the_trio,
                    $gs_out_devices->{$k}{cmd_opts},
                    $raster_fname,
                    $ps_fname
                );
                system $the_cmd;
                
                # Notify the completion.
                printf(
                    "[%s] --> %s rasterized. (DPI: %s)\n",
                    $ps_fname, "\U$k", $self->Ctrls->dpi
                );
            }
        }
    }
    
    # Remove duplicated to-be-animated paths (for ImageMagick and FFmpeg).
    @{$self->rasters_dirs} = $self->uniq_rasters_dirs;
}

__PACKAGE__->meta->make_immutable;
1;


package Ghostscript::Cmt;

use Moose;
use namespace::autoclean;
with 'My::Moose::Cmt';

__PACKAGE__->meta->make_immutable;
1;


package Ghostscript::Ctrls;

use Moose;
use namespace::autoclean;
with 'My::Moose::Ctrls';

#
# Additional attributes
#

#
# Rasterization parameters
#

# Subsample antialiasing
has $_ => (
    is      => 'rw',
    isa     => 'Int',
    lazy    => 1,
    default => 4, # Must be >=4; use.htm#Suppress%Rendering_parameters
) for qw(
    text_alpha_bits
    graphics_alpha_bits
);

sub set_text_alpha_bits {
    my $self = shift;
    
    $self->text_alpha_bits($_[0]) if defined $_[0];
}

sub set_graphics_alpha_bits {
    my $self = shift;
    
    $self->graphics_alpha_bits($_[0]) if defined $_[0];
}

# Resolution
has 'dpi' => (
    is      => 'rw',
    isa     => 'Int',
    lazy    => 1,
    # To see the image quality difference wrto dpi,
    # refer to the raster images found in: \cs\graphics\gs\
    default => 150,
);

sub set_dpi {
    my $self = shift;
    
    $self->dpi($_[0]) if defined $_[0];
}

# Output image orientation: For the 'setpagedevice' command of PostScript
has 'orientation' => (
    is      => 'rw',
    isa     => 'Int',
    lazy    => 1,
    # [0] Portrait
    # [1] Seascape
    # [2] Upside down
    # [3] Landscape
    default => 3,
);

sub set_orientation {
    my $self = shift;
    
    $self->orientation($_[0]) if defined $_[0];
}

# PNG
has 'png_switch' => (
    is      => 'rw',
    isa     => 'My::Moose::Ctrls::OnOff',
    lazy    => 1,
    default => 'off',
);

sub set_png_switch {
    my $self = shift;
    
    $self->png_switch($_[0]) if defined $_[0];
}

# Transparent PNG
has 'png_transparent_switch' => (
    is      => 'rw',
    isa     => 'My::Moose::Ctrls::OnOff',
    lazy    => 1,
    default => 'off',
);

sub set_png_transparent_switch {
    my $self = shift;
    
    $self->png_transparent_switch($_[0]) if defined $_[0];
}

# JPEG
has 'jpg_switch' => (
    is      => 'rw',
    isa     => 'My::Moose::Ctrls::OnOff',
    lazy    => 1,
    default => 'off',
);

sub set_jpg_switch {
    my $self = shift;
    
    $self->jpg_switch($_[0]) if defined $_[0];
}

# Ghostscript executable skipping switch for
# the subsequently executed programs ImageMagick and FFmpeg
has 'skipping_switch' => (
    is      => 'rw',
    isa     => 'My::Moose::Ctrls::OnOff',
    lazy    => 1,
    default => 'off',
);

sub set_skipping_switch {
    my $self = shift;
    
    $self->skipping_switch($_[0]) if defined $_[0];
}

__PACKAGE__->meta->make_immutable;
1;


package Ghostscript::FileIO;

use Moose;
use namespace::autoclean;
with 'My::Moose::FileIO';

__PACKAGE__->meta->make_immutable;
1;