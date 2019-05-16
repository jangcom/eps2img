#
# Moose role for commenting
#
# Copyright (c) 2018-2019 Jaewoong Jang
# This script is available under the MIT license;
# the license information is found in 'LICENSE'.
#
package My::Moose::Cmt;

use Moose::Role;
use namespace::autoclean;

our $PACKNAME = __PACKAGE__;
our $VERSION  = '1.00';
our $LAST     = '2019-05-11';
our $FIRST    = '2018-08-18';

#
# Abbreviations and full names
#
has 'abbrs' => (
    traits  => ['Hash'],
    is      => 'ro',
    isa     => 'HashRef[ArrayRef]',
    lazy    => 1,
    builder => '_build_abbr',
    handles => {
        set_abbrs => 'set',
    },
);

sub _build_abbr {
    return {
        energy => ['energy' => 'eng'], # eng is the axis name of energy in PHITS
        height => ['height' => 'hgt'],
        radius => ['radius' => 'rad'],
        bottom => ['bottom' => 'bot'],
        gap    => ['gap'    => 'gap'],
    };
}

has 'full_names' => (
    traits  => ['Hash'],
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    builder => '_build_full_names',
    handles => {
        set_full_names => 'set',
    },
);

sub _build_full_names {
    return {
        eng => 'energy',
        nrg => 'energy',
        hgt => 'height',
        rad => 'radius',
        bot => 'bottom',
        gap => 'gap',
    };
}

#
# Commenting
#

# Comment symbol
has 'symb' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => '#',
    writer  => 'set_symb',
);

# Comment border
has 'borders_len' => (
    is      => 'rw',
    isa     => 'Int',
    lazy    => 1,
    default => 70,
);

sub set_borders_len {
    my $self = shift;
    
    # Overwrite the comment border length.
    $self->borders_len($_[0]) if defined $_[0];
    
    # Update the lengths of comment borders.
    $self->set_borders(
        leading_symb => $self->borders_tmp->{leading_symb},
        border_symbs => $self->borders_tmp->{border_symbs}
    );
    
    return;
}

has $_ => ( 
    is      => 'rw',
    isa     => 'HashRef[Str]',
    default => sub { {} },
) for qw(
    borders_tmp
    borders
);

sub set_borders {
    my $self = shift;
    
    # Define (and memorize for later recovery) comment border properties.
    %{$self->borders_tmp} = @_ ?
        @_ : (leading_symb => '#', border_symbs => ['=', '-']);
    
    # Create comment borders using the designated properties.
    foreach my $symb (@{$self->borders_tmp->{border_symbs}}) {
        $self->borders->{$symb} =
            $self->borders_tmp->{leading_symb}.
            ($symb x ($self->borders_len - 1)); # -1: the leading symb
    }
    
    return;
}

1;
__END__