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

my ($self);
my ($good_gitdir);
$good_gitdir = "/home/jkeenan/gitwork/perl2";
my $workdir = "$ENV{HOMEDIR}/learn/perl/multisect";
my $first = '7c9c5138c6a704d1caf5908650193f777b81ad23';
my $last  = '8f6628e3029399ac1e48dfcb59c3cd30e5127c3e';
my $branch = 'blead';
my $configure_command = 'sh ./Configure -des -Dusedevel';
$configure_command   .= ' -Dcc=clang -Accflags=-DPERL_GLOBAL_STRUCT';
$configure_command   .= ' 1>/dev/null 2>&1';
my $test_command = '';

%args = (
    gitdir  => $good_gitdir,
    workdir => $workdir,
    first => $first,
    last    => $last,
    branch  => $branch,
    configure_command => $configure_command,
    test_command => $test_command,
    verbose => 1,
);
$params = process_options(%args);
#pp($params);
is($params->{gitdir}, $good_gitdir, "Got expected gitdir");
is($params->{workdir}, $workdir, "Got expected workdir");
is($params->{first}, $first, "Got expected first commit to be studied");
is($params->{last}, $last, "Got expected last commit to be studied");
is($params->{branch}, $branch, "Got expected branch");
is($params->{configure_command}, $configure_command, "Got expected configure_command");
ok(! $params->{test_command}, "test_command empty as expected");
ok($params->{verbose}, "verbose requested");


$self = Devel::Git::MultiBisect::BuildTransitions->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Devel::Git::MultiBisect::BuildTransitions');
isa_ok($self, 'Devel::Git::MultiBisect');
#pp($self);
pp({ map { $_ => $self->{$_} }  grep { $_ ne 'commits' } keys %{$self} });


ok(! exists $self->{targets},
    "BuildTransitions has no need of 'targets' attribute");
ok(! exists $self->{test_command},
    "BuildTransitions has no need of 'test_command' attribute");

my $this_commit_range = $self->get_commits_range();
ok($this_commit_range, "get_commits_range() returned true value");
is(ref($this_commit_range), 'ARRAY', "get_commits_range() returned array ref");

#pp($this_commit_range);

is($this_commit_range->[0], $first, "Got expected first commit in range");
is($this_commit_range->[-1], $last, "Got expected last commit in range");

my $rv = $self->multisect_builds();
ok($rv, "multisect_builds() returned true value");

note("get_multisected_outputs()");

my $multisected_outputs = $self->get_multisected_outputs();
say STDERR "AAA:";
pp($multisected_outputs);
is(ref($multisected_outputs), 'ARRAY',
    "get_multisected_outputs() returned array reference");
is(scalar(@{$multisected_outputs}), scalar(@{$self->{commits}}),
    "get_multisected_outputs() has one element for each commit");
for my $r (@{$multisected_outputs}) {
    ok(test_report($r),
        "Each element is either undefined or a hash ref with expected keys");
}

note("inspect_transitions()");

my $transitions = $self->inspect_transitions();
say STDERR "BBB:";
pp($transitions);
is(ref($transitions), 'HASH',
    "inspect_transitions() returned hash reference");
is(scalar(keys %{$transitions}), 3,
    "inspect_transitions() has 3 elements");
for my $k ( qw| newest oldest | ) {
    is(ref($transitions->{$k}), 'HASH',
        "Got hashref as value for '$k'");
    for my $l ( qw| idx md5_hex file | ) {
        ok(exists $transitions->{$k}->{$l},
            "Got key '$l' for '$k'");
    }
}
is(ref($transitions->{transitions}), 'ARRAY',
    "Got arrayref as value for 'transitions'");
my @arr = @{$transitions->{transitions}};
for my $t (@arr) {
    is(ref($t), 'HASH',
        "Got hashref as value for element in 'transitions' array");
    for my $m ( qw| newer older | ) {
        ok(exists $t->{$m}, "Got key '$m'");
        is(ref($t->{$m}), 'HASH', "Got hashref");
        for my $n ( qw| idx md5_hex file | ) {
            ok(exists $t->{$m}->{$n},
                "Got key '$n'");
        }
    }
}

done_testing();

# Copied from t/009.  TODO: Refactor so it's only defined once.

sub test_report {
    my $r = shift;
    return 1 if not defined $r;
    for my $k ( qw| commit commit_short file md5_hex | ) {
        return 0 unless exists $r->{$k};
    }
    return 1;
}

