package O365GCal::Google;
# Keyed upsert of Google Calendar v3 events (keyed-calendar-upsert principles):
#  - each managed event carries private extendedProperties:
#      managedBy=<tool>, o365key=<sha1 of stable key>, o365hash=<content hash>
#  - unchanged content => no write; sendUpdates=none always
#  - only events tagged managedBy=<tool> are ever patched or deleted
use strict; use warnings;
use JSON::PP ();
use HTTP::Tiny;
use Digest::SHA qw(sha1_hex);

my $BASE = 'https://www.googleapis.com/calendar/v3';
my $JSON = JSON::PP->new->canonical(1)->utf8(1);

sub new {
    my ($class, %a) = @_;
    my $s = bless {
        calendar  => $a{calendar} // die("calendar id required\n"),
        token_cb  => $a{token_cb},          # sub returning access token
        managedBy => $a{managedBy} // 'o365-gcal-sync',
        dry_run   => $a{dry_run} // 0,
        http      => $a{http} // HTTP::Tiny->new(timeout => 60, agent => 'o365-gcal-sync/0.1'),
        log       => $a{log} // sub { print "$_[0]\n" },
        counts    => {},
    }, $class;
    return $s;
}

sub key_id { sha1_hex($_[0]) }   # stable key -> property-safe id

sub _uri_esc { my $s = shift; $s =~ s/([^A-Za-z0-9\-._~])/sprintf('%%%02X', ord $1)/ge; $s }

sub _req {
    my ($s, $method, $path, $query, $body) = @_;
    my $url = $BASE . $path;
    if ($query && @$query) {
        my @q; for (my $i = 0; $i < @$query; $i += 2) { push @q, _uri_esc($query->[$i]) . '=' . _uri_esc($query->[$i+1]) }
        $url .= '?' . join '&', @q;
    }
    $s->{tok} //= $s->{token_cb}->();
    my %h = (headers => { Authorization => "Bearer $s->{tok}", Accept => 'application/json' });
    if (defined $body) { $h{content} = $JSON->encode($body); $h{headers}{'Content-Type'} = 'application/json' }
    my $r = $s->{http}->request($method, $url, \%h);
    if ($r->{status} == 410 || $r->{status} == 404) { return { _gone => 1 } }
    die "Google $method $path: HTTP $r->{status} $r->{reason}\n" unless $r->{success};
    return length($r->{content} // '') ? $JSON->decode($r->{content}) : {};
}

# Normalise the content we manage, hash it.
sub content_hash {
    my ($ev) = @_;
    my %c = map { $_ => $ev->{$_} } grep { defined $ev->{$_} } qw(summary description location start end recurrence status transparency);
    return sha1_hex($JSON->encode(\%c));
}

sub _tag {
    my ($s, $ev, $key) = @_;
    my %e = %$ev;
    $e{extendedProperties} = { private => {
        managedBy => $s->{managedBy}, o365key => key_id($key), o365hash => content_hash($ev),
        %{ $ev->{_extra_private} // {} },
    } };
    delete $e{_extra_private};
    return \%e;
}

# All managed events (optionally limited to a window). Returns { keyid => event }.
sub list_managed {
    my ($s, %w) = @_;
    my (%out, $page);
    do {
        my @q = (privateExtendedProperty => "managedBy=$s->{managedBy}", maxResults => 2500, showDeleted => 'false');
        push @q, timeMin => $w{timeMin} if $w{timeMin};
        push @q, timeMax => $w{timeMax} if $w{timeMax};
        push @q, pageToken => $page if $page;
        my $r = $s->_req(GET => '/calendars/' . _uri_esc($s->{calendar}) . '/events', \@q);
        for my $e (@{ $r->{items} // [] }) {
            my $k = $e->{extendedProperties}{private}{o365key} or next;
            $out{$k} = $e;
        }
        $page = $r->{nextPageToken};
    } while ($page);
    return \%out;
}

sub find_by_key {
    my ($s, $key) = @_;
    my $r = $s->_req(GET => '/calendars/' . _uri_esc($s->{calendar}) . '/events',
        [privateExtendedProperty => 'o365key=' . key_id($key), maxResults => 10]);
    for my $e (@{ $r->{items} // [] }) {
        return $e if ($e->{extendedProperties}{private}{managedBy} // '') eq $s->{managedBy};
    }
    return undef;
}

sub _count { $_[0]{counts}{$_[1]}++ }

# upsert($key, \%event, existing => $ev_or_undef (skip lookup if given/known))
sub upsert {
    my ($s, $key, $ev, %o) = @_;
    my $cur = exists $o{existing} ? $o{existing} : $s->find_by_key($key);
    my $body = $s->_tag($ev, $key);
    my $h = $body->{extendedProperties}{private}{o365hash};
    my $label = $ev->{summary} // '(no title)';
    if ($cur && ($cur->{extendedProperties}{private}{o365hash} // '') eq $h && ($cur->{status} // '') ne 'cancelled') {
        $s->_count('unchanged'); return ('unchanged', $cur->{id});
    }
    my $st = $cur ? 'updated' : 'created';
    $s->{log}->(sprintf "%s%-9s %s %s", ($s->{dry_run} ? '[dry-run] ' : ''), $st, _short($key), $label);
    $s->_count($st);
    return ($st, $cur ? $cur->{id} : undef) if $s->{dry_run};
    my $cal = '/calendars/' . _uri_esc($s->{calendar}) . '/events';
    my $r = $cur
        ? $s->_req(PUT => "$cal/" . _uri_esc($cur->{id}), [sendUpdates => 'none'], { %$body, status => 'confirmed' })
        : $s->_req(POST => $cal, [sendUpdates => 'none'], $body);
    return ($st, $r->{id});
}

sub delete_event {
    my ($s, $ev, $why) = @_;
    return 'missing' unless $ev && ($ev->{extendedProperties}{private}{managedBy} // '') eq $s->{managedBy};
    $s->{log}->(sprintf "%sdeleted   %s %s%s", ($s->{dry_run} ? '[dry-run] ' : ''),
        substr($ev->{extendedProperties}{private}{o365key}, 0, 10), $ev->{summary} // '', $why ? " ($why)" : '');
    $s->_count('deleted');
    return 'deleted' if $s->{dry_run};
    $s->_req(DELETE => '/calendars/' . _uri_esc($s->{calendar}) . '/events/' . _uri_esc($ev->{id}), [sendUpdates => 'none']);
    return 'deleted';
}

sub delete_by_key {
    my ($s, $key, $why) = @_;
    my $ev = $s->find_by_key($key);
    unless ($ev) { $s->_count('missing'); return 'missing' }
    return $s->delete_event($ev, $why);
}

sub _short { my $k = shift; length($k) > 40 ? substr($k, 0, 18) . '..' . substr($k, -18) : $k }

sub summary {
    my $s = shift; my $c = $s->{counts};
    join ' ', map { "$_=" . ($c->{$_} // 0) } qw(created updated unchanged deleted missing);
}
1;
