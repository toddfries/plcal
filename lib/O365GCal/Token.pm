package O365GCal::Token;
# Fetch an access token from pizauth. Never print or log it.
use strict; use warnings;
sub get {
    my ($account) = @_;
    die "no pizauth account given\n" unless defined $account && length $account;
    die "bad account name\n" unless $account =~ /\A[\w.\-\@]+\z/;
    open(my $fh, '-|', 'pizauth', 'show', $account) or die "cannot run pizauth: $!\n";
    my $tok = do { local $/; <$fh> };
    close $fh;
    die "pizauth show $account failed (run: pizauth show $account interactively to authorise)\n"
        if $? != 0 || !defined $tok;
    $tok =~ s/\s+\z//;
    die "empty token from pizauth\n" unless length $tok;
    return $tok;
}
1;
