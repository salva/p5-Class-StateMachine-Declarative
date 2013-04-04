package Class::StateMachine::Declarative::Builder;

use strict;
use warnings;
use Carp;
use 5.010;
use Scalar::Util ();

use Class::StateMachine;
*debug = \$Class::StateMachine::debug;
our $debug;

sub _debug {
    my $n = shift;
    warn "@_\n" if $debug and $n;
}

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

sub _is_hash  { UNIVERSAL::isa($_[0], 'HASH') }
sub _is_array { UNIVERSAL::isa($_[0], 'ARRAY') }

sub _ensure_list {
    my $ref = shift;
    ( UNIVERSAL::isa($ref, 'ARRAY') ? @$ref : $ref );
}

sub parse_state_declarations {
    my $self = shift;
    $self->_parse_state_declarations($self->{top}, @_);
    $self->_merge_any;
    $self->_resolve_advances($self->{top});
    $self->_resolve_transitions($self->{top}, []);
    # $self->_propagate_transitions($self->{top});
}

sub _parse_state_declarations {
    my $self = shift;
    my $parent = shift;
    while (@_) {
        my $name = shift // $self->_bad_def($parent, "undef is not valid as a state name");
        my $decl = shift;
        _is_hash($decl) or $self->_bad_def($parent, "HASH expected for substate '$name' declaration");
        $self->_add_state($name, $parent, %$decl);
    }
}

sub _add_state {
    my ($self, $name, $parent, @decl) = @_;
    my $secondary;
    if ($name = /^\((.*)\)$/) {
        $name = $1;
        $secondary = 1;
    }
    my $state = Class::StateMachine::Declarative::Builder::State->_new($name, $parent);
    $self->_handle_attr_secondary($state, 1) if $secondary;
    while (@decl) {
        my $k = shift @decl;
        my $method = $self->can("_handle_attr_$k") or $self->_bad_def($state, "bad declaration '$k'");
        if (defined (my $v = shift @decl)) {
            _debug(16, "calling handler for attribute $k with value $v");
            $method->($self, $state, $v);
        }
    }
    $self->{states}{$state->{full_name}} = $state;
    $state;
}

sub _handle_attr_enter {
    my ($self, $state, $v) = @_;
    $state->{enter} = $v;
}

sub _handle_attr_leave {
    my ($self, $state, $v) = @_;
    $state->{leave} = $v;
}

sub _handle_attr_jump {
    my ($self, $state, $v) = @_;
    $state->{jump} = $v;
}

sub _handle_attr_advance {
    my ($self, $state, $v) = @_;
    $state->{advance} = $v;
}

sub _handle_attr_delay {
    my ($self, $state, $v) = @_;
    push @{$state->{delay}}, _ensure_list($v);
}

sub _handle_attr_ignore {
    my ($self, $state, $v) = @_;
    push @{$state->{ignore}}, _ensure_list($v);
}

sub _handle_attr_secondary {
    my ($self, $state, $v) = @_;
    $state->{secondary} = !!$v;
}

sub _handle_attr_transitions {
    my ($self, $state, $v) = @_;
    _is_hash($v) or $self->_bad_def($state, "HASH expected for transitions declaration");
    my @transitions = %$v;
    while (@transitions) {
        my $event = shift @transitions;
        my $target = shift @transitions;
        $state->{transitions}{$event} = $target if defined $target;
    }
}

sub _handle_attr_substates {
    my ($self, $state, $v) = @_;
    $state->{full_name} eq '/__any__' and $self->_bad_def($state, "pseudo state __any__ can not contain substates");
    _is_array($v) or $self->_bad_def($state, "ARRAY expected for substate declarations");
    $self->_parse_state_declarations($state, @$v);
}

sub _merge_any {
    my $self = shift;
    my $top = $self->{top};
    $top->{name} = '__any__';
    if (defined(my $any = delete $self->{states}{'/__any__'})) {
        my $ss = $self->{top}{substates};
        @$ss = grep { $_->{name} ne '__any__' } @$ss;
        $top->{$_} //= $any->{$_} for keys %$any;
    }
}

sub _resolve_advances {
    my ($self, $state, $event) = @_;
    my @ss = @{$state->{substates}};
    if (@ss) {
        $event = $state->{advance} // $event;
        $self->_resolve_advances($_, $event) for @ss;
        if (defined $event) {
            while (@ss) {
                my $current_state = shift @ss;
                unless (defined ($current_state->{transitions}{$event})) {
                    if (my ($next_state) = grep { not $_->{secondary} } @ss) {
                        $current_state->{transitions}{$event} = $next_state->{full_name};
                    }
                }
            }
        }
    }
}

