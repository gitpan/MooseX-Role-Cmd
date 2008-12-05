package MooseX::Role::Cmd;

use strict;
use warnings;

use IPC::Cmd ();
use Moose::Role;
use MooseX::Role::Cmd::Meta::Attribute::Trait;

our $VERSION = '0.04';

=head1 NAME

MooseX::Role::Cmd - Wrap system command binaries the Moose way

=head1 SYNOPSIS

Create your command wrapper:

    package Cmd::Perl;

    use strict;
    use warnings;

    use Moose;

    with 'MooseX::Role::Cmd';

    has 'e' => (isa => 'Str', is => 'rw');

    # other perl switches here...

    1;

Use it somewhere else:

    use Cmd::Perl;

    my $perl = Cmd::Perl->new(e => q{'print join ", ", @ARGV'});
    print $perl->run(qw/foo bar baz/);
    # prints the STDOUT captured from running:
    # perl -e 'print join ", ", @ARGV' foo bar baz

=head1 DESCRIPTION

MooseX::Role::Cmd is a L<Moose> role intended to ease the task of building
command-line wrapper modules. It automatically maps L<Moose> objects into
command strings which are passed to L<IPC::Cmd>.

=head1 ATTRIBUTES

=head2 $cmd->bin_name

Sets the binary executable name for the command you want to run. Defaults
the to last part of the class name.

=cut

has 'bin_name' => (
    isa     => 'Str',
    is      => 'rw',
    lazy    => 1,
    default => sub { shift->build_bin_name },
);

=head2 $cmd->stdout

Returns the STDOUT buffer captured after running the command.

=cut

has 'stdout' => ( isa => 'ArrayRef', is => 'rw' );

=head2 $cmd->stderr

Returns the STDERR buffer captured after running the command.

=cut

has 'stderr' => ( isa => 'ArrayRef', is => 'rw' );

no Moose;

=head1 METHODS

=head2 my $bin_name = $cmd->build_bin_name

Builds the default string for the command name based on the class name.

=cut

# done this way to be overrideable
sub build_bin_name {
    my ($self) = @_;
    my $class = ref $self;
    if ( !$class ) {
        $class = $self;
    }
    return lc( ( split '::', $class )[-1] );    ## no critic
}

=head2 my @stdout = $cmd->run(@args);

Builds the command string and runs it based on the objects current attribute
settings. This will treat all the attributes defined in your class as flags
to be passed to the command.

Suppose the following setup:

    has 'in'  => (isa => 'Str', is => 'rw')
    has 'out' => (isa => 'Str', is => 'rw');

    # ...

    $cmd->in('foo');
    $cmd->out('bar');

The command will be invoked as:

    cmd -in foo -out bar

All quoting issues are left to be solved by the user.

=cut

sub run {
    my ( $self, @args ) = @_;

    my $cmd = $self->bin_name;
    my $full_path;
    if ( !( $full_path = IPC::Cmd::can_run($cmd) ) ) {
        confess qq{couldn't find command '$cmd'};
    }
    
    # build full list of cmd args from attrs
    @args = $self->cmd_args( @args );
    
    my ( $success, $error_code, $full_buf, $stdout_buf, $stderr_buf ) =
      IPC::Cmd::run( command => [ $full_path, @args ] );

    if ( !$success ) {
        confess "error running '$full_path': " . $error_code;
    }

    $self->stdout($stdout_buf);
    $self->stderr($stderr_buf);
    return 1;
}

=head2 cmd_args

Returns a list of the computed arguments that will be added to the command

=cut

sub cmd_args {
    my ( $self, @extra_args ) = @_;

    # exclude this role's attributes from the flag list
    # could use custom metaclasses and introspection, but this will do for now
    my %non_flag   = map  {    $_ => 1     } __PACKAGE__->meta->get_attribute_list;
    my @flag_attrs = grep { !$non_flag{$_} }       $self->meta->get_attribute_list;
    
    #####
    # IS: 2008/10/15
    # Changed the following to make a start on the suggestion above...
    #####
    #my @flags = map { ( "-$_" => $self->$_ ) } @flag_attrs;
    my @flags = map { ( $self->_attr_name_to_cmd_options( $_ ) ) } @flag_attrs;

    my @args = ( @flags, @extra_args );

    return wantarray ? @args : \@args;
}


=head1 PRIVATE METHODS

=head2 _attr_name_to_cmd_options

Returns an array (or array reference) of command options that correspond
to the given attribute name. This essentially provides the following
functionality:

Bool as flags, everything else as key => value params

    has 'v'       => ( isa => 'Bool' );                 # -v
    has 'i'       => ( isa => 'Str' );                  # -i input.data

Use Getopt::Long conventions with hyphenations:

    has 'v'       => ( isa => 'Bool' );                 # -v
    has 'verbose' => ( isa => 'Bool' );                 # --verbose

Use optional info from CmdOpt trait:

    has 'v'       => ( isa          => 'Bool' );        # -v
    
    has 'short'   => ( traits       => [ 'CmdOpt' ],
                       isa          => 'Bool',
                       cmdopt_prefix => '-'
                     );                                 # -short
    
    has 'rename'  => ( traits       => [ 'CmdOpt' ],
                       isa          => 'Bool',
                       cmdopt_name  => '+foo'
                     );                                 # +foo

=cut

sub _attr_name_to_cmd_options {
    my ( $self, $attr_name ) = @_;
    
    my $attr = $self->meta->get_attribute( $attr_name );
    
    # decide the default settings
    my $opt_prefix = length( $attr_name ) == 1 ? '-' : '--';
    my $opt_name   = $attr_name;
    
    # override defaults with Traits
    if ( $attr->does('MooseX::Role::Cmd::Meta::Attribute::Trait') ) {
        if ($attr->has_cmdopt_prefix) {
            $opt_prefix = $attr->cmdopt_prefix;
        }
        if ($attr->has_cmdopt_name) {
            $opt_prefix = '';                   # name overrides prefix
            $opt_name   = $attr->cmdopt_name;
        }
    }
    
    # create the full option name
    my $opt_fullname = $opt_prefix . $opt_name;
    
    my @options = ();
    if ( $attr->type_constraint->is_a_type_of( 'Bool' ) ) {
        push @options, ( $opt_fullname )
            if $self->$attr_name;                       # only add if attr is true
    }
    else {
        push @options, ( $opt_fullname, $self->$attr_name )
            if defined $self->$attr_name;               # only add if attr is defined
    }
    
    return wantarray ? @options : \@options;
}

=head1 AUTHOR

Eden Cardim <edencardim@gmail.com>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
