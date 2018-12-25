# -*- perl -*-
# xt/101-build-transitions.t
use strict;
use warnings;
use Devel::Git::MultiBisect::Opts qw( process_options );
use Devel::Git::MultiBisect::BuildTransitions;
use Test::More;
use Capture::Tiny qw( :all );
use Cwd;
use File::Spec;
use Data::Dump qw(dd pp);

my $ptg = File::Spec->catfile('', qw| path to gitdir |);
my $pttf = File::Spec->catfile('', qw| path to test file |);

my (%args, $params);

%args = (
    last_before => '12345ab',
    gitdir => $ptg,
    targets => [ $pttf ],
    last => '67890ab',
);
$params = process_options(%args);
ok($params, "process_options() returned true value");
ok(ref($params) eq 'HASH', "process_options() returned hash reference");
for my $k ( qw|
    last_before
    make_command
    outputdir
    repository
    branch
    short
    verbose
    workdir
| ) {
    ok(defined($params->{$k}), "A default value was assigned for $k: $params->{$k}");
}

my $cwd = cwd();

my (%args, $params, $self);
#%args = (
#  branch            => "master",
#  configure_command => "perl Makefile.PL 1>/dev/null",
#  first             => "v5.26.3",
#  gitdir            => "/home/jkeenan/gitwork/perl",
#  last              => "v5.26.9",
#  make_command      => "make 1>/dev/null",
#  outputdir         => "/tmp/yvv_BSgfHP",
#  repository        => "origin",
#  short             => 7,
#  test_command      => "prove -vb",
#  verbose           => 0,
#  workdir           => "/home/jkeenan/gitwork/devel-git-multibisect",
#);


my ($good_gitdir);
$good_gitdir = "/home/jkeenan/gitwork/perl2";
my $first = '00d5a150792677746a950e9c1db6b0d094b113af';
my $last  = '698ea056906af7b60f00b30a44b3591dcbf07a05';
my $branch = 'blead';
my $configure_command = 'sh ./Configure -des -Dusedevel';
my %test_command = '';


=pod

00d5a150792677746a950e9c1db6b0d094b113af refs/tags/v5.27.3
59ddc66bf56b5bb38d6501ff3a6c132bce020d8a refs/tags/v5.27.4
6060757363a636eb1aad2a114417ae5cef85613e refs/tags/v5.27.5
98a3f44f528b7c677f68fe7d2fd8ece45b79535a refs/tags/v5.27.6
6f8f9770f72e74d48b879fa817d78837af793582 refs/tags/v5.27.7
8ac0ebb14b343d555c93f87826c15468b5ec1c4a refs/tags/v5.27.8
698ea056906af7b60f00b30a44b3591dcbf07a05 refs/tags/v5.27.9

=cut

%args = (
    gitdir  => $good_gitdir,
    first => $first,
    last    => $last,
    branch  => $branch,
    configure_command => $configure_command,
    test_command => '',
);
$params = process_options(%args);
pp($params);
is($params->{gitdir}, $good_gitdir, "Got expected gitdir");
is($params->{first}, $first, "Got expected first commit to be studied");
is($params->{last}, $last, "Got expected last commit to be studied");
is($params->{branch}, $branch, "Got expected branch");
is($params->{configure_command}, $configure_command, "Got expected configure_command");
ok(! $params->{test_command}, "test_command empty as expected");
ok(! $params->{verbose}, "verbose not requested");

$self = Devel::Git::MultiBisect::BuildTransitions->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Devel::Git::MultiBisect::BuildTransitions');
pp([ keys %$self ]);

done_testing();
