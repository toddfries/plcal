package O365GCal::Trawl;
# Apply iTIP (REQUEST/CANCEL) VEVENTs found in mail to Google, with ordering rules.
use strict; use warnings;
use JSON::PP ();
use Digest::SHA qw(sha1_hex);
use Fcntl qw(:flock);
use O365GCal::ICS;

my $JSON = JSON::PP->new->canonical(1)->utf8(1)->pretty(1);

sub new {
    my ($class, %a) = @_;
    bless { g => $a{google}, state_file => $a{state_file}, default_tz => $a{default_tz} // 'America/Chicago',
            detail => $a{detail} // 'full', log => $a{log} // sub { print "$_[0]\n" },
            state => { msgs => {}, ev => {} }, stats => {} }, $class;
}

sub load_state {
    my $s = shift; my $f = $s->{state_file} or return;
    open($s->{lockfh}, '>>', "$f.lock") or die "lock $f.lock: $!\n";
    flock($s->{lockfh}, LOCK_EX | LOCK_NB) or die "another maildir-ics-trawl is running\n";
    return unless -e $f;
    open my $fh, '<', $f or die "$f: $!\n";
    $s->{state} = $JSON->decode(do { local $/; <$fh> });
}

sub save_state {
    my $s = shift; my $f = $s->{state_file} or return;
    open my $fh, '>', "$f.tmp" or die "$f.tmp: $!\n";
    print $fh $JSON->encode($s->{state}); close $fh or die "$f.tmp: $!\n";
    rename "$f.tmp", $f or die "rename $f: $!\n";
}

sub _stat { $_[0]{stats}{$_[1]}++ }

sub message_id {
    my ($raw) = @_;
    my $m = O365GCal::ICS::header($raw, 'Message-ID');
    return ($m && $m =~ /(<[^>]+>)/) ? $1 : 'sha1:' . sha1_hex($raw);
}

# Process one raw RFC822 message. Returns number of VEVENTs considered.
sub process_message {
    my ($s, $raw) = @_;
    my $mid = message_id($raw);
    if ($s->{state}{msgs}{$mid}) { $s->_stat('seen_msg'); return 0 }
    my $n = 0;
    for my $ics (O365GCal::ICS::calendar_parts($raw)) {
        my $cal = O365GCal::ICS::parse($ics);
        for my $ev (@{ $cal->{events} }) { $n++; $s->apply($cal->{method}, $ev) }
    }
    $s->{state}{msgs}{$mid} = time;
    return $n;
}

sub _gkey { "ics|$_[0]|$_[1]" }

sub apply {
    my ($s, $method, $ev) = @_;
    my $uid = $ev->{UID}{value} or do { $s->_stat('no_uid'); return };
    return $s->_stat("ignored_$method") unless $method =~ /^(REQUEST|PUBLISH|CANCEL|ADD)$/;
    my $recid = O365GCal::ICS::recid_str($ev);
    my $k = "$uid|$recid";
    my $seq = $ev->{SEQUENCE}{value} // 0; $seq =~ s/\D//g; $seq ||= 0;
    my $stamp = $ev->{DTSTAMP}{value} // '';
    my $st = $s->{state}{ev};
    if (my $p = $st->{$k}) {
        if ($seq < $p->{seq} || ($seq == $p->{seq} && $stamp le $p->{stamp})) {
            $s->{log}->("stale     $k seq=$seq (have $p->{seq})"); return $s->_stat('stale');
        }
    }
    if ($recid ne '' && (my $m = $st->{"$uid|"})) {   # series cancelled at a later/equal seq wins over exceptions
        if ($m->{cancelled} && $seq <= $m->{seq}) { $s->{log}->("stale     $k (series cancelled)"); return $s->_stat('stale') }
    }
    my $cancel = $method eq 'CANCEL' || (($ev->{STATUS}{value} // '') =~ /CANCELLED/i);
    my $rt = O365GCal::ICS::recid_time($ev, $s->{default_tz});
    my $rec = { seq => $seq, stamp => $stamp, cancelled => $cancel ? 1 : 0, vevent => $ev, ($rt ? (recid_t => $rt) : ()) };

    if ($recid eq '') {
        if ($cancel) {
            $st->{$k} = { %$rec, vevent => undef };
            $s->{g}->delete_by_key(_gkey($uid, ''), 'CANCEL series');
            $s->_drop_overrides($uid, 'series cancelled');
            return $s->_stat('cancel_series');
        }
        my $old = $st->{$k};
        if ($old && $old->{vevent} && ($old->{vevent}{RRULE}{value} // '') ne ($ev->{RRULE}{value} // '')) {
            $s->_drop_overrides($uid, 'RRULE changed');
        }
        $st->{$k} = $rec;
        $s->_push_master($uid);
        return $s->_stat('request_series');
    }
    # single occurrence (exception)
    $st->{$k} = $rec;
    if ($cancel) {
        $s->{g}->delete_by_key(_gkey($uid, $recid), 'CANCEL occurrence');
        $s->_stat('cancel_occurrence');
    } else {
        my $body = O365GCal::ICS::to_google($ev, default_tz => $s->{default_tz}, detail => $s->{detail}) or return $s->_stat('bad_event');
        $body->{_extra_private} = { o365src => 'ics' };
        $s->{g}->upsert(_gkey($uid, $recid), $body);
        $s->_stat('request_occurrence');
    }
    $s->_push_master($uid);
}

sub _overrides {
    my ($s, $uid) = @_;
    my $st = $s->{state}{ev};
    return map { $st->{$_} } grep { index($_, "$uid|") == 0 && $_ ne "$uid|" } sort keys %$st;
}

sub _drop_overrides {
    my ($s, $uid, $why) = @_;
    my $st = $s->{state}{ev};
    for my $k (grep { index($_, "$uid|") == 0 && $_ ne "$uid|" } keys %$st) {
        my ($recid) = substr($k, length($uid) + 1);
        $s->{g}->delete_by_key(_gkey($uid, $recid), $why) unless $st->{$k}{cancelled};
        delete $st->{$k};
    }
}

sub _push_master {
    my ($s, $uid) = @_;
    my $m = $s->{state}{ev}{"$uid|"};
    return unless $m && $m->{vevent} && !$m->{cancelled};
    my @ex = map { $_->{recid_t} } grep { $_->{recid_t} } $s->_overrides($uid);
    my $body = O365GCal::ICS::to_google($m->{vevent}, default_tz => $s->{default_tz}, detail => $s->{detail}, exdates => \@ex)
        or return $s->_stat('bad_event');
    $body->{_extra_private} = { o365src => 'ics' };
    $s->{g}->upsert(_gkey($uid, ''), $body);
}

sub scan_maildirs {
    my ($s, @dirs) = @_;
    my @files;
    for my $d (@dirs) {
        for my $sub (qw(new cur)) {
            opendir(my $dh, "$d/$sub") or do { warn "skip $d/$sub: $!\n"; next };
            push @files, map { "$d/$sub/$_" } grep { !/^\./ } readdir $dh;
        }
    }
    my $n = 0;
    for my $f (sort @files) {
        open my $fh, '<:raw', $f or next;
        my $raw = do { local $/; <$fh> };
        if ($raw !~ m{text/calendar|application/ics|\.ics|BEGIN:VCALENDAR}i) {   # cheap prefilter
            $s->{state}{msgs}{ message_id($raw) } //= time; next;
        }
        $n += $s->process_message($raw);
    }
    return $n;
}
1;
