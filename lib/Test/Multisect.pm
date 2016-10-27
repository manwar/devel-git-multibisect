package Test::Multisect;
use strict;
use warnings;
use v5.10.0;
use Test::Multisect::Opts qw( process_options );
use Test::Multisect::Auxiliary qw(
    clean_outputfile
    hexdigest_one_file
    validate_list_sequence
);
use Carp;
use Cwd;
use File::Temp;
use List::Util qw(first sum);
use Data::Dump qw( pp );

our $VERSION = '0.01';

=head1 NAME

Test::Multisect - Study test output over a range of git commits

=head1 SYNOPSIS

    use Test::Multisect;

    $self = Test::Multisect->new(\%parameters);

    $commit_range = $self->get_commits_range();

    $full_targets = $self->set_targets(\@target_args);

    $outputs = $self->run_test_files_on_one_commit($commit_range->[0]);

    $all_outputs = $self->run_test_files_on_all_commits();

    $rv = $self->get_digests_by_file_and_commit();

    $transitions = $self->examine_transitions();

=head1 DESCRIPTION

Given a Perl library or application kept in F<git> for version control, it is
often useful to be able to compare the output collected from running one or
several test files over a range of git commits.  If that range is sufficiently
large, a test may fail in B<more than one way> over that range.

If that is the case, then simply asking, I<"When did this file start to
fail?"> is insufficient.  We may want to capture the test output for each
commit, or, more usefully, may want to capture the test output only at those
commits where the output changed.

F<Test::Multisect> provides methods to achieve that objective.

=head1 METHODS

=head2 C<new()>

=over 4

=item * Purpose

Test::Multisect constructor.

=item * Arguments

    $self = Test::Multisect->new(\%params);

Reference to a hash, typically the return value of
C<Test::Multisect::Opts::process_options()>.

The hashref passed as argument must contain key-value pairs for C<gitdir>,
C<workdir> and C<outputdir>.  C<new()> tests for the existence of each of
these directories.

=item * Return Value

Test::Multisect object.

=item * Comment

=back

=cut

sub new {
    my ($class, $params) = @_;
    my %data;

    while (my ($k,$v) = each %{$params}) {
        $data{$k} = $v;
    }

    my @missing_dirs = ();
    for my $dir ( qw| gitdir workdir outputdir | ) {
        push @missing_dirs, $data{$dir}
            unless (-d $data{$dir});
    }
    if (@missing_dirs) {
        croak "Cannot find directory(ies): @missing_dirs";
    }

    $data{last_short} = substr($data{last}, 0, $data{short});
    $data{commits} = _get_commits(\%data);

    return bless \%data, $class;
}

sub _get_commits {
    my $dataref = shift;
    my $cwd = cwd();
    chdir $dataref->{gitdir} or croak "Unable to chdir";
    my @commits = ();
    my ($older, $cmd);
    my ($fh, $err) = File::Temp::tempfile();
    if ($dataref->{last_before}) {
        $older = '^' . $dataref->{last_before};
        $cmd = "git rev-list --reverse $older $dataref->{last} 2>$err";
    }
    else {
        $older = $dataref->{first} . '^';
        $cmd = "git rev-list --reverse ${older}..$dataref->{last} 2>$err";
    }
    chomp(@commits = `$cmd`);
    if (! -z $err) {
        open my $FH, '<', $err or croak "Unable to open $err for reading";
        my $error = <$FH>;
        chomp($error);
        close $FH or croak "Unable to close $err after reading";
        croak $error;
    }
    my @extended_commits = map { {
        sha     => $_,
        short   => substr($_, 0, $dataref->{short}),
    } } @commits;
    chdir $cwd or croak "Unable to return to original directory";
    return [ @extended_commits ];
}

=head2 C<get_commits_range()>

=over 4

=item * Purpose

Identify the SHAs of each git commit identified by C<new()>.

=item * Arguments

    $commit_range = $self->get_commits_range();

None; all data needed is already in the object.

=item * Return Value

Array reference, each element of which is a SHA.

=item * Comment

=back

=cut

sub get_commits_range {
    my $self = shift;
    return [  map { $_->{sha} } @{$self->{commits}} ];
}

=head2 C<set_targets()>

=over 4

=item * Purpose

Identify the test files which will be run at different points in the commits range.

=item * Arguments

    $target_args = [
        't/44_func_hashes_mult_unsorted.t',
        't/45_func_hashes_alt_dual_sorted.t',
    ];
    $full_targets = $self->set_targets($target_args);

Reference to an array holding the relative paths beneath the C<gitdir> to the
test files selected for examination.

=item * Return Value

Reference to an array holding hash references with these elements:

=over 4

=item * C<path>

Absolute paths to the test files selected for examination.  Test file is
tested for its existence.

=item * C<stub>

String composed by taking an element in the array ref passed as argument and substituting underscores C(<_>) for forward slash (C</>) and dot (C<.>) characters.  So,

    t/44_func_hashes_mult_unsorted.t

... becomes:

    t_44_func_hashes_mult_unsorted_t'

=item * Comment

=back

=back

=cut

