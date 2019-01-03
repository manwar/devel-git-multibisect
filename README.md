# NAME

Devel::Git::MultiBisect - Study test output over a range of `git` commits

# DESCRIPTION

Given a Perl library or application kept in `git` for version control, it is
often useful to be able to compare the output collected from running one or
several test files over a range of `git` commits.  If that range is sufficiently
large, a test may fail in **more than one way** over that range.

If that is the case, then simply asking, _"When did this file start to
fail?"_ is insufficient.  We may want to (a) capture the test output for each
commit; or, (b) capture the test output only at those commits where the output
changed.  The output of a run of a test file may change for a variety of
reasons:  test failures, segfaults, changes in the number or content of tests,
etc.)

`Devel::Git::MultiBisect` provides methods to achieve that objective.  Its
child classes, `Devel::Git::MultiBisect::AllCommits` and
`Devel::Git::MultiBisect::Transitions`, provide different flavors of that
functionality for objectives (a) and (b), respectively.  Please refer to their
documentation for further discussion.

## Multisection of Build-Time Failures

Perl 5 has many different configuration options, some of which are used
infrequently.  Given a sufficiently large number of `git` commits and a
specific set of configuration options, it is possible that Perl might fail to
build (`i.e.`, a build-time failure in `make`) in **more than one way** over
that range.

If that is the case, then simply asking, _"When did Perl start failing to
build with this set of configuration options?"_ is insufficient.  We may want
to capture the built-time error output at those commits where the output
changed.  `Devel::Git::MultiBisect::BuildTransitions` provides methods to
achieve that objective.  Please refer to their documentation for further
discussion.

# PREREQUISITES

Perl 5.10 or higher.

Capture::Tiny and IO::CaptureOutput needed for testing only.

git.

# INSTALL

    perl Makefile.PL
    make
    make test
    make install

If you are on a windows box you should use 'nmake' rather than 'make'.  (This
library has not yet been tested on Windows.)

Once installed, start reading the documentation by calling:

    perldoc Devel::Git::MultiBisect
