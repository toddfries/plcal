package FakeHTTP;
# In-memory stand-in for Google Calendar v3 + Graph calendarView. No network.
use strict; use warnings;
use JSON::PP;
my $J = JSON::PP->new->canonical(1)->utf8(1);
sub new { bless { events => {}, n => 0, writes => 0, log => [], graph_pages => [] }, shift }
sub _unesc { my $s = shift; $s =~ s/%([0-9A-F]{2})/chr hex $1/ge; $s }
sub get { my ($s, $u, $o) = @_; $s->request('GET', $u, $o) }
sub request {
    my ($s, $m, $url, $o) = @_;
    push @{ $s->{log} }, "$m $url";
    if ($url =~ m{graph\.microsoft\.com}) {
        my $i = $url =~ /page=(\d+)/ ? $1 : 0;
        return { success => 1, status => 200, content => $J->encode($s->{graph_pages}[$i]) };
    }
    my ($path, $q) = split /\?/, $url, 2;
    my %q; for (split /&/, $q // '') { my ($k, $v) = split /=/, $_, 2; $q{_unesc($k)} = _unesc($v // '') }
    my ($id) = $path =~ m{/events/([^/]+)$};
    $id = _unesc($id) if defined $id;
    my $ok = sub { { success => 1, status => $_[1] // 200, content => defined $_[0] ? $J->encode($_[0]) : '' } };
    if ($m eq 'GET') {
        my ($pk, $pv) = split /=/, $q{privateExtendedProperty}, 2;
        my @it = grep { ($_->{extendedProperties}{private}{$pk} // '') eq $pv } map { $s->{events}{$_} } sort keys %{ $s->{events} };
        return $ok->({ items => \@it });
    }
    $s->{writes}++;
    if ($m eq 'POST') { my $e = $J->decode($o->{content}); $e->{id} = 'ev' . ++$s->{n}; $s->{events}{ $e->{id} } = $e; return $ok->($e) }
    if ($m eq 'PUT')  { my $e = $J->decode($o->{content}); $e->{id} = $id; $s->{events}{$id} = $e; return $ok->($e) }
    if ($m eq 'DELETE') { delete $s->{events}{$id}; return $ok->(undef, 204) }
    die "unexpected $m";
}
sub by_summary { my $s = shift; [ sort map { $_->{summary} } values %{ $s->{events} } ] }
1;
