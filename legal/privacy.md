# Privacy Policy — plcal (o365-gcal-sync)

DRAFT for Todd's review — not legal advice. Placeholders: <ANGLE_BRACKETS>. Items tagged [GAP] must be confirmed by Todd before publishing; delete this banner and all [GAP]/[INF] notes before publishing.
Structure/tone mirrors https://zhc.fdh.bz/legal/privacy.html (numbered sections; optional plain-English line under each).

**plcal** · <OPERATOR_NAME> [GAP: Todd T. Fries personally, or Free Daemon Consulting, LLC?] · Effective: <EFFECTIVE_DATE> · Last updated: <DATE>
Homepage: <HOMEPAGE_URL> · Source: https://github.com/toddfries/plcal

## 1. Who we are
plcal ("the app", "we") is an open-source command-line tool that copies calendar events from a Microsoft Office 365 calendar (via Microsoft Graph) or from calendar invitations (`.ics`) found in your local mail folder into a Google Calendar you choose. It runs on your own computer. Contact for privacy matters: <CONTACT_EMAIL>.

*Plain English: it's a script that runs on your machine and copies meetings into your Google Calendar.* [optional]

## 2. What the app accesses
When you authorize it, the app accesses Google user data and other data as follows:
- **Google Calendar data** (scope `https://www.googleapis.com/auth/calendar.events` [INF: confirm exact scope(s) in final OAuth client; README lists only this one]): the app searches your chosen Google calendar for events it previously created, then creates, updates, and deletes only events it tagged itself (private extended property `managedBy=o365-gcal-sync`). Your own events on that calendar are not changed.
- **Microsoft 365 calendar data** (Microsoft Graph `Calendars.Read`, read-only): event ID, subject, location, start/end, all-day flag, cancelled flag, free/busy status, event type, series ID, and sensitivity — read only to copy them to your Google Calendar.
- **Calendar invitations from your local Maildir**: the app reads `text/calendar` parts and `.ics` attachments from folders you point it at.
- **Authorization tokens**: the app obtains short-lived access tokens by running the separate `pizauth` program on your computer. The app does not store, log, or print tokens.

## 3. How we use the data
Only to provide the user-facing feature you invoked: mirroring events (adds, updates, cancellations) into your Google Calendar. We do not use it for anything else.

## 4. Where data goes / sharing
- Data flows directly between your computer, Microsoft Graph, and Google Calendar API. [INF: only graph.microsoft.com and www.googleapis.com/calendar/v3 appear in the code]
- <OPERATOR_NAME> does not operate any server for the app and does not receive, collect, or have access to your data. [INF from repo: no hosted component is described; GAP: Todd confirm]
- We do not sell data, do not share it with third parties, do not use it for advertising, and do not use it to train AI or machine-learning models.
- No humans read your Google user data, except where you send it to us (e.g. in a bug report) or where required by law. [INF; matches Limited Use]

## 5. Google API Services User Data Policy (Limited Use)
plcal's use and transfer to any other app of information received from Google APIs will adhere to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements.

## 6. Storage, retention, and deletion
- Event data is stored in your own Google Calendar and Microsoft account; their policies govern that storage.
- **Local state file** (calendar-invite mode only; default `~/.local/state/maildir-ics-trawl.json`): holds processed message IDs and, per event key, the latest sequence/timestamp and last event data, stored only on your computer. Delete the file to remove it.
- **Logs**: the app prints one line per change and a summary to your terminal; any log file is created by your own cron/redirect. [GAP: confirm whether change lines include event titles]
- To remove what plcal created: delete the events tagged `managedBy=o365-gcal-sync` from your Google Calendar (or delete the calendar).
- To revoke access: https://myaccount.google.com/permissions (Google) and https://account.live.com/consent/Manage / your organization's Entra admin (Microsoft). Revocation stops all access immediately.

## 7. Your rights and requests
Because we hold none of your data, requests about data in Google or Microsoft are handled in those services. For anything else, email <CONTACT_EMAIL>; we aim to respond within 30 days. [mirrors ZHC §8]

## 8. Children
The app is not directed to children and is not intended for anyone under 13. [mirrors ZHC §9]

## 9. Security
The app uses HTTPS for all API calls and does not persist OAuth tokens (obtained on demand from `pizauth`). No software is 100% secure. Report concerns to <CONTACT_EMAIL>.

## 10. Changes
We may update this policy by posting a new version with a new "Last updated" date. If we change how Google user data is used, we will notify users and obtain consent before using it in the new way. [required by Google's User Data Policy]

## 11. Contact
<CONTACT_EMAIL> · <OPERATOR_NAME> · <HOMEPAGE_URL>