sub _resolve_transitions {
    my ($self, $state, $path) = @_;
    my @path = (@$path, $state->{short_name});
    my %transitions_abs;
    my %transitions_rev;
    while (my ($event, $target) = each %{$state->{transitions}}) {
        my $target_abs = $self->_resolve_target($target, \@path);
        $transitions_abs{$event} = $target_abs;
        push @{$transitions_rev{$target_abs} ||= []}, $event;
    }
    $state->{transitions_abs} = \%transitions_abs;
    $state->{transitions_rev} = \%transitions_rev;

    my $jump = $state->{jump};
    my $ss = $state->{substates};
    if (not defined $jump and not defined $state->{enter} and @$ss) {
        if (my ($main) = grep { not $_->{secondary} } @$ss) {
            $jump //= $main->{full_name};
        }
        else {
            $self->_bad_def($state, "all the substates are secondary");
        }
    }

    $state->{jump_abs} = $self->_resolve_target($jump, \@path) if defined $jump;

    $self->_resolve_transitions($_, \@path) for @$ss;
}

# sub _propagate_transitions {
#     my ($self, $state) = @_;
#     my $t = $state->{transitions_abs};
#     for my $ss (@{$state->{substates}}) {
#         my $ss_t = $ss->{transitions_abs};
#         $ss_t->{$_} //= $t->{$_} for keys %$t;
#         $self->_propagate_transitions($ss);
#     }
# }

sub _resolve_target {
    my ($self, $target, $path) = @_;
    # _debug(32, "resolving target '$target' from '".join('/',@$path)."'");
    if ($target =~ m|^__(\w+)__$|) {
        return $target;
    }
    if ($target =~ m|^/|) {
        return $target if $self->{states}{$target};
        _debug(32, "absolute target '$target' not found");
    }
    else {
        my @path = @$path;
        while (@path) {
            my $target_abs = join('/', @path, $target);
            if ($self->{states}{$target_abs}) {
                _debug(32, "target '$target' from '".join('/',@$path)."' resolved as '$target_abs'");
                return $target_abs;
            }
            pop @path;
        }
    }

    my $name = join('/', @$path);
    $name =~ s|^/+||;
    croak "unable to resolve transition target '$target' from state '$name'";
}

my $ignore_cb = sub {};

sub generate_class {
    my $self = shift;
    my $class = $self->{class};
    while (my ($full_name, $state) = each %{$self->{states}}) {
        my $name = $state->{name};
        my $parent = $state->{parent};
        if ($parent and $parent != $self->{top}) {
            Class::StateMachine::set_state_isa($class, $name, $parent->{name});
        }

        for my $when ('enter', 'leave') {
            if (defined (my $action = $state->{$when})) {
                Class::StateMachine::install_method($class,
                                                    "${when}_state",
                                                    sub { shift->$action },
                                                    $name);
            }
        }

        if (not defined $state->{enter} and $state->{name} ne '__any__') {
            if (defined (my $jump = $state->{jump_abs})) {
                my $jump_name = $self->{states}{$jump}{name};
                Class::StateMachine::install_method($class,
                                                    'enter_state',
                                                    sub { shift->state($jump_name) },
                                                    $name);
            }
        }

        for my $delay (@{$state->{delay}}) {
            my $event = $delay;
            Class::StateMachine::install_method($class,
                                                $event,
                                                sub { shift->delay_until_next_state($event) },
                                                $name);
        }
        for my $ignore (@{$state->{delay}}) {
            Class::StateMachine::install_method($class, $ignore, $ignore_cb, $name);
        }

        while (my ($target, $events) = each %{$state->{transitions_rev}}) {
            my $target_state = $self->{states}{$target};
            my $method = $target_state->{come_here_method} //= do {
                my $target_name = $target_state->{name};
                sub { shift->state($target_name) }
            };
            Class::StateMachine::install_method($class, $_, $method, $name) for @$events;
        }
    }
}

package Class::StateMachine::Declarative::Builder::State;

sub _new {
    my ($class, $name, $parent) = @_;
    $name //= '';
    my $full_name = ($parent ? "$parent->{full_name}/$name" : $name);
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
    $state;
}

1;