sub set_targets {
    my ($self, $targets) = @_;

    my @raw_targets = ();
    if (defined $self->{targets} and @{$self->{targets}}) {
        @raw_targets = @{$self->{targets}};
    }

    # If set_targets() is provided with an appropriate argument, override
    # whatever may have been stored in the object by new().

    if (defined $targets and ref($targets) eq 'ARRAY') {
        @raw_targets = @{$targets};
    }

    my @full_targets = ();
    my @missing_files = ();
    for my $rt (@raw_targets) {
        my $ft = "$self->{gitdir}/$rt";
        if (! -e $ft) { push @missing_files, $ft; next }
        my $stub;
        ($stub = $rt) =~ s{[./]}{_}g;
        push @full_targets, {
            path    => $ft,
            stub    => $stub,
        };
    }
    if (@missing_files) {
        croak "Cannot find file(s) to be tested: @missing_files";
    }
    $self->{targets} = [ @full_targets ];
    return \@full_targets;
}

=head2 C<run_test_files_on_one_commit()>

=over 4

=item * Purpose

Capture the output from running the selected test files at one specific git checkout.

=item * Arguments

    $outputs = $self->run_test_files_on_one_commit("2a2e54a");

or

    $excluded_targets = [
        't/45_func_hashes_alt_dual_sorted.t',
    ];
    $outputs = $self->run_test_files_on_one_commit("2a2e54a", $excluded_targets);

=over 4

=item 1

String holding the SHA from a single commit in the repository.  This string
would typically be one of the elements in the array reference returned by
C<$self->get_commits_range()>.  If no argument is provided, the method will
default to using the first element in the array reference returned by
C<$self->get_commits_range()>.

=item 2

Reference to array of target test files to be excluded from a particular invocation of this method.  Optional, but will die if argument is not an array reference.

=back

=item * Return Value

Reference to an array, each element of which is a hash reference with the
following elements:

=over 4

=item * C<commit>

String holding the SHA from the commit passed as argument to this method (or
the default described above).

=item * C<commit_short>

String holding the value of C<commit> (above) to the number of characters
specified in the C<short> element passed to the constructor; defaults to 7.

=item * C<file_stub>

String holding a rewritten version of the relative path beneath C<gitdir> of
the test file being run.  In this relative path forward slash (C</>) and dot
(C<.>) characters are changed to underscores C(<_>).  So,

    t/44_func_hashes_mult_unsorted.t

... becomes:

    t_44_func_hashes_mult_unsorted_t'

=item * C<file>

String holding the full path to the file holding the TAP output collected
while running one test file at the given commit.  The following example shows
how that path is calculated.  Given:

    output directory (outputdir)    => '/tmp/DQBuT_SRAY/'
    SHA (commit)                    => '2a2e54af709f17cc6186b42840549c46478b6467'
    shortened SHA (commit_short)    => '2a2e54a'
    test file (target->[$i])        => 't/44_func_hashes_mult_unsorted.t'

... the file is placed in the directory specified by C<outputdir>.  We then
join C<commit_short> (the shortened SHA), C<file_stub> (the rewritten relative
path) and the strings C<output> and C<txt> with a dot to yield this value for
the C<file> element:

    2a2e54a.t_44_func_hashes_mult_unsorted_t.output.txt

=item * C<md5_hex>

String holding the return value of
C<Test::Multisect::Auxiliary::hexdigest_one_file()> run with the file
designated by the C<file> element as an argument.  (More precisely, the file
as modified by C<Test::Multisect::Auxiliary::clean_outputfile()>.)

=back

Example:

    [
      {
        commit => "2a2e54af709f17cc6186b42840549c46478b6467",
        commit_short => "2a2e54a",
        file => "/tmp/1mVnyd59ee/2a2e54a.t_44_func_hashes_mult_unsorted_t.output.txt",
        file_stub => "t_44_func_hashes_mult_unsorted_t",
        md5_hex => "31b7c93474e15a16d702da31989ab565",
      },
      {
        commit => "2a2e54af709f17cc6186b42840549c46478b6467",
        commit_short => "2a2e54a",
        file => "/tmp/1mVnyd59ee/2a2e54a.t_45_func_hashes_alt_dual_sorted_t.output.txt",
        file_stub => "t_45_func_hashes_alt_dual_sorted_t",
        md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
      },
    ]

=item * Comment

In this method's current implementation, we start with a C<git checkout> from
the repository at the specified C<commit>.  We configure (I<e.g.,> C<perl
Makefile.PL>) and build (I<e.g.,> C<make>) the source code.  We then test each
of the test files we have targeted (I<e.g.,> C<prove -vb
relative/path/to/test_file.t>).  We redirect both STDOUT and STDERR to
C<outputfile>, clean up the outputfile to remove the line containing timings
(as that introduces unwanted variability in the C<md5_hex> values) and compute
the digest.

This implementation is very much subject to change.

If a true value for C<verbose> has been passed to the constructor, the method
prints C<Created [outputfile]> to STDOUT before returning.

=back

=cut

sub _configure_build_one_commit {
    my ($self, $commit) = @_;
    chdir $self->{gitdir} or croak "Unable to change to $self->{gitdir}";
    system(qq|git clean --quiet -dfx|) and croak "Unable to 'git clean --quiet -dfx'";
    my @branches = qx{git branch};
    chomp(@branches);
    my ($cb, $current_branch);
    $cb = first { m/^\*\s+?/ } @branches;
    ($current_branch) = $cb =~ m{^\*\s+?(.*)};

    system(qq|git checkout --quiet $commit|) and croak "Unable to 'git checkout --quiet $commit'";
    system($self->{configure_command}) and croak "Unable to run '$self->{configure_command})'";
    system($self->{make_command}) and croak "Unable to run '$self->{make_command})'";
    return $current_branch;
}

