#
# A Moose role for controls
#
# Copyright (c) 2018 Jaewoong Jang
# This script is available under the MIT license;
# the license information is found in 'LICENSE'.
#
package My::Moose::Ctrls;

use Moose::Role;
use Moose::Util::TypeConstraints;
use namespace::autoclean;

subtype 'My::Moose::Ctrls::OnOff'
    => as 'Str'
    => where { /\b(on|off)\b/i }
    => message {
        "\n\n".
        ("-" x 50)."\n".
        "You have input [$_]; please input 'on' or 'off'.\n".
        ("-" x 50).
        "\n\n"
    };

has 'switch' => (
    is      => 'rw',
    isa     => 'My::Moose::Ctrls::OnOff',
    lazy    => 1,
    default => 'off',
);

sub set_switch {
    my $self = shift;
    
    $self->switch($_[0]) if defined $_[0];
}

has 'mute' => (
    is      => 'rw',
    isa     => 'My::Moose::Ctrls::OnOff',
    lazy    => 1,
    default => 'off',
);

sub set_mute {
    my $self = shift;
    
    $self->mute($_[0]) if defined $_[0];
}

has 'write_fm' => (
    is      => 'rw',
    isa     => 'My::Moose::Ctrls::OnOff',
    lazy    => 1,
    default => 'off',
);

sub set_write_fm {
    my $self = shift;
    
    $self->write_fm($_[0]) if defined $_[0];
}

has 'is_first_run' => (
    is      => 'rw',
    isa     => 'Num',
    default => 1,
);

sub set_is_first_run {
    my $self = shift;
    
    $self->is_first_run($_[0]) if defined $_[0];
};

sub init_is_first_run {
    my $self = shift;
    
    $self->is_first_run(1);
};

1;