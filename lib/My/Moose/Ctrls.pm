#
# Moose role for controls
#
# Copyright (c) 2018-2019 Jaewoong Jang
# This script is available under the MIT license;
# the license information is found in 'LICENSE'.
#
package My::Moose::Ctrls;

use Moose::Role;
use Moose::Util::TypeConstraints;
use namespace::autoclean;

our $PACKNAME = __PACKAGE__;
our $VERSION  = '1.00';
our $LAST     = '2019-03-23';
our $FIRST    = '2018-08-18';

my %_on_off = map { $_ => 1 } qw(
    on
    off
);

subtype 'My::Moose::Ctrls::OnOff'
    => as 'Str'
    => where { exists $_on_off{$_} }
    => message {
        printf(
            "\n\n%s\n[%s] is not an allowed value.".
            "\nPlease input one of these: [%s]\n%s\n\n",
            ('-' x 70), $_,
            join(', ', sort keys %_on_off), ('-' x 70),
        )
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
    
    return;
};

sub init_is_first_run {
    my $self = shift;
    
    $self->is_first_run(1);
    
    return;
};

1;
__END__