sub run_test_files_on_one_commit {
    my ($self, $commit, $excluded_targets) = @_;
    if (defined $excluded_targets) {
        if (ref($excluded_targets) ne 'ARRAY') {
            croak "excluded_targets, if defined, must be in array reference";
        }
    }
    else {
        $excluded_targets = [];
    }
    my %excluded_targets;
    for my $t (@{$excluded_targets}) {
        $excluded_targets{"$self->{gitdir}/$t"}++;
    }

    my @current_targets = grep { ! exists $excluded_targets{$_->{path}} } @{$self->{targets}};
    $commit //= $self->{commits}->[0]->{sha};
    my $short = substr($commit,0,$self->{short});

    my $current_branch = $self->_configure_build_one_commit($commit);

    my @outputs;
    for my $target (@current_targets) {
        my $outputfile = join('/' => (
            $self->{outputdir},
            join('.' => (
                $short,
                $target->{stub},
                'output',
                'txt'
            )),
        ));
        my $cmd = qq|$self->{test_command} $target->{path} >$outputfile 2>&1|;
        system($cmd) and croak "Unable to run test_command";
        $outputfile = clean_outputfile($outputfile);
        push @outputs, {
            commit => $commit,
            commit_short => $short,
            file => $outputfile,
            file_stub => $target->{stub},
            md5_hex => hexdigest_one_file($outputfile),
        };
        say "Created $outputfile" if $self->{verbose};
    }
    system(qq|git checkout $current_branch|) and croak "Unable to 'git checkout $current_branch";
    return \@outputs;
}

=head2 C<run_test_files_on_all_commits()>

=over 4

=item * Purpose

Capture the output from a run of the selected test files at each specific git
checkout in the selected commit range.

=item * Arguments

    $all_outputs = $self->run_test_files_on_all_commits();

None; all data needed is already present in the object.

=item * Return Value

Array reference, each of whose elements is an array reference, each of whose elements is a hash reference with the same four keys as in the return value from C<run_test_files_on_one_commit()>:

    commit
    commit_short
    file
    md5_hex

Example:

    [
      # Array where each element corresponds to a single git checkout

      [
        # Array where each element corresponds to one of the selected test
        # files (here, 2 test files were targetd)

        {
          # Hash where each element correponds to the result of running a
          # single test file at a single commit point

          commit => "2a2e54af709f17cc6186b42840549c46478b6467",
          commit_short => "t_44_func_hashes_mult_unsorted_t",
          file => "/tmp/BrihPrp0qw/2a2e54a.t_44_func_hashes_mult_unsorted_t.output.txt",
          md5_hex => "31b7c93474e15a16d702da31989ab565",
        },
        {
          commit => "2a2e54af709f17cc6186b42840549c46478b6467",
          commit_short => "t_45_func_hashes_alt_dual_sorted_t",
          file => "/tmp/BrihPrp0qw/2a2e54a.t_45_func_hashes_alt_dual_sorted_t.output.txt",
          md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
        },
      ],
      [
        {
          commit => "a624024294a56964eca53ec4617a58a138e91568",
          commit_short => "t_44_func_hashes_mult_unsorted_t",
          file => "/tmp/BrihPrp0qw/a624024.t_44_func_hashes_mult_unsorted_t.output.txt",
          md5_hex => "31b7c93474e15a16d702da31989ab565",
        },
        {
          commit => "a624024294a56964eca53ec4617a58a138e91568",
          commit_short => "t_45_func_hashes_alt_dual_sorted_t",
          file => "/tmp/BrihPrp0qw/a624024.t_45_func_hashes_alt_dual_sorted_t.output.txt",
          md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
        },
      ],
    # ...
      [
        {
          commit => "d304a207329e6bd7e62354df4f561d9a7ce1c8c2",
          commit_short => "t_44_func_hashes_mult_unsorted_t",
          file => "/tmp/BrihPrp0qw/d304a20.t_44_func_hashes_mult_unsorted_t.output.txt",
          md5_hex => "31b7c93474e15a16d702da31989ab565",
        },
        {
          commit => "d304a207329e6bd7e62354df4f561d9a7ce1c8c2",
          commit_short => "t_45_func_hashes_alt_dual_sorted_t",
          file => "/tmp/BrihPrp0qw/d304a20.t_45_func_hashes_alt_dual_sorted_t.output.txt",
          md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
        },
      ],
    ]

=item * Comment

Note:  If the number of commits in the commits range is large, this method
will take a long time to run.  That time will be even longer if the
configuration and build times for each commit are large.  For example, to run
one test over 160 commits from the Perl 5 core distribution might take 15
hours.  YMMV.

The implementation of this method is very much subject to change.

=back

=cut

sub run_test_files_on_all_commits {
    my $self = shift;
    my $all_commits = $self->get_commits_range();
    my @all_outputs;
    for my $commit (@{$all_commits}) {
        my $outputs = $self->run_test_files_on_one_commit($commit);
        push @all_outputs, $outputs;
    }
    $self->{all_outputs} = [ @all_outputs ];
    return \@all_outputs;
}

