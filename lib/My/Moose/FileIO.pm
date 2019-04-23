#
# Moose role for file I/O
#
# Copyright (c) 2018-2019 Jaewoong Jang
# This script is available under the MIT license;
# the license information is found in 'LICENSE'.
#
package My::Moose::FileIO;

use Moose::Role;
use namespace::autoclean;

our $PACKNAME = __PACKAGE__;
our $VERSION  = '1.00';
our $LAST     = '2019-04-18';
our $FIRST    = '2018-08-18';

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
my %_fname_elems = ( # (key) attribute => (val) default
    fname_sep       => '-',
    fname_space     => '_', # Underline (_) instead of the space
    fname_ext_delim => '.',
    # Filename placeholders
    inp      => undef,
    inp_dmp  => undef, # Input file generating a dump file
    out      => undef,
    tmp      => undef,
    dat      => undef,
    rpt_flag => undef,
    # Elements of directory name
    dir       => undef,
    subdir    => undef,
    subsubdir => undef,
);

has $_ => (
    is      => 'ro',
    default => $_fname_elems{$_},
    writer  => 'set_'.$_,
) for keys %_fname_elems;

has 'fname_exts' => (
    traits  => ['Hash'],
    is      => 'ro',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    builder => '_build_fname_exts',
    handles => {
        set_fname_exts => 'set',
    },
);

sub _build_fname_exts {
    return {
        # Common
        tmp => 'tmp', # Temporary
        exe => 'exe',
        bat => 'bat',
        
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
        svg => 'svg',
        emf => 'emf',
        wmf => 'wmf',
        
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

#
# Platform-dependent attributes
#
my %_platform_dependents = (
    path_delim => {
        mswin    => '\\',
        unixlike => '/',
    },
    env_var_delim => {
        mswin    => ';',
        unixlike => ':',
    },
);

has $_ => (
    is      => 'ro',
    default => $^O =~ /MSWin32/i ? $_platform_dependents{$_}{mswin} :
                                   $_platform_dependents{$_}{unixlike},
    writer  => 'set_'.$_,
) for keys %_platform_dependents;

1;
__END__