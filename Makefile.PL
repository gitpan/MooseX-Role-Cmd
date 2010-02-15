use inc::Module::Install;

name     'MooseX-Role-Cmd';
all_from 'lib/MooseX/Role/Cmd.pm';

requires 'Moose' => 0.90;
requires 'IPC::Cmd' => 0.42;
requires 'IPC::Run';

auto_install;
WriteAll;