=head2 C<get_digests_by_file_and_commit()>

=over 4

=item * Purpose

Present the same outcomes as C<run_test_files_on_all_commits()>, but formatted by target file, then commit.

=item * Arguments

    $rv = $self->get_digests_by_file_and_commit();

None; all data needed is already present in the object.

=item * Return Value

Reference to a hash keyed on the basename of the target file, modified to substitute underscores for forward slashes and dots.  The value of each element in the hash is a reference to an array which, in turn, holds a list of hash references, one per git commit.  Each such hash has the following keys:

    commit
    file
    md5_hex

Example:

    {
      t_44_func_hashes_mult_unsorted_t   => [
          {
            commit  => "2a2e54af709f17cc6186b42840549c46478b6467",
            file    => "/tmp/Xhilc8ZSgS/2a2e54a.t_44_func_hashes_mult_unsorted_t.output.txt",
            md5_hex => "31b7c93474e15a16d702da31989ab565",
          },
          {
            commit  => "a624024294a56964eca53ec4617a58a138e91568",
            file    => "/tmp/Xhilc8ZSgS/a624024.t_44_func_hashes_mult_unsorted_t.output.txt",
            md5_hex => "31b7c93474e15a16d702da31989ab565",
          },
          # ...
          {
            commit  => "d304a207329e6bd7e62354df4f561d9a7ce1c8c2",
            file    => "/tmp/Xhilc8ZSgS/d304a20.t_44_func_hashes_mult_unsorted_t.output.txt",
            md5_hex => "31b7c93474e15a16d702da31989ab565",
          },
      ],
      t_45_func_hashes_alt_dual_sorted_t => [
          {
            commit  => "2a2e54af709f17cc6186b42840549c46478b6467",
            file    => "/tmp/Xhilc8ZSgS/2a2e54a.t_45_func_hashes_alt_dual_sorted_t.output.txt",
            md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
          },
          {
            commit  => "a624024294a56964eca53ec4617a58a138e91568",
            file    => "/tmp/Xhilc8ZSgS/a624024.t_45_func_hashes_alt_dual_sorted_t.output.txt",
            md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
          },
          # ...
          {
            commit  => "d304a207329e6bd7e62354df4f561d9a7ce1c8c2",
            file    => "/tmp/Xhilc8ZSgS/d304a20.t_45_func_hashes_alt_dual_sorted_t.output.txt",
            md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
          },
      ],
    }


=item * Comment

This method currently may be called only after calling
C<run_test_files_on_all_commits()> and will die otherwise.

=back

=cut

sub get_digests_by_file_and_commit {
    my $self = shift;
    unless (exists $self->{all_outputs}) {
        croak "You must call run_test_files_on_all_commits() before calling get_digests_by_file_and_commit()";
    }
    my $rv = {};
    for my $commit (@{$self->{all_outputs}}) {
        for my $target (@{$commit}) {
            push @{$rv->{$target->{file_stub}}},
                {
                    commit  => $target->{commit},
                    file    => $target->{file},
                    md5_hex => $target->{md5_hex},
                };
        }
    }
    return $rv;
}

=head2 C<examine_transitions()>

=over 4

=item * Purpose

Determine whether a run of the same targeted test file run at two consecutive
commits produced the same or different output (as measured by string equality
or inequality of each commit's md5_hex value.

=item * Arguments

    $hashref = $self->get_digests_by_file_and_commit();

    $transitions = $self->examine_transitions($hashref);

Hash reference returned by C<get_digests_by_file_and_commit()>;

=item * Return Value

Reference to a hash keyed on the basename of the target file, modified to
substitute underscores for forward slashes and dots.  The value of each
element in the hash is a reference to an array which, in turn, holds a list of
hash references, one per each pair of consecutive git commits.  Each such hash
has the following keys:

    older
    newer
    compare

The value for each of the C<older> and C<newer> elements is a reference to a
hash with two elements:

    md5_hex
    idx

... where C<md5_hex> is the digest of the test output file and C<idx> is the
position (count starting at C<0>) of that element in the list of commits in
the commit range.

Example:

    {
      t_44_func_hashes_mult_unsorted_t   => [
          {
            compare => "same",
            newer   => { md5_hex => "31b7c93474e15a16d702da31989ab565", idx => 1 },
            older   => { md5_hex => "31b7c93474e15a16d702da31989ab565", idx => 0 },
          },
          {
            compare => "same",
            newer   => { md5_hex => "31b7c93474e15a16d702da31989ab565", idx => 2 },
            older   => { md5_hex => "31b7c93474e15a16d702da31989ab565", idx => 1 },
          },
          # ...
          {
            compare => "same",
            newer   => { md5_hex => "31b7c93474e15a16d702da31989ab565", idx => 9 },
            older   => { md5_hex => "31b7c93474e15a16d702da31989ab565", idx => 8 },
          },
      ],
      t_45_func_hashes_alt_dual_sorted_t => [
          {
            compare => "same",
            newer   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 1 },
            older   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 0 },
          },
          {
            compare => "same",
            newer   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 2 },
            older   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 1 },
          },
          {
            compare => "same",
            newer   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 3 },
            older   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 2 },
          },
          # ...
          {
            compare => "same",
            newer   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 9 },
            older   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 8 },
          },
      ],
    }

