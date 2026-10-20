#!/usr/bin/env perl
# Regression: dashed options (--dry-run, --no-delete) must reach $o{dry_run}/$o{no_delete}.
use strict; use warnings; use Test::More;
use FindBin;
for my $bin (qw(o365-gcal-sync maildir-ics-trawl)) {
    my $src = do { local (@ARGV, $/) = "$FindBin::Bin/../bin/$bin"; <> };
    like $src, qr/tr\/-\/_\//, "$bin normalizes dashed option keys";
    # every $o{x_y} used must not rely on a raw dashed key
    unlike $src, qr/\$o\{'?[a-z]+-[a-z-]+'?\}/, "$bin never reads a dashed key directly";
}
# behavioural check of the normalization snippet
use Getopt::Long qw(GetOptionsFromArray);
my %o; GetOptionsFromArray([qw(--dry-run --no-delete)], \%o, 'dry-run|n', 'no-delete') or die;
for my $k (grep { /-/ } keys %o) { (my $u = $k) =~ tr/-/_/; $o{$u} = delete $o{$k} }
ok $o{dry_run}, '--dry-run sets dry_run';
ok $o{no_delete}, '--no-delete sets no_delete';
my %p; GetOptionsFromArray([qw(-n)], \%p, 'dry-run|n') or die;
for my $k (grep { /-/ } keys %p) { (my $u = $k) =~ tr/-/_/; $p{$u} = delete $p{$k} }
ok $p{dry_run}, '-n sets dry_run';
done_testing;
