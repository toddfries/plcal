use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use File::Temp qw(tempdir); use File::Copy;
use FakeHTTP; use O365GCal::Google; use O365GCal::Trawl;
my $D = "$FindBin::Bin/fixtures/msgs";
sub setup {
    my $http = FakeHTTP->new;
    my $g = O365GCal::Google->new(calendar => 'cal@example.invalid', http => $http, token_cb => sub { 'T' }, log => sub {}, @_);
    my $t = O365GCal::Trawl->new(google => $g, log => sub {});
    return ($http, $g, $t);
}
sub md { my $d = tempdir(CLEANUP => 1); mkdir "$d/$_" for qw(new cur tmp); copy("$D/$_", "$d/new/$_") for @_; $d }
sub series { my $h = shift; (grep { $_->{recurrence} } values %{ $h->{events} })[0] }

my ($h, $g, $t) = setup();
$t->scan_maildirs(md('01-series.eml'));
is(scalar keys %{ $h->{events} }, 1, 'series created');
my $w = $h->{writes};
$t->{state}{msgs} = {};                 # re-read same mail: idempotent
$t->scan_maildirs(md('01-series.eml'));
is($h->{writes}, $w, 'replay is a no-op (stale/unchanged)');

$t->scan_maildirs(md('02-moved.eml'));
is_deeply($h->by_summary, ['Weekly Widget Standup', 'Weekly Widget Standup (moved)'], 'moved occurrence standalone');
like(join(' ', @{ series($h)->{recurrence} }), qr/EXDATE;TZID=America\/Chicago:20261109T090000/, 'master exdated moved slot');

$t->scan_maildirs(md('03-cancel-one.eml'));
like(join(' ', @{ series($h)->{recurrence} }), qr/20261116T090000/, 'cancelled occurrence -> exdate');
is(scalar keys %{ $h->{events} }, 2, 'no extra event for cancel');

$t->scan_maildirs(md('04-stale.eml'));
is(series($h)->{summary}, 'Weekly Widget Standup', 'older SEQUENCE ignored (out-of-order)');

$t->scan_maildirs(md('07-rrule-change.eml'));
is_deeply($h->by_summary, ['Weekly Widget Standup'], 'RRULE change drops old exceptions');
is(series($h)->{recurrence}[0], 'RRULE:FREQ=WEEKLY;COUNT=10;BYDAY=TU', 'new rrule');
unlike(join(' ', @{ series($h)->{recurrence} }), qr/EXDATE/, 'old exdates cleared');

$t->scan_maildirs(md('06-cancel-series.eml'));
is(scalar keys %{ $h->{events} }, 0, 'series cancel deletes');
$t->{state}{msgs} = {};
$t->scan_maildirs(md('02-moved.eml'));
is(scalar keys %{ $h->{events} }, 0, 'late exception after series cancel ignored');

# out of order: exception before master
($h, $g, $t) = setup();
$t->scan_maildirs(md('02-moved.eml'));
$t->{state}{msgs} = {};
$t->scan_maildirs(md('01-series.eml'));
like(join(' ', @{ series($h)->{recurrence} }), qr/20261109T090000/, 'exception-first still exdates master');

# forwarded, all-day
($h, $g, $t) = setup();
$t->scan_maildirs(md('05-forwarded.eml'));
is_deeply($h->by_summary, ['Call', 'Offsite Day'], 'forwarded invite events');

# dry-run writes nothing
($h, $g, $t) = setup(dry_run => 1);
$t->scan_maildirs(md(map { sprintf '%02d-%s.eml', @$_ } [1,'series'], [2,'moved'], [5,'forwarded']));
is($h->{writes}, 0, 'dry-run: no writes');
is($g->{counts}{created}, 5, 'dry-run counted creates');

# foreign events untouched
($h, $g, $t) = setup();
$h->{events}{foreign} = { id => 'foreign', summary => 'Mine', extendedProperties => { private => { o365key => O365GCal::Google::key_id('ics|synthetic-weekly-001@example.invalid|') } } };
$t->scan_maildirs(md('01-series.eml', '06-cancel-series.eml'));
ok($h->{events}{foreign}, 'untagged (foreign managedBy) event never deleted');
done_testing;
