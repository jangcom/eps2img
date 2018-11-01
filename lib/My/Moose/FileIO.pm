#
# A Moose role for file I/O
#
# Copyright (c) 2018 Jaewoong Jang
# This script is available under the MIT license;
# the license information is found in 'LICENSE'.
#
package My::Moose::FileIO;

use Moose::Role;
use namespace::autoclean;

#
# Note on delimiters and separators
#
# A delimiter sets the start and end of a thing.
# (i)  A single delimiter: the comma (,) in [a, b, c, d, e]
# (ii) A paired delimiter: the quote (') in 'We have been delimited'
# 
# A separator is a special kind of a delimiter
# that separates two items in a row.
# (i) The sentence "We have been delimited" is delimited by a pair of
#     double quotes ("), while its components "We", "have", "been",
#     and "delimited" are separated by a space.
# 
# In this context, I use a separator to separate the constituent words
# of a filename (without its extension), and a delimiter to denote
# the end of the filename and the beginning of its extension.
# e.g. FileNaming.pm
#      'File' and 'naming' are separated by the capitalization of
#      the first letter of 'naming' (UpperCamelCase or PascalCase),
#      and the beginning of the associated extension 'pm' is denoted
#      by its single delimiter, the period (.).
# 
# For detailed discussions, refer to
# https://softwareengineering.stackexchange.com/questions/127783
# /comma-as-a-separator-vs-comma-as-a-delimiter
#

#
# Filename elements
#
has 'fname_sep' => (
    is      => 'ro', 
    isa     => 'Str',
    default => '-',
);

has 'fname_space' => (
    is       => 'ro',
    isa      => 'Str',
    default  => '_', # Underline (_) instead of the space
    init_arg => undef,
);

has 'fname_ext' => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    builder => '_build_fname_ext',
    handles => {
        set_fname_ext => 'set',
    },
);

has 'fname_ext_delim' => (
    is       => 'ro',
    isa      => 'Str',
    lazy     => 1,
    default  => '.',
    init_arg => undef,
);

sub _build_fname_ext {
    return {
        # Common
        tmp   => 'tmp',
        exe   => 'exe',
        bat   => 'bat',
        
        # Dataset
        dat => 'dat',
        csv => 'csv',
        
        # Perl
        pl => 'pl',
        pm => 'pm',
        
        # Markups
        xml  => 'xml',
        html => 'html',
        
        # gnuplot
        gp => 'gp',
        
        # PHITS
        inp => 'inp',
        out => 'out',
        ang => 'ang',
        
        # ANSYS
        arr => 'arr',
        tab => 'tab',
        mac => 'mac',
        
        # Office tools
        xls  => 'xls',
        xlsx => 'xlsx',
        ppt  => 'ppt',
        pptx => 'pptx',
        
        # Vector graphics formats
        ps  => 'ps',
        eps => 'eps',
        pdf => 'pdf',
        wmf => 'wmf',
        emf => 'emf',
        
        # Raster graphics formats
        png  => 'png',
        jpeg => 'jpg',
        jpg  => 'jpg',
        tif  => 'tif',
        tiff => 'tiff',
        gif  => 'gif',
        
        # Video formats
        avi   => 'avi',
        mpeg4 => 'mp4',
        mp4   => 'mp4',
    };
}

has $_ => (
    is  => 'rw',
    isa => 'Str',
) for qw(
    inp
    out
    tmp
    dat
);

sub set_inp {
    my $self  = shift;
    
    $self->inp($_[0]) if defined $_[0];
};

sub set_out {
    my $self  = shift;
    
    $self->out($_[0]) if defined $_[0];
};

sub set_tmp {
    my $self  = shift;
    
    $self->tmp($_[0]) if defined $_[0];
};

sub set_dat {
    my $self  = shift;
    
    $self->dat($_[0]) if defined $_[0];
};

#
# Directory names
#
has $_ => (
    is  => 'rw',
    isa => 'Str',
) for qw(
    dir
    subdir
    subsubdir
    rpt_dir
);

sub set_dir    {
    my $self = shift;
    
    $self->dir($_[0]) if defined $_[0];
};

sub set_subdir {
    my $self = shift;
    
    $self->subdir($_[0]) if defined $_[0];
};

sub set_subsubdir {
    my $self = shift;
    
    $self->subsubdir($_[0]) if defined $_[0];
};

sub set_rpt_dir {
    my $self = shift;
    
    $self->rpt_dir($_[0]) if defined $_[0];
};

# Path delimiter; platform-dependent.
has 'path_delim' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => sub { $^O =~ /MSWin32/i ? '\\' : '/' },
);

sub set_path_delim {
    my $self = shift;
    
    $self->path_delim($_[0]) if defined $_[0];
}

# Environment variable delimiter; platform-dependent.
has 'env_var_delim' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => sub { $^O =~ /MSWin32/i ? ';' : ':' },
);

sub set_env_var_delim {
    my $self = shift;
    
    $self->env_var_delim($_[0]) if defined $_[0];
}

1;