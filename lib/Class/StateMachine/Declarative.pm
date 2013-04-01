package Class::StateMachine::Declarative;

sub _clean_eval { eval shift }

our $VERSION = '0.01';

use 5.010;

use strict;
use warnings;
use Carp;
BEGIN { our @CARP_NOT = qw(Class::StateMachine Class::StateMachine::Private) }

use Class::StateMachine::Declarative::Builder;

my $dump = exists $ENV{CLASS_STATEMACHINE_DECLARATIVE_DUMPFILE};
my %dump;

END {
    if ($dump) {
        open my $fh, ">", $ENV{CLASS_STATEMACHINE_DECLARATIVE_DUMPFILE} or return;
        require Data::Dumper;
        print $fh Data::Dumper->Dump([\%dump], [qw(*state_machines)]);
        close $fh;
    }
}

sub import {
    shift;
    my $class = scalar(caller);
    $dump{$class} = [ @_ ] if $dump;
    my $builder = Class::StateMachine::Declarative::Builder->new($class);
    $builder->parse_state_declarations(@_);
    $builder->generate_class;
    use Data::Dumper;
    print STDERR Dumper($builder);
}

1;
__END__

=head1 NAME

Class::StateMachine::Declarative - Perl extension for blah blah blah

=head1 SYNOPSIS


  package Dog;

  use parent 'Class::StateMachine';

  use Class::StateMachine::Declarative
      happy    => { transitions => { on_knocked_down => 'injuried',
                                     on_kicked       => 'angry' } },
      injuried => { transitions => { on_sleep        => 'happy' } },
      angry    => { enter       => sub { shift->bark },
                    leave       => sub { shift->bark },
                    transitions => { on_feed         => 'happy',
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

Copyright (C) 2011-2013 by Salvador FandiE<ntilde>o <sfandino@yahoo.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.4 or,
at your option, any later version of Perl 5 you may have available.


=cut
