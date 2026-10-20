use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use FakeHTTP; use O365GCal::Graph; use O365GCal::Google;
my $h = FakeHTTP->new;
my @ev = (
 { iCalUId => 'u1', subject => 'Design review', start => { dateTime => '2026-11-02T15:00:00.0000000', timeZone => 'UTC' }, end => { dateTime => '2026-11-02T16:00:00.0000000' }, location => { displayName => 'Room 2' }, showAs => 'busy' },
 { iCalUId => 'u2', subject => 'Holiday', isAllDay => JSON::PP::true, start => { dateTime => '2026-11-26T00:00:00.0000000' }, end => { dateTime => '2026-11-27T00:00:00.0000000' }, showAs => 'free' },
 { iCalUId => 'u3', subject => 'Secret', sensitivity => 'private', start => { dateTime => '2026-11-03T15:00:00' }, end => { dateTime => '2026-11-03T15:30:00' } },
);
$h->{graph_pages} = [ { value => [ @ev[0,1] ], '@odata.nextLink' => 'https://graph.microsoft.com/v1.0/me/calendarView?page=1' }, { value => [ $ev[2] ] } ];
my $got = O365GCal::Graph::fetch(token_cb => sub { 'T' }, start => 'a', end => 'b', http => $h);
is(scalar @$got, 3, 'nextLink followed');
my $g0 = O365GCal::Graph::to_google($ev[0]);
is_deeply($g0->{start}, { dateTime => '2026-11-02T15:00:00Z', timeZone => 'UTC' }, 'utc time');
is_deeply(O365GCal::Graph::to_google($ev[1])->{start}, { date => '2026-11-26' }, 'all-day');
is(O365GCal::Graph::to_google($ev[1])->{transparency}, 'transparent', 'free -> transparent');
is(O365GCal::Graph::to_google($ev[2])->{summary}, 'Busy (work)', 'private masked');

sub run_sync {   # mirror of bin/o365-gcal-sync main loop
    my ($g, $events) = @_;
    my $have = $g->list_managed; my %seen;
    for my $e (@$events) {
        my $k = O365GCal::Graph::key_for($e); my $kid = O365GCal::Google::key_id($k);
        next if $e->{isCancelled}; $seen{$kid} = 1;
        my $b = O365GCal::Graph::to_google($e); $b->{_extra_private} = { o365src => 'graph' };
        $g->upsert($k, $b, existing => $have->{$kid});
    }
    $g->delete_event($have->{$_}) for grep { !$seen{$_} } keys %$have;
}
my $g = O365GCal::Google->new(calendar => 'c', http => $h, token_cb => sub { 'T' }, log => sub {});
run_sync($g, \@ev);
is(scalar keys %{ $h->{events} }, 3, 'created 3');
my $w = $h->{writes};
run_sync($g, \@ev);
is($h->{writes}, $w, 'second run: no writes');
$ev[0]{subject} = 'Design review v2';
run_sync($g, \@ev);
is($h->{writes}, $w + 1, 'one update on change');
$ev[1]{isCancelled} = JSON::PP::true;
run_sync($g, [ @ev[0,1] ]);
is_deeply($h->by_summary, ['Design review v2'], 'cancelled + vanished deleted');
done_testing;
