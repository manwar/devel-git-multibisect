package Devel::Git::MultiBisect::BuildTransitions;
use strict;
use warnings;
use v5.10.0;
use parent ( qw| Devel::Git::MultiBisect | );
use Devel::Git::MultiBisect::Auxiliary qw(
    hexdigest_one_file
    validate_list_sequence
);
use Carp;
use Cwd;
use List::Util qw(first sum);
use File::Spec;
use File::Temp qw( tempdir );
use Data::Dump qw(dd pp);

our $VERSION = '0.08';

=head1 NAME

Devel::Git::MultiBisect::BuildTransitions - Gather build-time output where it changes over a range of F<git> commits

=head1 SYNOPSIS

    use Devel::Git::MultiBisect::BuildTransitions;

    $self = Devel::Git::MultiBisect::BuildTransitions->new(\%parameters);

    $commit_range = $self->get_commits_range();

    $self->multisect_builds();

    $multisected_outputs = $self->get_multisected_outputs();

    $transitions = $self->inspect_transitions();
}

=head1 DESCRIPTION

TK

When the number of commits in the specified range is large and you only need
the build-time output at those commits where the output materially changed, you can
use this package, F<Devel::Git::MultiBisect::BuildTransitions>.

=head1 METHODS

=head2 C<new()>

=cut

sub new {
    my ($class, $params) = @_;

    my $data = Devel::Git::MultiBisect::Init::init($params);

    delete $data->{targets};
    delete $data->{test_command};

    return bless $data, $class;
}

=head2 C<multisect_builds()>

=over 4

=item * Purpose

With a given set of configuration options and a specified range of F<git>
commits, identify the point where the "build command" -- typically, F<make>
-- first threw exceptions and then all subsequent commits where the build-time
exceptions materially changed.  A "material change" would be either a
correction of all exceptions or a set of different build-time exceptions from
those first observed.  Store the test output at those transition points for
human inspection.

=item * Arguments

    $self->multisect_builds();

None; all data needed is already present in the object.

=item * Return Value

Returns true value upon success.

=item * Comment

As C<multisect_builds()> runs it does two kinds of things:

=over 4

=item *

It stores results data within the object which you can subsequently access through method calls.

=item *

It captures error messages from each commit run and writes them to a file on
disk for later human inspection.

=back

=back

=cut

