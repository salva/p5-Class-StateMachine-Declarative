use 5.010;

use ExtUtils::MakeMaker;

WriteMakefile( NAME         => 'Class::StateMachine::Declarative',
               VERSION_FROM => 'lib/Class/StateMachine/Declarative.pm',
               PREREQ_PM    => { 'mro' => 0,
                                 'Class::StateMachine' => '0.17' },
               AUTHOR       => 'Salvador Fandiño <sfandino@yahoo.com>',
             );
