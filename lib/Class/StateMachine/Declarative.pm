package Class::StateMachine::Declarative;

sub _clean_eval { eval shift }

our $VERSION = '0.01';

use 5.010;

use strict;
use warnings;

use Carp;
use Class::StateMachine;
use mro;

require parent;

sub import {
    shift;
    init_class(scalar(caller), @_);
}

my $usage = 'usage: use Class::StateMachine::Declarative state => { enter_state => action, transitions => { event => final_state, ...}, ... }, state => { ... }, ...;';

sub _action {
    my ($action, $call_next) = @_;
    given (ref $action) {
        when ('CODE') {
            if ($call_next) {
                return sub {
                    my $self = $_[0];
                    $action->(@_);
                    $self->maybe::next::method;
                };
            }
            else { return $action }
        }
        when ('') {
            if ($action =~ /^\w+(?:::\w)*$/) {
                if ($call_next) {
                    return sub {
                        my $self = shift;
                        $self->$action;
                        $self->maybe::next::method;
                    };
                }
                else {
                    return sub { shift->$action };
                }
            }
            else {
                my ($pkg, $fn, $line) = caller(1);
                my $maybe = ($call_next ? '; $self->maybe::next::method' : '');
                my $sub = _clean_eval <<SUB;
sub {
    package $pkg;
    my \$self = shift;
    # line $line $fn
    $action
    $maybe
}
SUB
                die $@ if $@;
                return $sub;
            }
        }
        default {
            croak "$action is not a valid action";
        }
    }
}

sub init_class {
     my ($class, %states) = @_;
     while (my ($state, $decl) = each %states) {
         ref $decl eq 'HASH' or croak "$decl is not a hash reference, $usage";
         while (my ($type, $arg) = each %$decl) {
             given ($type) {
                 when(/^(enter|leave)(\+?)$/) {
                     Class::StateMachine::install_method($class, "${1}_state", _action($arg, $2), $state);
                 }
                 when ('transitions') {
                     ref $arg eq 'HASH' or croak "$arg is not a hash reference, $usage";
                     while (my ($event, $final) = each %$arg) {
                         Class::StateMachine::install_method($class, $event,
                                                             sub { shift->state($final) },
                                                             $state);
                     }
                 }
                 default {
                     croak "invalid option '$type', $usage";
                 }
             }
         }
     }
}

1;
__END__

=head1 NAME

Class::StateMachine::Declarative - Perl extension for blah blah blah

=head1 SYNOPSIS


  package Dog;

  use parent 'Class::StateMachine';

  use Class::StateMachine::Declarative
      __any__  => { enter       => sub { say "entering state $_[0]" },
                    leave       => sub { say "leaving state $_[0" },
      happy    => { transitions => { on_knocked_down => 'injuried',
                                     on_kicked       => 'angry' } },
      injuried => { transitions => { on_sleep        => 'happy' } },
      angry    => { transitions => { on_feed         => 'happy',
                                     on_knocked_down => 'injuried' } } };

  sub new {
    my $class = shift;
    my $self = {};
    # starting state is set here:
    Class::StateMachine::bless $self, $class, 'happy';
    $self;
  }


  # events (mehotds) that do not cause a state change:
  sub on_touched_head : OnState(happy) { shift->move_tail }
  sub on_touched_head : OnState(injuried) { shift->bark('') }
  sub on_touched_head : OnState(angry) { shift->bite }


  package main;

  my $dog = Dog->new;
  $dog->on_touched_head; # the dog moves his tail
  $dog->on_kicked;
  $dog->on_touched_head; # the dog bites you
  $dog->on_injuried;
  $dog->on_touched_head; # the dog barks
  $dog->on_sleep;
  $dog->on_touched_head; # the dog moves his tail


=head1 DESCRIPTION

Class::StateMachine::Declarative is a L<Class::StateMachine> extension
that allows to define most of a state machine class declaratively.

=head1 SEE ALSO

L<Class::StateMachine>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Salvador FandiE<ntilde>o <sfandino@yahoo.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.4 or,
at your option, any later version of Perl 5 you may have available.


=cut