sub multisect_builds {
    my ($self) = @_;

    # Prepare data structures in the object to hold results of build runs on a
    # per target, per commit basis.
    # Also, "prime" the data structure by performing build runs for each target
    # on the first and last commits in the commit range, storing that build
    # output on disk as well.

    my $start_time = time();
    my $all_outputs = $self->_prepare_for_multisection();
    #say STDERR "AAA: In multisect_builds(), after _prepare_for_multisection()";
    #pp($all_outputs);

=pod

At this point, C<$all_outputs> is an array ref with one
element per commit in the commit range.  If a commit has been visited, the
element is a hash ref with 4 key-value pairs like the ones below.  If the
commit has not yet been visited, the element is C<undef>.

    [
      {
        commit => "7c9c5138c6a704d1caf5908650193f777b81ad23",
        commit_short => "7c9c513",
        file => "/home/jkeenan/learn/perl/multisect/7c9c513.make.errors.rpt.txt",
        md5_hex => "d41d8cd98f00b204e9800998ecf8427e",
      },
      undef,
      undef,
    ...
      undef,
      {
        commit => "8f6628e3029399ac1e48dfcb59c3cd30e5127c3e",
        commit_short => "8f6628e",
        file => "/home/jkeenan/learn/perl/multisect/8f6628e.make.errors.rpt.txt",
        md5_hex => "fdce7ff2f07a0a8cd64005857f4060d4",
      },
    ]

Unlike F<Devel::Git::MultiBisect::Transitions -- where we could have been
testing multiple test files on each commit -- here we're only concerned with
recording the presence or absence of build-time errors.  Hence, we only need
an array of hash refs rather than an array of arrays of hash refs.

The multisection process will entail running C<run_build_on_one_commit()> over
each commit selected by the multisection algorithm.  Each run will insert a hash
ref with the 4 KVPs into C<@{$self-E<gt>{all_outputs}}>.  At the end of the
multisection process those elements which we did not need to visit will still be
C<undef>.  We will then analyze the defined elements to identify the
transitional commits.

The objective of multisection is to identify the git commits at which the
build output -- as reflected in a file on disk holding a list of normalized
errors -- materially changed.  We are using an md5_hex value for that error
file as a presumably valid unique identifier for that file's content.  A
transition point is a commit at which the output file's md5_hex differs from
that of the immediately preceding commit.  So, to identify the first
transition point, we need to locate the commit at which the md5_hex changed
from that found in the very first commit in the designated commit range.  Once
we've identified the first transition point, we'll look for the second
transition point, i.e., that where the md5_hex changed from that observed at
the first transition point.  We'll continue that process until we get to a
transition point where the md5_hex is identical to that of the very last
commit in the commit range.

=cut


#    my $target_count = scalar(@{$self->{targets}});
#    my $max_target_idx = $#{$self->{targets}};
#
#    # 1 element per test target file, keyed on stub, value 0 or 1
#    my %overall_status = map { $self->{targets}->[$_]->{stub} => 0 } (0 .. $max_target_idx);
#
#    # Overall success criterion:  We must have completed multisection --
#    # identified all transitional commits -- for each target and recorded that
#    # completion with a '1' in its element in %overall_status.  If we have
#    # achieved that, then each element in %overall_status will have the value
#    # '1' and they will sum up to the total number of test files being
#    # targeted.
#
#    until (sum(values(%overall_status)) == $target_count) {
#        if ($self->{verbose}) {
#            say "target count|sum of status values: ",
#                join('|' => $target_count, sum(values(%overall_status)));
#        }
#
#        # Target and process one file at a time.  To multisect a target is to
#        # identify all its transitional commits over the commit range.
#
#        for my $target_idx (0 .. $max_target_idx) {
#            my $target = $self->{targets}->[$target_idx];
#            if ($self->{verbose}) {
#                say "Targeting file: $target->{path}";
#            }
#
#            my $rv = $self->_multisect_one_target($target_idx);
#            if ($rv) {
#                $overall_status{$target->{stub}}++;
#            }
#        }
#    } # END until loop
    my $end_time = time();
#    my %distinct_commits = ();
#    for my $target (keys %{$self->{multisected_outputs}}) {
#        for my $el (@{$self->{multisected_outputs}->{$target}}) {
#            if (defined $el) {
#                $distinct_commits{$el->{commit}} = 1;
#            }
#        }
#    }
    my %timings = (
	    elapsed	=> $end_time - $start_time,
        #runs => scalar(keys(%distinct_commits)),
        runs => scalar( grep {defined $_} @{$self->{all_outputs}} ),
    );
    $timings{mean} = sprintf("%.02f" => $timings{elapsed} / $timings{runs});
    if ($self->{verbose}) {
        say "Ran $timings{runs} runs; elapsed: $timings{elapsed} sec; mean: $timings{mean} sec";
    }
    $self->{timings}	  = \%timings;

    return 1;
}

sub _prepare_for_multisection {
    my $self = shift;

    # get_commits_range is inherited from parent

    my $all_commits = $self->get_commits_range();
    $self->{all_outputs} = [ (undef) x scalar(@{$all_commits}) ];

    my %multisected_outputs_table;
    for my $idx (0, $#{$all_commits}) {

        my $outputs = $self->run_build_on_one_commit($all_commits->[$idx]);
        $self->{all_outputs}->[$idx] = $outputs;
#        for my $target (@{$outputs}) {
#            my @other_keys = grep { $_ ne 'file_stub' } keys %{$target};
#            $multisected_outputs_table{$target->{file_stub}}[$idx] =
#                { map { $_ => $target->{$_} } @other_keys };
#        }
    }
#    $self->{multisected_outputs} = { %multisected_outputs_table };
##pp($self->{all_outputs});
#    return \%multisected_outputs_table;
    return $self->{all_outputs};
}

