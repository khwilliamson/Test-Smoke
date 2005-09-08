#! /usr/bin/perl -w
use strict;

# $Id$

use File::Spec::Functions;
my $findbin;
use File::Basename;
BEGIN { $findbin = dirname $0; }
use lib $findbin;
use TestLib;
use Cwd;

use Test::More tests => 13;
BEGIN {
    use_ok( 'Test::Smoke::Patcher' );
    use_ok( 'Test::Smoke::Syncer' );
}
my $verbose = exists $ENV{SMOKE_VERBOSE} ? $ENV{SMOKE_VERBOSE} : 0;

my $patch = find_a_patch();
$verbose and diag( "Found patch: '$patch'" );
my $untgz = find_untargz();
$verbose and diag( "found untargz: $untgz" );
my $unzipper = find_unzip();
$verbose and diag( "Found unzip: $unzipper" );
my %config = (
    ddir  => catdir(qw( t perl-current )),
    fsync    => 'copy',
    cdir     => catdir(qw( t perl )),
    mdir     => catdir(qw( t perl-master )),
    fdir     => catdir(qw( t perl-inter  )),
    patchbin => $patch,
    v        => $verbose,
);

my $has_forest = 0;
SKIP: {
    my $to_skip = 13;
    $patch    or skip "Cannot find a working 'patch' program.", $to_skip;
    $untgz    or skip "Cannot un-tar-gz",                       $to_skip;
    $unzipper or skip "No unzip found",                         $to_skip;

    chdir 't';
    my $untgz_ok = do_untargz( $untgz, File::Spec->catfile(
       qw( ftppub snap perl@20000.tgz ) ) );
    my $p_content = do_unzip( $unzipper, catfile(
        qw( ftppub perl-current-diffs 20005.gz ) ));
    chdir updir;
    ok( $untgz_ok, "Mockup sourcetree unpacked" );
    ok -d catdir( 't', 'perl' ), "sourcetree is there";
    like $p_content, 'm/^+/', "patch content ok";

    my $syncer = Test::Smoke::Syncer->new( forest => %config );
    ok my $pl = $syncer->sync, "Forest planted" or
        skip "No source forest", $to_skip -= 3;
    is $pl, '20000', "patchlevel $pl";
    $has_forest = 1;

    local *PINFO;
    my $relpatch = catfile updir, '20005';
    open PINFO, "> " . catfile(qw( t 20005 )) or
        skip "Cannot write patch: $!", $to_skip -= 4;
    print PINFO $p_content;
    ok close PINFO, "patch written";

    my $pinfo = catfile( 't', 'test.patches' );
    open PINFO, "> $pinfo" or skip "Cannot open '$pinfo': $!", $to_skip -= 6;
    select( (select(PINFO), $|++)[0] );
    print PINFO <<EOPINFO;
$relpatch;-p1
# Do some somments 
# This is to take out #20001, so we can see what happend
# $relpatch;-R
# $relpatch
EOPINFO
    ok close PINFO, "pfile written";

    # cheat with .patch
    unlink catfile qw( t perl-inter .patch );
    ok my $patcher = Test::Smoke::Patcher->new( multi => {
        %config,
        pfile => catfile( updir, 'test.patches' ),
    }), "Patcher created";
    isa_ok $patcher, 'Test::Smoke::Patcher';

    $ENV{SMOKE_DEBUG} and diag Dumper $patcher;
    ok eval { $patcher->patch }, "Patch the intermediate tree";

    chomp( my $plev = get_file(qw( t perl-current .patch )) );
    is $plev, 20006, "Tree successfully patched";
}

END {
    unless ( $ENV{SMOKE_DEBUG} ) {
        rmtree catdir( 't', $_ )
            for qw( perl perl-master perl-inter perl-current );
        1 while unlink catfile qw( t test.patches );
        1 while unlink catfile qw( t 20005 );
    }
}
