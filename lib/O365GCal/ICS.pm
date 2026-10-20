package O365GCal::ICS;
# Minimal MIME walker + iCalendar parser + VEVENT -> Google mapping. No CPAN deps.
use strict; use warnings;
use MIME::Base64 qw(decode_base64);
use MIME::QuotedPrint qw(decode_qp);
use Time::Local qw(timegm);
use POSIX qw(strftime);

# ---------- MIME ----------
sub _split_head {
    my ($raw) = @_;
    my ($head, $body) = split /\r?\n\r?\n/, $raw, 2;
    $body //= '';
    $head =~ s/\r?\n[ \t]+/ /g;
    my %h;
    for my $l (split /\r?\n/, $head) {
        next unless $l =~ /^([!-9;-~]+):\s*(.*)$/;
        my $k = lc $1; $h{$k} //= $2;
    }
    return (\%h, $body);
}
sub header { my ($raw, $name) = @_; my ($h) = _split_head($raw); $h->{lc $name} }

sub _param { my ($v, $p) = @_; return $1 if $v =~ /;\s*\Q$p\E\s*=\s*"([^"]*)"/i; return $1 if $v =~ /;\s*\Q$p\E\s*=\s*([^;\s]+)/i; undef }

sub _decode {
    my ($body, $cte) = @_;
    $cte = lc($cte // '');
    return decode_base64($body) if $cte =~ /base64/;
    return decode_qp($body) if $cte =~ /quoted-printable/;
    return $body;
}

# Returns list of iCalendar texts found anywhere in the message.
sub calendar_parts {
    my ($raw, $depth) = @_;
    $depth //= 0;
    return () if $depth > 10;
    my ($h, $body) = _split_head($raw);
    my $ct = $h->{'content-type'} // 'text/plain';
    my ($type) = lc($ct) =~ /^\s*([^;\s]+)/;
    $type //= 'text/plain';
    if ($type =~ m{^multipart/}) {
        my $b = _param($ct, 'boundary') // return ();
        my @parts = split /^--\Q$b\E(?:--)?[ \t]*\r?$/m, $body;
        shift @parts;            # preamble
        my @out;
        for my $p (@parts) { $p =~ s/\A\r?\n//; next unless $p =~ /\S/; push @out, calendar_parts($p, $depth + 1) }
        return @out;
    }
    if ($type eq 'message/rfc822') { return calendar_parts(_decode($body, $h->{'content-transfer-encoding'}), $depth + 1) }
    my $fname = _param($h->{'content-disposition'} // '', 'filename') // _param($ct, 'name') // '';
    if ($type eq 'text/calendar' || $type eq 'application/ics' || $fname =~ /\.ics\z/i) {
        my $t = _decode($body, $h->{'content-transfer-encoding'});
        return $t =~ /BEGIN:VCALENDAR/ ? ($t) : ();
    }
    return ();
}

# ---------- iCalendar ----------
sub _unescape { my $v = shift; $v =~ s/\\n/\n/gi; $v =~ s/\\([,;\\])/$1/g; $v }

# parse($text) -> { method => 'REQUEST', events => [ {NAME => {value, params}} ...], tzids => {..} }
sub parse {
    my ($text) = @_;
    $text =~ s/\r?\n[ \t]//g;   # unfold
    my (%cal, @stack, $ev);
    $cal{events} = []; $cal{tzids} = {};
    for my $line (split /\r?\n/, $text) {
        next unless length $line;
        if ($line =~ /^BEGIN:(\S+)/i) { push @stack, uc $1; $ev = {} if uc $1 eq 'VEVENT' && @stack == 2; next }
        if ($line =~ /^END:(\S+)/i) {
            my $c = pop @stack;
            if (($c // '') eq 'VEVENT' && @stack == 1 && $ev) { push @{ $cal{events} }, $ev; undef $ev }
            next;
        }
        my ($nameparams, $value) = $line =~ /^((?:[^:"]|"[^"]*")*):(.*)$/ or next;
        my ($name, @p) = split /;(?=(?:[^"]*"[^"]*")*[^"]*$)/, $nameparams;
        $name = uc $name;
        my %params = map { my ($k, $v) = split /=/, $_, 2; (uc $k => do { ($v // '') =~ s/^"|"$//gr }) } @p;
        my $cur = $stack[-1] // '';
        if ($cur eq 'VCALENDAR' && $name eq 'METHOD') { $cal{method} = uc $value }
        elsif ($cur eq 'VTIMEZONE' && $name eq 'TZID') { $cal{tzids}{$value} = 1 }
        elsif ($cur eq 'VEVENT' && @stack == 2 && $ev) {
            if ($name eq 'EXDATE' || $name eq 'RDATE') { push @{ $ev->{$name} }, { value => $value, params => \%params } }
            else { $ev->{$name} //= { value => $value, params => \%params } }
        }
    }
    $cal{method} //= 'PUBLISH';
    return \%cal;
}

# ---------- time zones ----------
my %WIN = (
 'Dateline Standard Time'=>'Etc/GMT+12','Hawaiian Standard Time'=>'Pacific/Honolulu','Alaskan Standard Time'=>'America/Anchorage',
 'Pacific Standard Time'=>'America/Los_Angeles','US Mountain Standard Time'=>'America/Phoenix','Mountain Standard Time'=>'America/Denver',
 'Central Standard Time'=>'America/Chicago','Central America Standard Time'=>'America/Guatemala','Canada Central Standard Time'=>'America/Regina',
 'Central Standard Time (Mexico)'=>'America/Mexico_City','Eastern Standard Time'=>'America/New_York','US Eastern Standard Time'=>'America/Indianapolis',
 'Atlantic Standard Time'=>'America/Halifax','Newfoundland Standard Time'=>'America/St_Johns','E. South America Standard Time'=>'America/Sao_Paulo',
 'Argentina Standard Time'=>'America/Buenos_Aires','SA Pacific Standard Time'=>'America/Bogota','UTC'=>'UTC','Coordinated Universal Time'=>'UTC',
 'GMT Standard Time'=>'Europe/London','Greenwich Standard Time'=>'Atlantic/Reykjavik','W. Europe Standard Time'=>'Europe/Berlin',
 'Central Europe Standard Time'=>'Europe/Budapest','Romance Standard Time'=>'Europe/Paris','Central European Standard Time'=>'Europe/Warsaw',
 'E. Europe Standard Time'=>'Europe/Chisinau','FLE Standard Time'=>'Europe/Kiev','GTB Standard Time'=>'Europe/Bucharest','Israel Standard Time'=>'Asia/Jerusalem',
 'South Africa Standard Time'=>'Africa/Johannesburg','Russian Standard Time'=>'Europe/Moscow','Arabian Standard Time'=>'Asia/Dubai',
 'India Standard Time'=>'Asia/Calcutta','China Standard Time'=>'Asia/Shanghai','Singapore Standard Time'=>'Asia/Singapore',
 'Tokyo Standard Time'=>'Asia/Tokyo','Korea Standard Time'=>'Asia/Seoul','AUS Eastern Standard Time'=>'Australia/Sydney',
 'E. Australia Standard Time'=>'Australia/Brisbane','New Zealand Standard Time'=>'Pacific/Auckland',
);
my @LABEL = ( # Outlook "(UTC-06:00) Central Time (US & Canada)" style TZIDs
 [qr/Central Time \(US/i,'America/Chicago'],[qr/Eastern Time \(US/i,'America/New_York'],[qr/Mountain Time \(US/i,'America/Denver'],
 [qr/Pacific Time \(US/i,'America/Los_Angeles'],[qr/Arizona/i,'America/Phoenix'],[qr/Alaska/i,'America/Anchorage'],[qr/Hawaii/i,'Pacific/Honolulu'],
 [qr/London|Dublin/i,'Europe/London'],[qr/Amsterdam|Berlin/i,'Europe/Berlin'],[qr/Brussels|Paris/i,'Europe/Paris'],
);
sub iana {
    my ($tzid, $default) = @_;
    return $default unless defined $tzid && length $tzid;
    $tzid =~ s/^"|"$//g;
    return $WIN{$tzid} if $WIN{$tzid};
    return $tzid if $tzid =~ m{^(?:[A-Z][A-Za-z_]+/[A-Za-z_/+\-]+|UTC|Etc/\S+)$};
    if ($tzid =~ m{/((?:America|Europe|Asia|Africa|Australia|Pacific|Atlantic)/[A-Za-z_]+)}) { return $1 }  # /mozilla.org/.../America/Chicago
    for my $l (@LABEL) { return $l->[1] if $tzid =~ $l->[0] }
    return $default;
}

# ---------- VEVENT -> Google ----------
sub _dt {   # value + params -> Google start/end object
    my ($p, $deftz) = @_;
    my $v = $p->{value};
    if (($p->{params}{VALUE} // '') eq 'DATE' || $v =~ /^\d{8}$/) {
        return { date => sprintf('%s-%s-%s', unpack 'A4A2A2', $v) };
    }
    my ($Y,$M,$D,$h,$m,$s,$z) = $v =~ /^(\d{4})(\d\d)(\d\d)T(\d\d)(\d\d)(\d\d)(Z?)$/ or return undef;
    my $iso = "$Y-$M-${D}T$h:$m:$s";
    return { dateTime => "${iso}Z", timeZone => 'UTC' } if $z;
    return { dateTime => $iso, timeZone => iana($p->{params}{TZID}, $deftz) };
}

sub _add_duration {   # wall-clock arithmetic on a Google time object
    my ($t, $dur) = @_;
    my ($sign, $w, $d, $h, $m, $s) = $dur =~ /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/ or return undef;
    my $secs = (($w//0)*7*86400 + ($d//0)*86400 + ($h//0)*3600 + ($m//0)*60 + ($s//0)) * (($sign//'+') eq '-' ? -1 : 1);
    if ($t->{date}) {
        my ($Y,$M,$D) = split /-/, $t->{date};
        return { date => strftime('%Y-%m-%d', gmtime(timegm(0,0,12,$D,$M-1,$Y) + $secs)) };
    }
    my ($Y,$M,$D,$hh,$mm,$ss,$z) = $t->{dateTime} =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)(Z?)/;
    return { dateTime => strftime('%Y-%m-%dT%H:%M:%S', gmtime(timegm($ss,$mm,$hh,$D,$M-1,$Y) + $secs)) . $z, timeZone => $t->{timeZone} };
}

sub recid_str {   # normalised RECURRENCE-ID ('' when none)
    my $ev = shift;
    my $r = $ev->{'RECURRENCE-ID'} or return '';
    my $t = _dt($r, 'floating') // return $r->{value};
    return $t->{date} // ($t->{dateTime} . ($t->{dateTime} =~ /Z$/ ? '' : "|$t->{timeZone}"));
}

sub _ical_time {   # Google time object -> "EXDATE;TZID=..:..." suffix
    my $t = shift;
    if ($t->{date}) { (my $d = $t->{date}) =~ s/-//g; return ";VALUE=DATE:$d" }
    (my $v = $t->{dateTime}) =~ s/[-:]//g;
    return ":$v" if $v =~ /Z$/;
    return ";TZID=$t->{timeZone}:$v";
}

# to_google($vevent, default_tz => 'America/Chicago', exdates => [time objs]) -> body
sub to_google {
    my ($ev, %o) = @_;
    my $deftz = $o{default_tz} // 'America/Chicago';
    my $start = _dt($ev->{DTSTART} // return undef, $deftz) // return undef;
    my $end = $ev->{DTEND} ? _dt($ev->{DTEND}, $deftz)
            : $ev->{DURATION} ? _add_duration($start, $ev->{DURATION}{value})
            : $start->{date} ? _add_duration($start, 'P1D') : { %$start };
    my %g = (start => $start, end => $end, summary => _unescape($ev->{SUMMARY}{value} // '(no title)'));
    $g{location} = _unescape($ev->{LOCATION}{value}) if $ev->{LOCATION} && length $ev->{LOCATION}{value};
    $g{summary} = $o{busy_title} // 'Busy (work)' if ($o{detail} // 'full') eq 'busy'
        || ($ev->{CLASS}{value} // '') =~ /PRIVATE|CONFIDENTIAL/i;
    delete $g{location} if $g{summary} eq ($o{busy_title} // 'Busy (work)');
    $g{transparency} = (($ev->{TRANSP}{value} // '') =~ /TRANSPARENT/i) ? 'transparent' : 'opaque';
    if (!$ev->{'RECURRENCE-ID'}) {
        my @rec;
        push @rec, "RRULE:$ev->{RRULE}{value}" if $ev->{RRULE};
        for my $x (@{ $ev->{EXDATE} // [] }) {
            for my $v (split /,/, $x->{value}) { my $t = _dt({ value => $v, params => $x->{params} }, $deftz); push @rec, 'EXDATE' . _ical_time($t) if $t }
        }
        for my $r (@{ $ev->{RDATE} // [] }) {
            for my $v (split /,/, $r->{value}) { my $t = _dt({ value => $v, params => $r->{params} }, $deftz); push @rec, 'RDATE' . _ical_time($t) if $t }
        }
        push @rec, 'EXDATE' . _ical_time($_) for @{ $o{exdates} // [] };
        if (@rec && $ev->{RRULE}) {
            my %u; @rec = grep { !$u{$_}++ } @rec;
            $g{recurrence} = \@rec;
        }
    }
    return \%g;
}

sub recid_time { my ($ev, $deftz) = @_; $ev->{'RECURRENCE-ID'} ? _dt($ev->{'RECURRENCE-ID'}, $deftz // 'America/Chicago') : undef }
1;