=item * Comment

This method currently may be called only after calling
C<run_test_files_on_all_commits()> and will die otherwise.

Since in this method we are concerned with the B<transition> in the test
output between a pair of commits, the second-level arrays returned by this
method will have one fewer element than the second-level arrays returned by
C<get_digests_by_file_and_commit()>.

=back

=cut

sub examine_transitions {
    my ($self, $rv) = @_;
    my %transitions;
    for my $k (sort keys %{$rv}) {
        my @arr = @{$rv->{$k}};
        for (my $i = 1; $i <= $#arr; $i++) {
            next unless (defined $arr[$i] and defined $arr[$i-1]);
            my $older = $arr[$i-1]->{md5_hex};
            my $newer = $arr[$i]->{md5_hex};
            if ($older eq $newer) {
                push @{$transitions{$k}}, {
                    older => { idx => $i-1, md5_hex => $older },
                    newer => { idx => $i,   md5_hex => $newer },
                    compare => 'same',
                }
            }
            else {
                push @{$transitions{$k}}, {
                    older => { idx => $i-1, md5_hex => $older },
                    newer => { idx => $i,   md5_hex => $newer },
                    compare => 'different',
                }
            }
        }
    }
    return \%transitions;
}

=head2 C<prepare_multisect()>

=over 4

=item * Purpose

Set up data structures within object needed before multisection can start.

=item * Arguments

    $bisected_outputs = $dself->prepare_multisect();

None; all data needed is already present in the object.

=item * Return Value

Reference to an array holding a list of array references, one for each commit
in the range.  Only the first and last elements of the array will be
populated, as the other, internal elements will be populated in the course of
the multisection process.  The first and last elements will hold one element
for each of the test files targeted.  Each such element will be a hash keyed
on the same keys as C<run_test_files_on_one_commit()>:

    commit
    commit_short
    file
    file_stub
    md5_hex

Example:

   [
     [
       {
         commit => "630a7804a7849e0075351ef72b0cbf5a44985fb1",
         commit_short => "630a780",
         file => "/tmp/T8oUInphoW/630a780.t_001_load_t.output.txt",
         file_stub => "t_001_load_t",
         md5_hex => "59c9d8f4cee1c31bcc3d85ab79a158e7",
       },
     ],
     [],
     [],
     # ...
     [],
     [
       {
         commit => "efdd091cf3690010913b849dcf4fee290f399009",
         commit_short => "efdd091",
         file => "/tmp/T8oUInphoW/efdd091.t_001_load_t.output.txt",
         file_stub => "t_001_load_t",
         md5_hex => "318ce8b2ccb3e92a6e516e18d1481066",
       },
     ],
   ];


=item * Comment

=back

=cut

sub prepare_multisect {
    my $self = shift;
    my $all_commits = $self->get_commits_range();
    my @bisected_outputs = (undef) x scalar(@{$all_commits});
    for my $idx (0, $#{$all_commits}) {
        my $outputs = $self->run_test_files_on_one_commit($all_commits->[$idx]);
        $bisected_outputs[$idx] = $outputs;
    }
    $self->{bisected_outputs} = [ @bisected_outputs ];
    return \@bisected_outputs;
}

sub prepare_multisect_hash {
    my $self = shift;
    my $all_commits = $self->get_commits_range();
    $self->{xall_outputs} = [ (undef) x scalar(@{$all_commits}) ];
    my %bisected_outputs;
    for my $idx (0, $#{$all_commits}) {
        my $outputs = $self->run_test_files_on_one_commit($all_commits->[$idx]);
        $self->{xall_outputs}->[$idx] = $outputs;
        for my $target (@{$outputs}) {
            my @other_keys = grep { $_ ne 'file_stub' } keys %{$target};
            $bisected_outputs{$target->{file_stub}}[$idx] =
                { map { $_ => $target->{$_} } @other_keys };
        }
    }
    $self->{bisected_outputs} = { %bisected_outputs };
    return \%bisected_outputs;
}

=pod

This is a first pass at multisection.  Here, we'll only try to identify the
very first transition for each test file targeted.

To establish that, for each target, we have to find the commit whose md5_hex
first differs from that of the very first commit in the range.  How will we
know when we've found it?  Its md5_hex will be different from the very first's,
but the immediately preceding commit will have the same md5_hex as the very first.

Hence, we have to do *two* instances of run_test_files_on_one_commit() at each
bisection point.  For each of them we will stash the result in a cache.  That way,
before calling run_test_files_on_one_commit(), we can check the cache to see
whether we can skip the configure-build-test cycle for that particular commit.
As a matter of fact, that cache will be nothing other than the 'bisected_outputs'
array created in prepare_multisect().

We have to account for the fact that the first transition is quite likely to be
different for each of the test files targeted.  We are likely to have to keep on
bisecting for one file after we've completed another.  Hence, we'll need a hash
keyed on file_stub in which to record the Boolean status of our progress for each
target and before embarking on a given round of run_test_files_on_one_commit()
we should check the status.

=cut

