package Class::StateMachine::Declarative::Builder;

use strict;
use warnings;
use Carp;
use 5.010;
use Scalar::Util ();

sub new {
    my ($class, $target_class) = @_;
    my $top = Class::StateMachine::Declarative::Builder::State->_new;
    my $self = { top => $top,
                 states => { '/' => $top },
                 class => $target_class };
    bless $self, $class;
    $self;
}

sub _bad_def {
    my ($self, $state, @msg) = @_;
    croak "@msg on definition of state '$state->{name}' for class '$self->{class}'";
}

sub new_state {
    my ($self, $name, $parent, @decl) = @_;

    $parent //= $self->{top};
    my $state = Class::StateMachine::Declarative::Builder::State->_new($name, $parent);

    while (@decl) {
        my $k = shift @decl;
        my $v = shift @decl;
        if (defined $v) {
            given ($k) {
                when ('enter') {
                    ref $v and $self->_bad_def($state, "'enter' arguments is not an scalar");
                    $state->{enter} = $v;
                }
                when ('leave') {
                    ref $v and $self->_bad_def($state, "'leave' arguments is not an scalar");
                    $state->{leave} = $v;
                }
                when ('delay') {
                    ref $v eq 'ARRAY' or $self->_bad_def($state, "'delay' arguments is not an ARRAY reference");
                    push @{$state->{delay}}, @$v;
                }
                when ('ignore') {
                    ref $v eq 'ARRAY' or $self->_bad_def($state, "'ignore' arguments is not an ARRAY reference");
                    push @{$state->{ignore}}, @$v;
                }
                when ('transitions') {
                    ref $v eq 'HASH' or $self->_bad_def($state, "'transitions' arguments is not a HASH reference")
                    while (my ($event, $target) = each %$v) {
                        ref $event and $self->_bad_def($state, "transition event arguments is not an scalar");
                        ref $target and $self->_bad_def($state, "transition target arguments is not an scalar");
                        $state->{transitions}{$event} = $target if defined $target;
                    }
                }
                default {
                    $self->_bad_def($state, "unsupported state attribute '$k'");
                }
            }
        }
    }
    $state;
}

sub resolve_transitions {
    my $self = shift;
    my @path;
    $self->_resolve_transitions($self->{top}, \@path);
}

sub _resolve_transitions {
    my ($self, $state, $path) = @_;
    my @path = (@$path, $state->{name});
    my %transitions_abs;
    my %transitions_rev;
    while (my ($event, $target) = each %{$state->{transitions}}) {
        my $target_abs = $self->_resolve_target($target, \@path);
        $transitions_abs{$event} = $target_abs;
        push @{$transitions_rev{$target_abs} ||= []}, $event;
    }
    $state->{transitions_abs} = \%transitions_abs;
    $state->{transitions_rev} = \%transitions_rev;

    for my $substate (values %{$state->{}}) {
        $self->_resolve_transitions($self, $substate, \@path);
    }
}

sub _resolve_target {
    my ($self, $target, $path) = @_;
    if ($target =~m|^/|) {
        return $target if $self->{states}{$target};
    }
    else {
        my @path = @$path;
        while (@path) {
            my $target_abs = join('/', @path, $target);
            return $target_abs if $self->{states}{$target_abs};
            shift @path;
        }
    }

    my $name = join('/', @$path);
    $name =~ s|^/+||;
    croak "unable to resolve transition target '$target' from state '$name'";
}

my $ignore_cb = sub {};

sub generate {
    my $self = shift;
    my $class = $self->{class};
    while (my ($full_name, $state) = each %{self->{states}}) {
        my $name = $state->{name};
        my $parent = $state->{parent};
        if ($parent and $parent != $self->{top}) {
            Class::StateMachine::set_state_isa($class, $state, $parent->{name});
        }

        for my $when ('enter', 'leave') {
            my $action = $state->{$when};
            Class::StateMachine::install_method($class,
                                                "${when}_state",
                                                sub { shift->$action },
                                                $name);
        }
        for my $delay (@{$state->{delay}}) {
            my $event = $delay;
            Class::StateMachine::install_method($class,
                                                $event,
                                                sub { shift->delay_until_next_state($event) },
                                                $name);
        }
        for my $ignore (@{$state->{delay}}) {
            Class::StateMachine::install_method($class, $event, $ignore_cb, $name);
        }

        while (my ($target, $events) = each %{$state->{transitions_rev}}) {
            my $target_state = $self->{states}{$target};
            my $method = $target_state->{come_here_method} //= do {
                my $target_name = $target_state->{name};
                sub { shift->state($name) };
            };
            Class::StateMachine::install_method($class, $_, $method, $name) for @$events;
        }
    }
}

package Class::StateMachine::Declarative::Builder::State;

sub _new {
    my ($class, $name, $parent) = @_;
    my $full_name = ($parent ? "$parent->{full_name}/$name" : $name // "");
    my $final_name = $full_name;
    $final_name =~ s|^/+||;
    my $state = { short_name => $name,
                  full_name => $full_name,
                  name => $final_name,
                  parent => $parent,
                  substates => [],
                  transitions => {},
                  ignore => [],
                  delay => [] };
    bless $state, $class;
    push @{$parent->{substates}}, $state if $parent;
    Scalar::Util::weaken($state->{parent});
    $self;
}

1;