sub run_build_on_one_commit {
    my ($self, $commit) = @_;
    $commit //= $self->{commits}->[0]->{sha};
    say "Building commit: $commit" if ($self->{verbose});

    my $starting_branch = $self->_configure_one_commit($commit);

    my $outputsref = $self->_build_one_commit($commit);
    say "Tested commit:  $commit; returning to: $starting_branch"
        if ($self->{verbose});

    # We want to return to our basic branch (e.g., 'master', 'blead')
    # before checking out a new commit.

    system(qq|git checkout --quiet $starting_branch|)
        and croak "Unable to 'git checkout --quiet $starting_branch";

    $self->{commit_counter}++;
    say "Commit counter: $self->{commit_counter}" if $self->{verbose};

    return $outputsref;
}

sub _configure_one_commit {
    my ($self, $commit) = @_;
    chdir $self->{gitdir} or croak "Unable to change to $self->{gitdir}";
    system(qq|git clean --quiet -dfx|) and croak "Unable to 'git clean --quiet -dfx'";
    my $starting_branch = $self->{branch};

    system(qq|git checkout --quiet $commit|) and croak "Unable to 'git checkout --quiet $commit'";
    say "Running '$self->{configure_command}'" if $self->{verbose};
    system($self->{configure_command}) and croak "Unable to run '$self->{configure_command})'";
    return $starting_branch;
}

sub _build_one_commit {
    my ($self, $commit) = @_; 
    my $short_sha = substr($commit,0,$self->{short});
    #my @outputs;
    my $build_log = File::Spec->catfile(
        $self->{outputdir},
        join('.' => (
            $short_sha,
            'make',
            'output',
            'txt'
        )),
    );
    my $command_raw = $self->{make_command};
    my $cmd = qq|$command_raw > $build_log 2>&1|;
    say "Running '$cmd'" if $self->{verbose};
    my $rv = system($cmd);
    my $filtered_errors_file = $self->_filter_build_log($build_log, $short_sha);
    say "Created $filtered_errors_file" if $self->{verbose};
    return {
        commit => $commit,
        commit_short => $short_sha,
        file => $filtered_errors_file,
        md5_hex => hexdigest_one_file($filtered_errors_file),
    };
    #return \@outputs;
}

