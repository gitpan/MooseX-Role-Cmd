use inc::Module::Install;

name     'MooseX-Role-Cmd';
all_from 'lib/MooseX/Role/Cmd.pm';

requires 'Moose' => 0.24;
requires 'IPC::Cmd';

auto_install;
WriteAll;
