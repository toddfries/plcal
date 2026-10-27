# Terms of Service — plcal (o365-gcal-sync)

DRAFT for Todd's review — not legal advice. Placeholders <ANGLE_BRACKETS>; [GAP] = Todd must confirm. Google lists a ToS as OPTIONAL for OAuth verification (privacy policy is mandatory), but it is shown on the consent screen if provided.
Structure/boilerplate mirrors https://zhc.fdh.bz/legal/terms.html (numbered sections; disclaimer, liability cap, governing law, changes, contact). Dropped as N/A: accounts, environments, payments/refunds, Behavior Bucks, hosted API tokens.

**plcal** · <OPERATOR_NAME> [GAP] · Effective: <EFFECTIVE_DATE> · Homepage: <HOMEPAGE_URL>

## 1. Who we are
These Terms govern your use of plcal (a.k.a. o365-gcal-sync), open-source software published at https://github.com/toddfries/plcal by <OPERATOR_NAME> ("we", "us"). plcal runs on your computer; we do not operate a hosted service for it. [INF]

## 2. Acceptance
By running plcal or authorizing it to access your Google or Microsoft account, you agree to these Terms and our Privacy Policy (<PRIVACY_URL>). If you do not agree, do not use it.

## 3. What the app does and your responsibilities
plcal copies events from your Microsoft 365 calendar or calendar invitations into a Google Calendar you choose, and may create, change, or delete events it created there. You are responsible for: having the right to copy that data (including your employer's or client's policies — plcal's `--detail busy` option can hide titles); your own Google Cloud OAuth client and credentials [GAP: does each user bring their own client, or will Todd ship a shared one?]; and keeping credentials confidential. Test on a throwaway calendar first.

## 4. Acceptable use
Don't use plcal unlawfully, to access accounts or data you aren't authorized to access, or to violate Google's or Microsoft's terms or API policies, including the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy).

## 5. Open-source license
The software is licensed under the license in the repository. [GAP: repo has no LICENSE file — add one (e.g. ISC/BSD/MIT) and name it here.] These Terms govern use of the app; the license governs the code.

## 6. Data
How data is handled is described in the Privacy Policy. You retain all rights to your calendar data.

## 7. Feedback
Bug reports and suggestions may be used to improve the software. [mirrors ZHC §9, trimmed]

## 8. Disclaimers
TO THE MAXIMUM EXTENT PERMITTED BY LAW, PLCAL IS PROVIDED "AS IS" AND "AS AVAILABLE," WITHOUT WARRANTIES OF ANY KIND, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT. Sync may miss, duplicate, or incorrectly alter events (for example around recurring-event exceptions or daylight-saving changes). You remain responsible for checking your calendar.

## 9. Limitation of liability
TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE WILL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR FOR LOST PROFITS, DATA, MEETINGS, OR GOODWILL. OUR AGGREGATE LIABILITY WILL NOT EXCEED USD $50. [ZHC uses greater of fees paid or $50; plcal is free]

## 10. Termination
You may stop using plcal at any time and revoke its access (https://myaccount.google.com/permissions). We may discontinue the software or any Google/Microsoft integration at any time. Sections 8–9, 11 survive.

## 11. Governing law
Laws of the State of Oklahoma, USA; venue in the state or federal courts located in Oklahoma, except where mandatory consumer-protection law provides otherwise. [mirrors ZHC §16; GAP confirm for plcal / operator entity]

## 12. Changes
We may update these Terms by posting a revised version with a new effective date. Continued use after that date constitutes acceptance where permitted by law.

## 13. Contact
<CONTACT_EMAIL> · <OPERATOR_NAME> · <HOMEPAGE_URL>