sub _filter_build_log {
    my ($self, $buildlog, $short_sha) = @_;
    say "short_sha: $short_sha";
    my $tdir = tempdir( CLEANUP => 1 );
    
    my $ackpattern = q|-A2 '^[^:]+:\d+:\d+:\s+error:'|;
    my @raw_acklines = grep { ! m/^--\n/ } `ack $ackpattern $buildlog`;
    chomp(@raw_acklines);
    #pp(\@raw_acklines);
    croak "Got incorrect count of lines from ack; should be divisible by 3"
        unless scalar(@raw_acklines) % 3 == 0;
    
    my @refined_errors = ();
    for (my $i=0; $i <= $#raw_acklines; $i += 3) {
        my $j = $i + 2;
        my @this_error = ();
        my ($normalized) =
            $raw_acklines[$i] =~ s/^([^:]+):\d+:\d+:(.*)$/$1:_:_:$2/r;
        push @this_error, ($normalized, @raw_acklines[$i+1 .. $j]);
        push @refined_errors, \@this_error;
    }
    
    my $error_report_file =
        File::Spec->catfile($self->{workdir}, "$short_sha.make.errors.rpt.txt");
    say "rpt: $error_report_file";
    open my $OUT, '>', $error_report_file
        or croak "Unable to open $error_report_file for writing";
    if (@refined_errors) {
        for (my $i=0; $i<=($#refined_errors -1); $i++) {
            say $OUT join "\n" => @{$refined_errors[$i]};
            say $OUT "--";
        }
        say $OUT join "\n" => @{$refined_errors[-1]};
    }
    close $OUT or croak "Unable to close $error_report_file after writing";
    return $error_report_file;
}

###########################################################

#sub _multisect_one_target {
#    my ($self, $target_idx) = @_;
#    croak "Must supply index of test file within targets list"
#        unless(defined $target_idx and $target_idx =~ m/^\d+$/);
#    croak "You must run _prepare_for_multisection() before any stand-alone run of _multisect_one_target()"
#        unless exists $self->{multisected_outputs};
#    my $target  = $self->{targets}->[$target_idx];
#    my $stub    = $target->{stub};
#
#    # The condition for successful multisection of one particular test file
#    # target is that the list of md5_hex values for files holding the output of TAP
#    # run over the commit range exhibit the following behavior:
#
#    # The list is composed of sub-sequences (a) whose elements are either (i)
#    # the md5_hex value for the TAP outputfiles at a given commit or (ii)
#    # undefined; (b) if defined, the md5_values are all identical; (c) the
#    # first and last elements of the sub-sequence are both defined; and (d)
#    # the sub-sequence's unique defined value never reoccurs in any subsequent
#    # sub-sequence.
#
#    # For each run of _multisect_one_target() over a given target, it will
#    # return a true value (1) if the above condition(s) are met and 0
#    # otherwise.  The caller (multisect_builds()) will handle that return
#    # value appropriately.  The caller will then call _multisect_one_target()
#    # on the next target, if any.
#
#    # The objective of multisection is to identify the git commits at which
#    # the test output targeted materially changed.  We are using
#    # an md5_hex value for that test file as a presumably valid unique
#    # identifier for that file's content.  A transition point is a commit at
#    # which the output file's md5_hex differs from that of the immediately
#    # preceding commit.  So, to identify the first transition point for a
#    # given target, we need to locate the commit at which the md5_hex changed
#    # from that found in the very first commit in the designated commit range.
#    # Once we've identified the first transition point, we'll look for the
#    # second transition point, i.e., that where the md5_hex changed from that
#    # observed at the first transition point.  We'll continue that process
#    # until we get to a transition point where the md5_hex is identical to
#    # that of the very last commit in the commit range.
#
#    # This entails checking out the source code at each commit calculated by
#    # the bisection algorithm, configuring and building the code, running the
#    # test targets at that commit, computing their md5_hex values and storing
#    # them in the 'multisected_outputs' structure.  The _prepare_for_multisection()
#    # method will pre-populate that structure with md5_hexes for each test
#    # file for each of the first and last commits in the commit range.
#
#    # Since the configuration and build at a particular commit may be
#    # time-consuming, once we have completed those steps we will run all the
#    # test files at once and store their results in 'multisected_outputs'
#    # immediately.  We will make our bisection decision based only on analysis
#    # of the current target.  But when we come to the second target file we
#    # will be able to skip configuration, build and test-running at commits
#    # visited during the pass over the first target file.
#
#    my ($min_idx, $max_idx)     = (0, $#{$self->{commits}});
#    my $this_target_status      = 0;
#    my $current_start_idx       = $min_idx;
#    my $current_end_idx         = $max_idx;
#    my $overall_start_md5_hex   =
#            $self->{multisected_outputs}->{$stub}->[$min_idx]->{md5_hex};
#    my $overall_end_md5_hex     =
#            $self->{multisected_outputs}->{$stub}->[$max_idx]->{md5_hex};
#    my $excluded_targets = {};
#    my $n = 0;
#
#    while (! $this_target_status) {
#
#        # Start multisecting on this test target file: one transition point at
#        # a time until we've got them all for this test file.
#
#        # What gets (or may get) updated or assigned to in the course of one rep of this loop:
#        # $current_start_idx
#        # $current_end_idx
#        # $n
#        # $excluded_targets
#        # $self->{all_outputs}
#        # $self->{multisected_outputs}
#
#        my $h = sprintf("%d" => (($current_start_idx + $current_end_idx) / 2));
#        $self->_run_one_commit_and_assign($h);
#
#        my $current_start_md5_hex =
#            $self->{multisected_outputs}->{$stub}->[$current_start_idx]->{md5_hex};
#        my $target_h_md5_hex  =
#            $self->{multisected_outputs}->{$stub}->[$h]->{md5_hex};
#
#        # Decision criteria:
#        # If $target_h_md5_hex eq $current_start_md5_hex, then the first
#        # transition is *after* index $h.  Hence bisection should go upwards.
#
#        # If $target_h_md5_hex ne $current_start_md5_hex, then the first
#        # transition has come *before* index $h.  Hence bisection should go
#        # downwards.  However, since the test of where the first transition is
#        # is that index j-1 has the same md5_hex as $current_start_md5_hex but
#        #         index j   has a different md5_hex, we have to do a run on
#        #         j-1 as well.
#
#        if ($target_h_md5_hex ne $current_start_md5_hex) {
#            my $g = $h - 1;
#            $self->_run_one_commit_and_assign($g);
#            my $target_g_md5_hex  = $self->{multisected_outputs}->{$stub}->[$g]->{md5_hex};
#            if ($target_g_md5_hex eq $current_start_md5_hex) {
#                if ($target_h_md5_hex eq $overall_end_md5_hex) {
#                }
#                else {
#                    $current_start_idx  = $h;
#                    $current_end_idx    = $max_idx;
#                }
#                $n++;
#            }
#            else {
#                # Bisection should continue downwards
#                $current_end_idx = $h;
#                $n++;
#            }
#        }
#        else {
#            # Bisection should continue upwards
#            $current_start_idx = $h;
#            $n++;
#        }
#        $this_target_status = $self->_evaluate_status_one_target_run($target_idx);
#    }
#    return 1;
#}
#
#sub _evaluate_status_one_target_run {
#    my ($self, $target_idx) = @_;
#    my @trans = ();
#    for my $o (@{$self->{all_outputs}}) {
#        push @trans,
#            defined $o ? $o->[$target_idx]->{md5_hex} : undef;
#    }
#    my $vls = validate_list_sequence(\@trans);
#    return ( (scalar(@{$vls}) == 1 ) and ($vls->[0])) ? 1 : 0;
#}
#
#sub _run_one_commit_and_assign {
#
#    # If we've already stashed a particular commit's outputs in
#    # all_outputs (and, simultaneously) in multisected_outputs,
#    # then we don't need to actually perform a run.
#
#    # This internal method assigns to all_outputs and multisected_outputs in
#    # place.
#
#    my ($self, $idx) = @_;
#    my $this_commit = $self->{commits}->[$idx]->{sha};
#    unless (defined $self->{all_outputs}->[$idx]) {
#        say "\nAt commit counter $self->{commit_counter}, preparing to test commit ", $idx + 1, " of ", scalar(@{$self->{commits}})
#            if $self->{verbose};
#        my $these_outputs = $self->run_test_files_on_one_commit($this_commit);
#        $self->{all_outputs}->[$idx] = $these_outputs;
#
#        for my $target (@{$these_outputs}) {
#            my @other_keys = grep { $_ ne 'file_stub' } keys %{$target};
#            $self->{multisected_outputs}->{$target->{file_stub}}->[$idx] =
#                { map { $_ => $target->{$_} } @other_keys };
#        }
#    }
#}
#
#=head2 C<get_multisected_outputs()>
#
#=over 4
#
#=item * Purpose
#
#Get results of C<multisect_builds()> (other than test output files
#created) reported on a per target/per commit basis.
#
#=item * Arguments
#
#    my $multisected_outputs = $self->get_multisected_outputs();
#
#None; all data needed is already present in the object.
#
#=item * Return Value
#
#Reference to a hash with one element for each targeted test file.
#
#Each element's key is a "stub" version of the target's relative path below the
#F<git> checkout directory in which forward slashes and dot characters have
#been replaced with underscores.  So,
#
#    t/44_func_hashes_mult_unsorted.t
#
#... becomes:
#
#    t_44_func_hashes_mult_unsorted_t
#
#Each element's value is a reference to an array with one element for each
#commit in the commit range.
#
#=over 4
#
#=item *
#
#If a particular commit B<was not visited> in the course of
#C<multisect_builds()>, then the array element is undefined.  (The point
#of multisection, of course, is to B<not> have to visit every commit in the
#commit range in order to figure out the commits at which test output changed.)
#
#=item *
#
#If a particular commit B<was visited> in the course of
#C<multisect_builds()>, then the array element is a hash reference whose
#elements have the following keys:
#
#    commit
#    commit_short
#    file
#    md5_hex
#
#=back
#
#Example:
#
#    {
#      t_001_load_t => [
#          {
#            commit => "d2bd2c75a2fd9afd3ac65a808eea2886d0e41d01",
#            commit_short => "d2bd2c7",
#            file => "/tmp/LHEG4uXfj1/d2bd2c7.t_001_load_t.output.txt",
#            md5_hex => "318ce8b2ccb3e92a6e516e18d1481066",
#          },
#          undef,
#          {
#            commit => "f2bc0ec377776b42928a29cebe04954975a30eb2",
#            commit_short => "f2bc0ec",
#            file => "/tmp/LHEG4uXfj1/f2bc0ec.t_001_load_t.output.txt",
#            md5_hex => "318ce8b2ccb3e92a6e516e18d1481066",
#          },
#          # ...
#          },
#          {
#            commit => "199494ee204dd78ed69490f9e54115b0e83e7d39",
#            commit_short => "199494e",
#            file => "/tmp/LHEG4uXfj1/199494e.t_001_load_t.output.txt",
#            md5_hex => "d7125615b2e5dbb4750ff107bbc1bad3",
#          },
#        ],
#      t_002_add_t  => [
#          {
#            commit => "d2bd2c75a2fd9afd3ac65a808eea2886d0e41d01",
#            commit_short => "d2bd2c7",
#            file => "/tmp/LHEG4uXfj1/d2bd2c7.t_002_add_t.output.txt",
#            md5_hex => "0823e5d7628802e5a489661090109c56",
#          },
#          undef,
#          {
#            commit => "f2bc0ec377776b42928a29cebe04954975a30eb2",
#            commit_short => "f2bc0ec",
#            file => "/tmp/LHEG4uXfj1/f2bc0ec.t_002_add_t.output.txt",
#            md5_hex => "0823e5d7628802e5a489661090109c56",
#          },
#          # ...
#          {
#            commit => "199494ee204dd78ed69490f9e54115b0e83e7d39",
#            commit_short => "199494e",
#            file => "/tmp/LHEG4uXfj1/199494e.t_002_add_t.output.txt",
#            md5_hex => "7716009f1af9a562a3edad9e2af7dedc",
#          },
#        ],
#    }
#
#=back
#
#=cut
#
#sub get_multisected_outputs {
#    my $self = shift;
#    return $self->{multisected_outputs};
#}
#
#=head2 C<inspect_transitions()>
#
#=over 4
#
#=item * Purpose
#
#Get a data structure which reports on the most meaningful results of
#C<multisect_builds()>, namely, the first commit, the last commit and all
#transitional commits.
#
#=item * Arguments
#
#    my $transitions = $self->inspect_transitions();
#
#None; all data needed is already present in the object.
#
#=item * Return Value
#
#Reference to a hash with one element per target.  Each element's key is a
#"stub" version of the target's relative path below the F<git> checkout
#directory.  (See example in documentation for C<get_multisected_outputs>
#above.)
#
#Each element's value is another hash reference.  The elements of that hash
#will have the following keys:
#
#=over 4
#
#=item * C<oldest>
#
#Value is reference to hash keyed on C<idx>, C<md5_hex> and C<file>, whose
#values are, respectively, the index position of the very first commit in the
#commit range, the digest of that commit's test output and the path to the file
#holding that output.
#
#=item * C<newest>
#
#Value is reference to hash keyed on C<idx>, C<md5_hex> and C<file>, whose
#values are, respectively, the index position of the very last commit in the
#commit range, the digest of that commit's test output and the path to the file
#holding that output.
#
#=item * C<transitions>
#
#Value is reference to an array with one element for each transitional commit.
#Each such element is a reference to a hash with keys C<older> and C<newer>.
#In this context C<older> refers to the last commit in a sub-sequence with a
#particular digest; C<newer> refers to the next immediate commit which is the
#first commit in a new sub-sequence with a new digest.
#
#The values of C<older> and C<newer> are, in turn, references to hashes with
#keys C<idx>, C<md5_hex> and C<file>.  Their values are, respectively, the index
#position of the particular commit in the commit range, the digest of that
#commit's test output and the path to the file holding that output.
#
#=back
#
#Example:
#
#    {
#      t_001_load_t => {
#          newest => {
#            file => "/tmp/IvD3Zwn3FJ/199494e.t_001_load_t.output.txt",
#            idx => 13,
#            md5_hex => "d7125615b2e5dbb4750ff107bbc1bad3",
#          },
#          oldest => {
#            file => "/tmp/IvD3Zwn3FJ/d2bd2c7.t_001_load_t.output.txt",
#            idx => 0,
#            md5_hex => "318ce8b2ccb3e92a6e516e18d1481066",
#          },
#          transitions => [
#            {
#              newer => {
#                         file => "/tmp/IvD3Zwn3FJ/1debd8a.t_001_load_t.output.txt",
#                         idx => 5,
#                         md5_hex => "e5a839ea2e34b8976000c78c258299b0",
#                       },
#              older => {
#                         file => "/tmp/IvD3Zwn3FJ/707da97.t_001_load_t.output.txt",
#                         idx => 4,
#                         md5_hex => "318ce8b2ccb3e92a6e516e18d1481066",
#                       },
#            },
#            {
#              newer => {
#                         file => "/tmp/IvD3Zwn3FJ/6653d84.t_001_load_t.output.txt",
#                         idx => 8,
#                         md5_hex => "f4920ddfdd9f1e6fc21ebfab09b5fcfe",
#                       },
#              older => {
#                         file => "/tmp/IvD3Zwn3FJ/b35b4d7.t_001_load_t.output.txt",
#                         idx => 7,
#                         md5_hex => "e5a839ea2e34b8976000c78c258299b0",
#                       },
#            },
#            {
#              newer => {
#                         file => "/tmp/IvD3Zwn3FJ/aa1ed28.t_001_load_t.output.txt",
#                         idx => 12,
#                         md5_hex => "d7125615b2e5dbb4750ff107bbc1bad3",
#                       },
#              older => {
#                         file => "/tmp/IvD3Zwn3FJ/65bf77c.t_001_load_t.output.txt",
#                         idx => 11,
#                         md5_hex => "f4920ddfdd9f1e6fc21ebfab09b5fcfe",
#                       },
#            },
#          ],
#      },
#      t_002_add_t  => {
#          newest => {
#            file => "/tmp/IvD3Zwn3FJ/199494e.t_002_add_t.output.txt",
#            idx => 13,
#            md5_hex => "7716009f1af9a562a3edad9e2af7dedc",
#          },
#          oldest => {
#            file => "/tmp/IvD3Zwn3FJ/d2bd2c7.t_002_add_t.output.txt",
#            idx => 0,
#            md5_hex => "0823e5d7628802e5a489661090109c56",
#          },
#          transitions => [
#            {
#              newer => {
#                         file => "/tmp/IvD3Zwn3FJ/646fd8a.t_002_add_t.output.txt",
#                         idx => 3,
#                         md5_hex => "dbd8c7a70877b3c8d3fd93a7a66d8468",
#                       },
#              older => {
#                         file => "/tmp/IvD3Zwn3FJ/f2bc0ec.t_002_add_t.output.txt",
#                         idx => 2,
#                         md5_hex => "0823e5d7628802e5a489661090109c56",
#                       },
#            },
#            {
#              newer => {
#                         file => "/tmp/IvD3Zwn3FJ/b35b4d7.t_002_add_t.output.txt",
#                         idx => 7,
#                         md5_hex => "50aac31686ac930aad7fdd23df679f28",
#                       },
#              older => {
#                         file => "/tmp/IvD3Zwn3FJ/55ab1f9.t_002_add_t.output.txt",
#                         idx => 6,
#                         md5_hex => "dbd8c7a70877b3c8d3fd93a7a66d8468",
#                       },
#            },
#            {
#              newer => {
#                         file => "/tmp/IvD3Zwn3FJ/6653d84.t_002_add_t.output.txt",
#                         idx => 8,
#                         md5_hex => "256f466d35533555dce93a838ba5ab9d",
#                       },
#              older => {
#                         file => "/tmp/IvD3Zwn3FJ/b35b4d7.t_002_add_t.output.txt",
#                         idx => 7,
#                         md5_hex => "50aac31686ac930aad7fdd23df679f28",
#                       },
#            },
#            {
#              newer => {
#                         file => "/tmp/IvD3Zwn3FJ/abc336e.t_002_add_t.output.txt",
#                         idx => 9,
#                         md5_hex => "037be971470cb5d96a7a7f9764a6f3aa",
#                       },
#              older => {
#                         file => "/tmp/IvD3Zwn3FJ/6653d84.t_002_add_t.output.txt",
#                         idx => 8,
#                         md5_hex => "256f466d35533555dce93a838ba5ab9d",
#                       },
#            },
#            {
#              newer => {
#                         file => "/tmp/IvD3Zwn3FJ/65bf77c.t_002_add_t.output.txt",
#                         idx => 11,
#                         md5_hex => "7716009f1af9a562a3edad9e2af7dedc",
#                       },
#              older => {
#                         file => "/tmp/IvD3Zwn3FJ/bbe25f4.t_002_add_t.output.txt",
#                         idx => 10,
#                         md5_hex => "037be971470cb5d96a7a7f9764a6f3aa",
#                       },
#            },
#          ],
#      },
#    }
#
#=item * Comment
#
#The return value of C<inspect_transitions()> should be useful to the developer
#trying to determine the various points in a long series of commits where a
#target's test output changed in meaningful ways.  Hence, it is really the
#whole point of F<Devel::Git::MultiBisect::BuildTransitions>.
#
#=back
#
#=cut
#
#sub inspect_transitions {
#    my ($self) = @_;
#    my $multisected_outputs = $self->get_multisected_outputs();
#    my %transitions;
#    for my $k (sort keys %{$multisected_outputs}) {
#        my $arr = $multisected_outputs->{$k};
#        my $max_index = $#{$arr};
#        $transitions{$k}{transitions} = [];
#        $transitions{$k}{oldest} = {
#            idx     => 0,
#            md5_hex => $arr->[0]->{md5_hex},
#            file    => $arr->[0]->{file},
#        };
#        $transitions{$k}{newest} = {
#            idx     => $max_index,
#            md5_hex => $arr->[$max_index]->{md5_hex},
#            file    => $arr->[$max_index]->{file},
#        };
#        for (my $j = 1; $j <= $max_index; $j++) {
#            my $i = $j - 1;
#            next unless ((defined $arr->[$i]) and (defined $arr->[$j]));
#            my $older_md5_hex   = $arr->[$i]->{md5_hex};
#            my $newer_md5_hex   = $arr->[$j]->{md5_hex};
#            my $older_file      = $arr->[$i]->{file};
#            my $newer_file      = $arr->[$j]->{file};
#            unless ($older_md5_hex eq $newer_md5_hex) {
#                push @{$transitions{$k}{transitions}}, {
#                    older => { idx => $i, md5_hex => $older_md5_hex, file => $older_file },
#                    newer => { idx => $j, md5_hex => $newer_md5_hex, file => $newer_file },
#                }
#            }
#        }
#    }
#    return \%transitions;
#}

1;

__END__
This package inherits methods from F<Devel::Git::MultiBisect>.  Only methods unique to
F<Devel::Git::MultiBisect::AllCommits> are documented here.  See the documentation for
F<Devel::Git::MultiBisect> for all other methods, including:

    new()
    get_commits_range()

