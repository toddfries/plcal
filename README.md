# o365-gcal-sync

Mirror a client's Office 365 work calendar onto a separate Google "work" calendar
(adds, updates, cancels). Two independent tools share one Google-side library:

| tool | source | good for |
|---|---|---|
| `bin/o365-gcal-sync` (D1) | Microsoft Graph `/me/calendarView` | the complete calendar, incl. things you created yourself |
| `bin/maildir-ics-trawl` (D2) | `text/calendar` invites in your mbsync Maildir | needs no Graph consent; only sees what was mailed to you |

**Point them at different Google calendars** (or run only one). They key events
differently (`graph` vs `ics` source), so both on one calendar would show duplicates.

Runs on the laptop (OpenBSD), not on the box. Tokens come from `pizauth show <account>`;
they are never stored, logged or printed.

## Dependencies
Perl core only (JSON::PP, HTTP::Tiny, Digest::SHA, MIME::Base64, MIME::QuotedPrint,
Time::Local, Getopt::Long). HTTPS for HTTP::Tiny needs:

    doas pkg_add p5-IO-Socket-SSL p5-Net-SSLeay pizauth isync

No DateTime: times are sent to Google as wall clock + IANA zone and Google does the
zone math. Windows zone names (`Central Standard Time`), Outlook labels
(`(UTC-06:00) Central Time (US & Canada)`) and `/mozilla.org/.../Europe/Paris`
TZIDs are mapped in `lib/O365GCal/ICS.pm`.

## Setup
1. **pizauth accounts** (`~/.config/pizauth.conf`), next to your existing mail account.
   Same `client_id` as the mail account; the app registration must allow the
   Graph `Calendars.Read` delegated permission (client admin consent may be needed —
   if the tenant refuses, use D2).

       account "o365cal" {
           auth_uri = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize";
           token_uri = "https://login.microsoftonline.com/common/oauth2/v2.0/token";
           client_id = "SAME-CLIENT-ID-AS-MAIL";
           scopes = ["https://graph.microsoft.com/Calendars.Read", "offline_access"];
       }
       account "gcal" {
           auth_uri = "https://accounts.google.com/o/oauth2/auth";
           token_uri = "https://oauth2.googleapis.com/token";
           client_id = "YOUR-GOOGLE-DESKTOP-CLIENT-ID";
           client_secret = "YOUR-GOOGLE-CLIENT-SECRET";
           scopes = ["https://www.googleapis.com/auth/calendar.events"];
       }

   `pizauth reload`, then `pizauth show o365cal` and `pizauth show gcal` once each to
   authorise in the browser (redirect to stdout is fine: `> /dev/null`).
   Google client: Cloud Console → enable "Google Calendar API" → OAuth client type
   "Desktop app"; add yourself as a test user.
2. **Google calendar id**: calendar.google.com → ⚙ Settings → your "work" calendar →
   "Integrate calendar" → *Calendar ID* (looks like `abc123…@group.calendar.google.com`).
   Make a throwaway "work-test" calendar first and use its id.
3. `export GCAL_ID='…@group.calendar.google.com'` (or pass `--calendar`).
   Account names default to `o365cal` / `gcal` (`--graph-account`, `--google-account`,
   or `O365_PIZAUTH`, `GCAL_PIZAUTH`).

## What to try first (in order)
1. `pizauth show o365cal >/dev/null && echo ok` — proves Graph consent works.
2. `bin/o365-gcal-sync --calendar "$TEST_ID" --dry-run` — lists what it *would* create.
3. Same without `--dry-run`, check the test calendar; run again → expect only `unchanged=N`.
4. Edit/cancel a meeting in Outlook, run again → `updated=1` / `deleted=1`.
5. `bin/maildir-ics-trawl --calendar "$TEST2_ID" --dry-run ~/Maildir/work/INBOX`
   (dry-run never writes the state file, so you can repeat it).
6. Switch to the real work calendar; `--detail busy` shows only "Busy (work)" if the
   client's meeting titles shouldn't be visible to family. Private/confidential items
   are always masked.

## Options
    o365-gcal-sync --calendar ID [--dry-run] [--past 7] [--future 90] [--detail full|busy] [--no-delete]
    maildir-ics-trawl --calendar ID [--dry-run] [--state FILE] [--tz America/Chicago] [--detail full|busy] MAILDIR...

