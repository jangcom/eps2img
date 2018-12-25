#
# Moose role for controls
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

my %_switches = ( # (key) attribute => (val) default
    switch   => 'off',
    mute     => 'off',
    write_fm => 'off',
);

has $_ => (
    is      => 'ro',
    isa     => 'My::Moose::Ctrls::OnOff',
    lazy    => 1,
    default => $_switches{$_},
    writer  => 'set_'.$_,
) for keys %_switches;

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