sub identify_transitions {
    my ($self) = @_;
say STDERR "AA: state of object at opening of identify_transitions";
pp($self);
    croak "You must run prepare_multisect_hash() before identify_transitions()"
        unless exists $self->{bisected_outputs};

    my $target_count = scalar(@{$self->{targets}});
    my $max_target_idx = $#{$self->{targets}};

    # 1 element per test target file, keyed on stub, value 0 or 1
    my %overall_status = map { $self->{targets}->[$_]->{stub} => 0 } (0 .. $max_target_idx);
say STDERR "BB:";
pp(\%overall_status);
        
    # Overall success criterion:  We must have completed multisection for each
    # targeted test file and recorded that completion with a '1' in its
    # element in %overall_status.
    
    until (sum(values(%overall_status)) == $target_count) {
        if ($self->{verbose}) {
            say "target count|sum of status values: ",
                join('|' => $target_count, sum(values(%overall_status)));
        }
        for my $target_idx (0 .. $max_target_idx) {
            my $target = $self->{targets}->[$target_idx];
            if ($self->{verbose}) {
                say "Targeting file: $target->{path}";
            }
            my $rv = $self->multisect_one_target($target_idx);
            if ($rv) {
                $overall_status{$target->{stub}}++;
            }
say STDERR "CC: ", sum(values(%overall_status)), "\t", $target_count;
pp(\%overall_status);
        }

#        my ($current_start_idx, $current_end_idx, $n);
#        my (%this_round_status, $excluded_targets);
#        $current_start_idx = 0;
#    
#        $current_end_idx = $max_idx = $#{$self->{commits}};
#        $n = 1;
#    #say STDERR "BBB: current_start_idx|current_end_idx: ", join('|' => ($current_start_idx, $current_end_idx));
#    #say STDERR "CCC: max_idx: ", join('|' => ($max_idx));
#    
#        %this_round_status = map { $_ => 0 } keys %{$self->{bisected_outputs}};
#        $excluded_targets = {};
#    
#        ABC: while ($n <= $max_idx) {
#            # What gets (or may get) updated or assigned to in the course of one rep of this loop:
#            # $current_start_idx
#            # $current_end_idx
#            # $n
#            # %this_round_status
#            # $excluded_targets
#            # $self->{xall_outputs}
#            # $self->{bisected_outputs}
#    
#    say STDERR "DDD: $n";
#    say STDERR "DDD1: current_start_idx|current_end_idx: ", join('|' => ($current_start_idx, $current_end_idx));
#    say STDERR "EEE: this_round_status:";
#    pp(\%this_round_status);
#            # Above is sanity check: We should never need more rounds than there are
#            # commits in the range.
#    
#            # Our process has to set the value of each element (file_stub) in
#            # %this_round_status to 1 to terminate.
#    
#            # For each test file, we know we've identified *one* transition point
#            # when (a) the md5_hex of the commit currently under consideration is
#            # *different* from $current_start_md5_hex and (b) the md5_hex of the
#            # immediately preceding commit is defined and is the *same* as
#            # $current_start_md5_hex.
#    
#            # For each test file, we know we've identified *all* transition points
#            # when, after repeating the procedure in the preceding paragraph
#            # enough times, (a) the md5_hex of the current commit is the same as that
#            # of the very last commit and (b) the md5_hex of the immediately
#            # preceding commit is defined and is *different* from the current
#            # md5_hex.
#    
#    #        return 1 if sum(values %this_round_status) ==
#    #            scalar(@{$self->{targets}});
#    
#            my $h = sprintf("%d" => (($current_start_idx + $current_end_idx) / 2));
#            $self->_run_one_commit_and_assign($h);
#    
#    
#            # Decision criteria:
#            # We'll handle 1 target test file at a time; too confusing otherwise.
#            my $first_target_stub = $self->{targets}->[0]->{stub};
#            my $current_start_md5_hex = $self->{bisected_outputs}->{$first_target_stub}->[0]->{md5_hex};
#            my $first_target_md5_hex  = $self->{bisected_outputs}->{$first_target_stub}->[$h]->{md5_hex};
#    say STDERR "GGG: ", join('|' => $first_target_stub, $current_start_md5_hex, $first_target_md5_hex);
#    
#            # If $first_target_stub eq $current_start_md5_hex, then the first
#            # transition is *after* index $h.  Hence bisection should go upwards.
#            #
#            # If $first_target_stub ne $current_start_md5_hex, then the first
#            # transition has come *before* index $h.  Hence bisection should go
#            # downwards.  However, since the test of where the first transition is
#            # is that index j-1 has the same md5_hex as $current_start_md5_hex but
#            #         index j   has a different md5_hex, we have to do a run on
#            #         j-1 as well.
#    
#            if (! $this_round_status{$first_target_stub}) {
#    say STDERR "HHH: status for $first_target_stub: $this_round_status{$first_target_stub}";
#                if ($first_target_md5_hex ne $current_start_md5_hex) {
#                    my $g = $h - 1;
#                    $self->_run_one_commit_and_assign($g);
#    
#    say STDERR "JJJ: bisected_outputs:";
#    pp($self->{bisected_outputs});
#    say STDERR "KKK: xall_outputs after precheck:";
#    pp($self->{xall_outputs});
#                    my $pre_target_md5_hex  = $self->{bisected_outputs}->{$first_target_stub}->[$g]->{md5_hex};
#    say STDERR "LLL: $pre_target_md5_hex";
#                    if ($pre_target_md5_hex eq $current_start_md5_hex) {
#                        # Success on the first target!
#                        $this_round_status{$first_target_stub}++;
#    say STDERR "MMM: success on first target";
#                        last ABC;
#                    }
#                    else {
#                        # Bisection should continue downwards
#    say STDERR "NNN: Bisection should continue downwards";
#                        $current_end_idx = $h;
#                        $n++;
#                        next ABC;
#                    }
#                }
#                else {
#                    # Bisection should continue upwards
#    say STDERR "OOO: Bisection should continue upwards";
#                    $current_start_idx = $h;
#                    $n++;
#                    next ABC;
#                }
#            }
#            else {
#    say STDERR "HHHHHH: status for $first_target_stub: $this_round_status{$first_target_stub}";
#            }
#        }
#        croak "XXX: Problem:  Number of bisection rounds ($n) exceeded " . ($max_idx) . " commits in range"
#            if $n > ($max_idx + 1);
#        return 1;
    } # END until loop
    #croak "Never completed loop over all targeted test files"
        
}