Output: one line per change (`created|updated|deleted`) and a summary
`created=.. updated=.. unchanged=.. deleted=.. missing=..`.

## Scheduling
cron (D1 every 15 min):

    */15 * * * * cd $HOME/src/o365-gcal-sync && GCAL_ID=... bin/o365-gcal-sync >>$HOME/.local/state/o365-gcal-sync.log 2>&1

mbsync has no post-sync hook, so wrap it (D2):

    #!/bin/sh
    # ~/bin/mbsync-work: use this instead of `mbsync work` (cron or neomutt macro)
    mbsync work || exit $?
    exec $HOME/src/o365-gcal-sync/bin/maildir-ics-trawl --calendar "$GCAL_ID" \
        $HOME/Maildir/work/INBOX >>$HOME/.local/state/maildir-ics-trawl.log 2>&1

## How it stays idempotent (keyed-calendar-upsert)
Every event we write carries private extendedProperties `managedBy=o365-gcal-sync`,
`o365key=sha1(key)`, `o365hash=sha1(normalised content)`, `o365src=graph|ics`.
Lookup is by that property, so nothing depends on a local DB for Google ids. Same hash →
no API write. Only events tagged `managedBy` are ever changed or deleted; your own
events on that calendar are left alone. `sendUpdates=none` always (no mail to attendees).

* D1 key: `iCalUId|start(UTC)`. Each occurrence of a series is mirrored as its own
  single event (calendarView expands them), so recurring-exception handling is
  Outlook's problem, not ours. Anything with our tag inside the window that Graph no
  longer returns, or returns with `isCancelled`, is deleted. Events outside the window
  are never touched.
* D2 key: `UID|RECURRENCE-ID`. State file (`~/.local/state/maildir-ics-trawl.json`)
  holds processed Message-IDs (or sha1 of the file if there's none) plus, per key, the
  winning SEQUENCE/DTSTAMP and the last VEVENT.

## D2 rules and edge cases
* **Which version wins**: higher `SEQUENCE`; on a tie, later `DTSTAMP`; exact replay
  ignored. So **out-of-order mail** (old update read after a newer one, or an mbsync
  re-download) is harmless.
* `METHOD:REQUEST`/`PUBLISH`/`ADD` → add/update; `CANCEL` (or `STATUS:CANCELLED`) → delete.
  `REPLY`/`COUNTER`/`REFRESH` (attendee responses) are ignored.
* **Recurring exceptions / moved occurrence**: an override (has RECURRENCE-ID) becomes
  a standalone Google event at the new time, and the master gets an `EXDATE` for the
  original slot so it isn't shown twice.
* **Cancelled single occurrence**: master gets an `EXDATE`; any override event is deleted.
* **Exception arrives before the series**: remembered in state; EXDATE applied once
  the master arrives.
* **Organizer changes the RRULE**: per RFC 5546 the old exceptions no longer apply;
  we delete their override events and drop their EXDATEs, then push the new series.
  Outlook usually re-sends surviving exceptions afterwards.
* **Series cancelled**: master and all overrides deleted; later exceptions with an equal
  or lower SEQUENCE are ignored.
* **Missing VTIMEZONE**: we never need it — TZID is mapped by name. Unknown
  names and floating times fall back to `--tz` (default America/Chicago).
* **All-day**: `VALUE=DATE` → Google `date`; no DTEND means one day. `DURATION` is
  supported (wall-clock add; an event spanning a DST change may be off by an hour).
* **Forwarded invites**: `message/rfc822` parts and `.ics` attachments are searched;
  the same UID/SEQUENCE seen twice is a no-op. A forward carries the organizer's UID,
  so a forwarded copy updates the same event.
* Invites only arrive for meetings you're invited to; things you put on the client
  calendar yourself, or invites deleted before mbsync, are invisible to D2. Use D1 for those.
* Mail removed from the Maildir doesn't delete anything; only a CANCEL does.
* Override events don't get Google's "this and following" linkage; each exception
  is its own event.

## Tests
    prove -l t/     # synthetic fixtures under t/fixtures (example.invalid), no network
