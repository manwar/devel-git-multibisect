# -*- perl -*-
# t/008-prepare-multisect.t
use strict;
use warnings;
use Test::Multisect::Allcommits;
use Test::Multisect::Opts qw( process_options );
use Test::More qw(no_plan); # tests => 43;
use List::Util qw( first );
use Cwd;
#use Data::Dump qw(pp);

my $cwd = cwd();

my (%args, $params, $self);
my ($good_gitdir, $good_last_before, $good_last);
my ($target_args, $full_targets);
my ($rv, $transitions, $all_outputs, $all_outputs_count, $expected_count, $first_element);

# So that we have a basis for comparison, we'll first run already tested
# methods over the 'dummyrepo'.

$good_gitdir = "$cwd/t/lib/dummyrepo";
$good_last_before = '92a79a3dc5bba45930a52e4affd91551aa6c78fc';
$good_last = 'efdd091cf3690010913b849dcf4fee290f399009';
%args = (
    gitdir => $good_gitdir,
    last_before => $good_last_before,
    last => $good_last,
    verbose => 0,
);
$params = process_options(%args);
$target_args = [ 't/001_load.t' ];

note("First object");

$self = Test::Multisect::Allcommits->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Test::Multisect::Allcommits');

$full_targets = $self->set_targets($target_args);
ok($full_targets, "set_targets() returned true value");
is(ref($full_targets), 'ARRAY', "set_targets() returned array ref");
is_deeply(
    [ map { $_->{path} } @{$full_targets} ],
    [ map { "$self->{gitdir}/$_" } @{$target_args} ],
    "Got expected full paths to target files for testing",
);

$all_outputs = $self->run_test_files_on_all_commits();
ok($all_outputs, "run_test_files_on_all_commits() returned true value");
is(ref($all_outputs), 'ARRAY', "run_test_files_on_all_commits() returned array ref");
$all_outputs_count = 0;
for my $c (@{$all_outputs}) {
    for my $t (@{$c}) {
        $all_outputs_count++;
    }
}
is(
    $all_outputs_count,
    scalar(@{$self->get_commits_range}) * scalar(@{$target_args}),
    "Got expected number of output files"
);

$rv = $self->get_digests_by_file_and_commit();
ok($rv, "get_digests_by_file_and_commit() returned true value");
is(ref($rv), 'HASH', "get_digests_by_file_and_commit() returned hash ref");
cmp_ok(scalar(keys %{$rv}), '==', scalar(@{$target_args}),
    "Got expected number of elements: one for each of " . scalar(@{$target_args}) . " test files targeted");
$first_element = first { $_ } keys %{$rv};
is(ref($rv->{$first_element}), 'ARRAY', "Records are array references");
is(
    scalar(@{$rv->{$first_element}}),
    scalar(@{$self->get_commits_range}),
    "Got 1 element for each of " . scalar(@{$self->get_commits_range}) . " commits"
);
is(ref($rv->{$first_element}->[0]), 'HASH', "Records are hash references");
for my $k ( qw| commit file md5_hex | ) {
    ok(exists $rv->{$first_element}->[0]->{$k}, "Record has '$k' element");
}

$transitions = $self->examine_transitions($rv);
ok($transitions, "examine_transitions() returned true value");
is(ref($transitions), 'HASH', "examine_transitions() returned hash ref");
cmp_ok(scalar(keys %{$transitions}), '==', scalar(@{$target_args}),
    "Got expected number of elements: one for each of " . scalar(@{$target_args}) . " test files targeted");
$first_element = first { $_ } keys %{$transitions};
is(ref($transitions->{$first_element}), 'ARRAY', "Records are array references");
$expected_count = scalar(@{$self->get_commits_range}) - 1;
is(
    scalar(@{$transitions->{$first_element}}),
    $expected_count,
    "Got 1 element for each of $expected_count transitions between commits"
);
is(ref($transitions->{$first_element}->[0]), 'HASH', "Records are hash references");
for my $k ( qw| older newer compare | ) {
    ok(exists $transitions->{$first_element}->[0]->{$k}, "Record has '$k' element");
}

#pp($transitions);

undef $self;

#######################################

note("Second object");

my ($bisected_outputs, $bisected_outputs_undef_count, $m, $n, $o);

$self = Test::Multisect::Allcommits->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Test::Multisect::Allcommits');

$m = scalar(@{$target_args});
$full_targets = $self->set_targets($target_args);
ok($full_targets, "set_targets() returned true value");
is(ref($full_targets), 'ARRAY', "set_targets() returned array ref");
is_deeply(
    [ map { $_->{path} } @{$full_targets} ],
    [ map { "$self->{gitdir}/$_" } @{$target_args} ],
    "Got expected full paths to target files for testing",
);

note("prepare_multisect()");

$bisected_outputs = $self->prepare_multisect();
ok($bisected_outputs, "prepare_multisect() returned true value");
is(ref($bisected_outputs), 'ARRAY', "prepare_multisect() returned array ref");
cmp_ok(
    scalar(@{$bisected_outputs}),
    '==',
    scalar(@{$self->get_commits_range}),
    "Got expected number of elements in bisected outputs"
);
ok(scalar(@{$bisected_outputs->[0]}), "Array ref in first element is non-empty");
ok(scalar(@{$bisected_outputs->[-1]}), "Array ref in last element is non-empty");
$bisected_outputs_undef_count = 0;
for my $idx (1 .. ($#{$bisected_outputs} - 1)) {
    $bisected_outputs_undef_count++
        if defined $bisected_outputs->[$idx];
}
ok(! $bisected_outputs_undef_count,
    "After prepare_multisect(), internal elements are all as yet undefined");

#note("prepare_multisect_hash()");
#
#$bisected_outputs = $self->prepare_multisect_hash();
#ok($bisected_outputs, "prepare_multisect_hash() returned true value");
#is(ref($bisected_outputs), 'HASH', "prepare_multisect_hash() returned hash ref");
#$n = scalar(keys %{$bisected_outputs});
#is($n, $m,
#    "bisected_outputs hash has $m element(s) as expected");
#$o = $bisected_outputs->{$self->{targets}->[$m - 1]->{stub}};
#ok(defined $o->[0], "first element is defined");
#ok(defined $o->[$#{$o}], "last element is defined");
#$bisected_outputs_undef_count = 0;
#for my $idx (1 .. ($#{$o} - 1)) {
#    $bisected_outputs_undef_count++
#        if defined $o->[$idx];
#}
#ok(! $bisected_outputs_undef_count,
#    "After prepare_multisect_hash(), internal elements are all as yet undefined");