sub multisect_one_target {
    my ($self, $target_idx) = @_;
    croak "Must supply index of test file within targets list"
        unless(defined $target_idx and $target_idx =~ m/^\d+$/);
    my $target = $self->{targets}->[$target_idx];
    my $stub = $target->{stub};
    croak "target must be a hash ref" unless ref($target) eq 'HASH';
    for my $arg ( qw| path stub | ) {
        croak "target must have a '$arg' element" unless defined $target->{$arg};
    }

    # The condition for successful multisection of one particular test file
    # target is that the list of md5_hex values for files holding the output of TAP
    # run over the commit range exhibit the following behavior:

    # The list is composed of sub-sequences (a) whose elements are either (i) the md5_hex value for
    # the TAP outputfiles at a given commit or (ii) undefined; (b) if defined,
    # the md5_values are all identical; (c) the first and last elements of the
    # sub-sequence are both defined; and (d) the sub-sequence's unique defined
    # value never reoccurs in any subsequent sub-sequence.

    # For each run of multisect_one_target() over a given target, it will
    # return a true value (1) if the above condition(s) are met and 0
    # otherwise.  The caller (identify_transitions()) will handle that return
    # value appropriately.  The caller will then call multisect_one_target()
    # on the next target, if any.

    # The objective of multisection is to identify the git commits at which
    # the output of the test file targeted materially changed.  We are using
    # an md5_hex value for that test file as a presumably valid unique
    # identifier for that file's content.  A transition point is a commit at
    # which the output file's md5_hex differs from that of the immediately
    # preceding commit.  So, to identify the first transition point for a
    # given target, we need to locate the commit at which the md5_hex changed
    # from that found in the very first commit in the designated commit range.
    # Once we've identified the first transition point, we'll look for the
    # second transition point, i.e., that where the md5_hex changed from that
    # observed at the first transition point.  We'll continue that process
    # until we get to a transition point where the md5_hex is identical to
    # that of the very last commit in the commit range.

    # This entails checking out the source code at each commit calculated by
    # the bisection algorithm, configuring and building the code, running the
    # test targets at that commit, computing their md5_hex values and storing
    # them in the 'bisected_outputs' structure.  The prepare_multisect_hash()
    # method will pre-populate that structure with md5_hexes for each test
    # file for each of the first and last commits in the commit range.

    # Since the configuration and build at a particular commit may be
    # time-consuming, once we have completed those steps we will run all the
    # test files at once and store their results in 'bisected_outputs'
    # immediately.  We will make our bisection decision based only on analysis
    # of the current target.  But when we come to the second target file we
    # will be able to skip configuration, build and test-running at commits
    # visited during the pass over the first target file.

    # Consider adding a counter here to defend against infinite loops.
    my ($min_idx, $max_idx) = (0, $#{$self->{commits}});
    my $this_target_status = 0;
    my $current_start_idx = $min_idx;
    my $current_end_idx  = $max_idx;
    my $overall_start_md5_hex =
            $self->{bisected_outputs}->{$stub}->[$min_idx]->{md5_hex};
    my $overall_end_md5_hex =
            $self->{bisected_outputs}->{$stub}->[$max_idx]->{md5_hex};
    my $excluded_targets = {};
    my $n = 0;
    #  my (%this_round_status);
say STDERR "III: min_idx|max_idx:                            ", join('|' => ($min_idx, $max_idx));
say STDERR "IIIa: overall_start_md5_hex|overall_end_md5_hex: ", join('|' => ($overall_start_md5_hex, $overall_end_md5_hex));
    
    ABC: while ((! $this_target_status) or ($n <= scalar(@{$self->{targets}}))) {
say STDERR "JJJ: current_start_idx|current_end_idx|this_target_status: ", join('|' => ($current_start_idx, $current_end_idx, $this_target_status));
        # Start multisecting on this test target file:
        # one transition point at a time until we've got them all for this
        # test file.

        # What gets (or may get) updated or assigned to in the course of one rep of this loop:
        # $current_start_idx
        # $current_end_idx
        # $n
        # %this_round_status
        # $excluded_targets
        # $self->{xall_outputs}
        # $self->{bisected_outputs}

        my $h = sprintf("%d" => (($current_start_idx + $current_end_idx) / 2));
say STDERR "KKK: index of commit being handled: $h";
        $self->_run_one_commit_and_assign($h);

        my $current_start_md5_hex =
            $self->{bisected_outputs}->{$stub}->[$current_start_idx]->{md5_hex};
        my $target_h_md5_hex  =
            $self->{bisected_outputs}->{$stub}->[$h]->{md5_hex};
#say STDERR "LLL: ", join('|' => $stub, $current_start_md5_hex, $target_h_md5_hex);

        # Decision criteria:
        # If $target_h_md5_hex eq $current_start_md5_hex, then the first
        # transition is *after* index $h.  Hence bisection should go upwards.

        # If $target_h_md5_hex ne $current_start_md5_hex, then the first
        # transition has come *before* index $h.  Hence bisection should go
        # downwards.  However, since the test of where the first transition is
        # is that index j-1 has the same md5_hex as $current_start_md5_hex but
        #         index j   has a different md5_hex, we have to do a run on
        #         j-1 as well.

        if ($target_h_md5_hex ne $current_start_md5_hex) {
            my $g = $h - 1;
            $self->_run_one_commit_and_assign($g);
#say STDERR "MMM: bisected_outputs:";
#pp($self->{bisected_outputs});
#say STDERR "NNN: xall_outputs after precheck:";
#pp($self->{xall_outputs});
            my $target_g_md5_hex  = $self->{bisected_outputs}->{$stub}->[$g]->{md5_hex};
#say STDERR "OOO: $target_h_md5_hex";
            if ($target_g_md5_hex eq $current_start_md5_hex) {
                # WRONG!:  Success on this transition point in the current target file!
                # Have to handle the case where $target_h_md5_hex is also eq
                #
                # To find the next transition point for the current target
                # file, we assign $h to $current_start_idx
say STDERR "MMM1: For target '$stub', identified transition at commit index '$h'";
say STDERR "MMM1a: target_g_md5_hex:         $target_g_md5_hex";
say STDERR "MMM1a: target_h_md5_hex:         $target_h_md5_hex";
say STDERR "MMM1b: current_start_md5_hex:    $current_start_md5_hex";
say STDERR "MMM1c: overall_end_md5_hex:      $overall_end_md5_hex";
                if ($target_h_md5_hex eq $overall_end_md5_hex) {
say STDERR "MMM1x: For target '$stub', identified final transition at commit index '$h'";
                }
                else {
say STDERR "MMM1y: For target '$stub', identified non-final transition at commit index '$h'";
                    $current_start_idx  = $h;
                    $current_end_idx    = $max_idx;
                }
                $n++;
            }
            else {
                # Bisection should continue downwards
say STDERR "MMM2: For target '$stub', bisection should continue downwards from commit index '$h'";
                $current_end_idx = $h;
                $n++;
            }
        }
        else {
            # Bisection should continue upwards
say STDERR "MMM3: For target '$stub', bisection should continue upwards from commit index '$h'";
            $current_start_idx = $h;
            $n++;
        }
        $this_target_status = $self->evaluate_status_one_target_run($target_idx);
say STDERR "ZZZ1: n:                  $n";
say STDERR "ZZZ2: this_target_status: $this_target_status";
#next ABC;
    }

    return 1;
}

sub evaluate_status_one_target_run {
    my ($self, $target_idx) = @_;
    my $stub = $self->{targets}->[$target_idx]->{stub};
say STDERR "QQQQ: $stub";
    my @trans = ();
    for my $o (@{$self->{xall_outputs}}) {
        push @trans,
            defined $o ? $o->[$target_idx]->{md5_hex} : 'undef';
    }
say STDERR "RRRR:";
pp(\@trans);
    my $vls = validate_list_sequence(\@trans);
say STDERR "SSSS:";
pp($vls);
    (
        (ref($vls) eq 'ARRAY') and
        (scalar(@{$vls}) == 1 ) and
        ($vls->[0])
    ) ? 1 : 0;
}

sub _run_one_commit_and_assign {

    # If we've already stashed a particular commit's outputs in
    # xall_outputs (and, simultaneously) in bisected_outputs,
    # then we don't need to actually perform a run.

    # This internal method assigns to xall_outputs and bisected_outputs in
    # place.

    my ($self, $idx) = @_;
    my $this_commit = $self->{commits}->[$idx]->{sha};
    unless (defined $self->{xall_outputs}->[$idx]) {
        my $these_outputs = $self->run_test_files_on_one_commit($this_commit);
        $self->{xall_outputs}->[$idx] = $these_outputs;

        for my $target (@{$these_outputs}) {
            my @other_keys = grep { $_ ne 'file_stub' } keys %{$target};
            $self->{bisected_outputs}->{$target->{file_stub}}->[$idx] =
                { map { $_ => $target->{$_} } @other_keys };
        }
    }
}

sub get_bisected_outputs {
    my $self = shift;
    return $self->{bisected_outputs};
}

1;

__END__
    # For debugging purposes, we'll create a phony count.
    #my $phony_count = 1;
    #$target_count = $phony_count;

#            if (! $this_round_status{$first_target_stub}) {
#    say STDERR "HHH: status for $first_target_stub: $this_round_status{$first_target_stub}";

