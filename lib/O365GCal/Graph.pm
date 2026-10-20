package O365GCal::Graph;
# Microsoft Graph calendarView reader + mapping to Google event bodies.
use strict; use warnings;
use JSON::PP ();
use HTTP::Tiny;

my $JSON = JSON::PP->new->utf8(1);

sub _esc { my $s = shift; $s =~ s/([^A-Za-z0-9\-._~])/sprintf('%%%02X', ord $1)/ge; $s }

# fetch(token_cb => sub, start => ISO, end => ISO, http => obj) -> [events]
sub fetch {
    my (%a) = @_;
    my $http = $a{http} // HTTP::Tiny->new(timeout => 60, agent => 'o365-gcal-sync/0.1');
    my $tok = $a{token_cb}->();
    my $sel = 'id,iCalUId,subject,location,start,end,isAllDay,isCancelled,showAs,type,seriesMasterId,sensitivity';
    my $url = 'https://graph.microsoft.com/v1.0/me/calendarView?startDateTime=' . _esc($a{start})
        . '&endDateTime=' . _esc($a{end}) . '&$top=100&$select=' . $sel;
    my @ev; my $pages = 0;
    while ($url) {
        die "too many pages\n" if ++$pages > 200;
        my $r = $http->get($url, { headers => {
            Authorization => "Bearer $tok", Accept => 'application/json',
            Prefer => 'outlook.timezone="UTC"' } });
        die "Graph calendarView: HTTP $r->{status} $r->{reason}\n" unless $r->{success};
        my $d = $JSON->decode($r->{content});
        push @ev, @{ $d->{value} // [] };
        $url = $d->{'@odata.nextLink'};
    }
    return \@ev;
}

sub _utc { my $t = shift; $t =~ s/\.\d+\z//; $t =~ s/Z\z//; "${t}Z" }

sub key_for { my $e = shift; ($e->{iCalUId} // $e->{id}) . '|' . _utc($e->{start}{dateTime}) }

# detail: 'full' (title+location), 'busy' (just "Busy")
sub to_google {
    my ($e, %o) = @_;
    my $detail = $o{detail} // 'full';
    my %g;
    if ($e->{isAllDay}) {
        %g = (start => { date => substr($e->{start}{dateTime}, 0, 10) },
              end   => { date => substr($e->{end}{dateTime}, 0, 10) });
    } else {
        %g = (start => { dateTime => _utc($e->{start}{dateTime}), timeZone => 'UTC' },
              end   => { dateTime => _utc($e->{end}{dateTime}),   timeZone => 'UTC' });
    }
    my $private = ($e->{sensitivity} // 'normal') =~ /private|confidential/i;
    if ($detail eq 'busy' || $private) {
        $g{summary} = $o{busy_title} // 'Busy (work)';
    } else {
        $g{summary} = $e->{subject} // '(no title)';
        my $loc = $e->{location}{displayName};
        $g{location} = $loc if defined $loc && length $loc;
    }
    $g{transparency} = (($e->{showAs} // 'busy') =~ /^free$/i) ? 'transparent' : 'opaque';
    return \%g;
}
1;
