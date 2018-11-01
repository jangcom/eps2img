#
# A Moose role for commenting
#
# Copyright (c) 2018 Jaewoong Jang
# This script is available under the MIT license;
# the license information is found in 'LICENSE'.
#
package My::Moose::Cmt;

use Moose::Role;
use namespace::autoclean;

#
# Abbreviations
#
has 'abbrs' => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef[ArrayRef]',
    lazy    => 1,
    builder => '_build_abbr',
    handles => {
        set_abbrs => 'set',
    },
);

sub _build_abbr {
    return {
        energy => ['energy', 'erg'],
        radius => ['radius', 'rad'],
        height => ['height', 'hgt'],
        bottom => ['bottom', 'bot'],
    };
}

#
# Commenting
#

# Comment symbol
has 'symb' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => '#',
);

sub set_symb {
    my $self = shift;
    
    $self->symb($_[0]) if defined $_[0];
}

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
}

has 'borders_tmp' => ( 
    is      => 'rw',
    isa     => 'HashRef[Str]',
    default => sub { {} },
);

has 'borders' => (
    is      => 'rw',
    isa     => 'HashRef[Str]',
    default => sub { {} },
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
}

1;