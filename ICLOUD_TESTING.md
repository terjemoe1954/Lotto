# iCloud verification before release

The app keeps the existing `iCloud.iCloude.com.terjemoe.Lottery` container and
existing store. SwiftData retains automatic CloudKit configuration, which uses the private database
from the existing single-container entitlement in signed builds. The added
`LotteryDeliveryChange` model records mark and unmark actions without changing
existing Lotto or international row fields.

The iCloud account panel reports account availability only. It does not report a
successful upload/download or a completed synchronization. Data remains local
when offline; the framework handles later synchronization.

## Automated coverage

Tests cover additive migration of an existing disk store, reopening persisted
marks, legacy UserDefaults import, idempotency, stable resolution of duplicate and
out-of-order changes, preservation of unmark actions, local monotonic timestamps,
and current/legacy backup formats. These tests simulate record merging; they do
not prove transport through Apple's servers.

Delivery changes resolve by timestamp, with a stable change-ID tie break. Legacy
positive marks receive a baseline timestamp so a late import from another device
cannot override a newer explicit unmark. False changes are retained. The event
history must not be deleted simply because a row is currently unmarked.

## Two-device check

1. Export a full backup before installing the update on an existing-data device.
2. Use signed builds of the same app on two devices signed into the same iCloud
   account. Confirm both builds use the same CloudKit environment and container.
   Open Settings and check account access. A status of Available is only a prerequisite.
   Unsigned simulator builds skip CKContainer account checks and show a device-check
   message instead; they can still run local tests without CloudKit entitlements.
3. Create a Lotto row on device A. Confirm the row appears on B. Mark it registered
   in the Weekly report on A, then confirm the gray mark appears on B and in the
   older Mine rekker screen.
4. Unmark the row on B. Confirm A removes the mark. Reopen both apps and confirm
   the old local legacy mark does not reappear.
5. Repeat with Vikinglotto and Eurojackpot, including two different draw dates in
   the same week. Verify marks and exported reports refer to the correct date/game.
6. While one device is offline, change a mark. Reconnect, allow synchronization and
   verify both devices converge. Also change different rows independently on each
   device. Do not assume immediate delivery, or use old app versions in this check.
7. Export and restore a full backup. Confirm both positive and removed marks are
   reflected on the other device after synchronization. A draws-only import must
   not change delivery status. A backup predating delivery marks leaves them intact.
8. On a separate test environment without an iCloud account, verify local rows,
   marks, report export and backup still work. Do not sign out a personal device
   merely to perform this check.

## TestFlight / App Store

- Develop and verify the new model using signed development builds first.
- Inspect the existing container in CloudKit Console. Deploy the additive schema,
  including the new delivery-change record type and international model types, to
  Production before testing TestFlight/App Store builds.
- Do not reset the container, rename the existing container or delete old types.
- Repeat the two-device check using production builds. Development and Production
  are separate environments; a successful Debug test does not prove Production works.
- Review privacy disclosures before distribution. Own rows and delivery status use
  the user's private database; no new shared public database is introduced here.

Common draw history still uses the existing SwiftData store and its configured
sync behavior. Moving it into an independent local cache is a separate data-store
migration and has not been performed in this change. Local display preferences
(such as hiding registered rows) remain device-specific. Full exported backups
remain available alongside synchronization.

References: [SwiftData synchronization](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices),
[CloudKit schema deployment](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).

## Device verification on 2026-11-10

The same signed Debug build was installed as an update on an iPhone 15 Pro and
an iPad (10th generation), without uninstalling the app. The user confirmed the
devices use the same iCloud account and that account access was Available on both.

Verified basic flow:
- A new Vikinglotto row saved on iPhone appeared on iPad.
- A registered mark set on iPhone reached iPad. A read-only diagnostic snapshot
  confirmed the same change identifier and value in both stores.
- The mark was removed on iPad. The iPad store contained the newer false change
  and reported a successful export after that change. The user subsequently
  confirmed the mark was removed on iPhone after unlocking and reopening Lotto.

Observed limitation: propagation was delayed. The iPhone had not started a new
import in the inspected interval, and a later diagnostic relaunch was blocked
while the phone was locked. This test establishes basic two-way delivery and
undo behavior; it does not establish immediate background delivery.

Temporary device-database snapshots used for diagnosis were deleted from the Mac
after inspection. No diagnostic snapshot was written back to either device.

Still pending before release: the offline/concurrent-edit checks, cross-device
backup restoration, and equivalent tests with the Production schema and
TestFlight builds. No production-schema deployment or App Store submission was
performed during this test.

## Offline and backup checks on 2026-11-10

Physical offline check confirmed by the user:
- With iPad in airplane mode and Wi-Fi off, the Vikinglotto test row was marked
  registered. The mark remained after closing and reopening Lotto while offline.
- After reconnecting iPad, the user confirmed that the offline mark appeared on
  iPhone. This verifies offline persistence and eventual upload/download in this flow.

The Settings backup workflow now delegates to LottoBackupStore, shared with the
integration tests. Full restore validates numbers/dates and status records before
replacing data; replacement deletes are staged until the final save. Draws-only
import leaves personal rows and registration changes intact.

The new Check backup file action trial-restores the selected file into an
independent, local, in-memory database with CloudKit disabled. Full backups are
compared for Lotto data, international data and positive/removed registration
status. The check does not replace device data or publish anything to iCloud.

Automated tests additionally cover offline disk reopen, ISO-8601 JSON file round
trip into a second disk store, malformed/truncated files, legacy full backups,
idempotent draws-only imports, isolated change merging and the complete bundled
archive. A physical full-restore-over-existing-data test and concurrent edits on
two physical offline devices remain outside the checks completed so far.

## Exported-file regression on 2026-11-10

The user's actual exported full backup was initially rejected because one older
own Lotto row contained an out-of-range number. This is a domain-data warning,
not proof of a corrupt backup container. The compatibility fix preserves old own
rows exactly and reports those issues; draw data, unreadable dates and malformed
files remain validated. Current row-entry validation is unchanged.

The actual exported file was decoded and trial-restored through LottoBackupStore
in an isolated in-memory database on the Mac. It passed content comparison for
885 own Lotto rows, one own Vikinglotto row, 3,584 draws and registration status.
The single historical data issue was preserved and reported. The original JSON
file and the device databases were not modified by this check. Regression tests
cover lossless recovery of such historical rows and unchanged new-entry rules.

## Favorites follow-up

Favorites add a new private-CloudKit model, LotteryFavoriteChange. The existing
container and all older row/change model fields are retained. The local first-run
prompt flag is not synchronized; favorites and enabled/disabled/cleared choices
are synchronized per game. Backup restore retains old-backup compatibility.

Automated coverage includes favorite validation, inclusion in every suggestion
mode, separate extra pools, limited unique-combination counts, deterministic
completion fallback, disable/clear resolution, additive disk migration and backup
round trip. Actual favorite propagation between the physical iPhone and iPad still
needs its own verification. Deploy the new favorite record type to Production
before testing it through TestFlight.


## Ledger schema and device verification — 2026-11-12

The additive `LotteryLedgerEntry` model was initialized with Apple's
`NSPersistentCloudKitContainer.initializeCloudKitSchema()` workflow from the
signed development build, before opening the same store with SwiftData. The
existing container `iCloud.iCloude.com.terjemoe.Lottery` was retained.

After explicit approval of the concrete deployment scope, CloudKit Console
reported **Changes Deployed — The schema is deployed to Production**. Production
Record Types was separately checked and showed `CD_LotteryLedgerEntry` with
18 fields. Deployment included the framework's supporting asset/move-receipt
fields on the five existing managed types and their indexes, plus the new type
and its standard roles. Existing types and data were not reset or deleted.

Physical devices: iPhone 15 Pro and Terje sin iPad 10 (10th generation), updated
in place with the same signed Debug build, without uninstalling either app.
An opt-in DEBUG diagnostic compared hashed CloudKit account identities (equal)
and observed framework setup/import/export events. Only one explicitly marked
synthetic ledger record was created; no existing personal records were edited.

Verified in Development through Apple's servers:
1. Created the marked record on iPhone: NOK 100 stake, NOK 45 prize.
2. Confirmed the same test identifier and values arrived in the iPad store.
3. Changed the test prize to NOK 50 on iPad and confirmed NOK 50 in iPhone's store.
4. Removed the synthetic record on iPad and confirmed zero matching records on
   both devices. Both reported successful CloudKit export/import events.

Delivery was delayed; one fresh app launch was needed during the initial check.
This does not establish immediate background delivery or concurrent edit semantics.

Simulator verification used the already-running iPhone 17 and iPad Pro 13-inch
(M5), iOS/iPadOS 27.2. Both ran the 86-test suite successfully. Interactive checks
covered opening the new overview, manual entry, NOK totals and net loss, opening
an existing post, and the pause recommendation at the gross monthly stake limit.
iPhone editing changed the prize from 45 to 50 and net from -55 to -50. Test budget
values were cleared. Synthetic UI entries remain only in the local simulators.
The iPad favorite flow saved 1 and 34, showed both in the first labelled
Favorite row, and showed subsequent rows without those locked favorites.
The ordinary prize thresholds, separate number pools, favorite behavior in all
modes, backup round trip and legacy preservation have automated coverage.

`LottoCloudDevelopment` is entirely DEBUG-only and requires explicit launch flags
for schema initialization or mutations of its fixed synthetic test identifier.
Normal development launches remove its diagnostic status file. Release builds
contain neither the schema initialization routine nor the synthetic record hook.

Still separate from these completed Development checks: transport via a signed
Production/TestFlight build, offline/concurrent ledger edits, and restoration of a
full backup over live physical-device data. No App Store Connect upload or public
app release was performed. Production schema presence alone is not proof of
Production data transport.

Final checks: the signed device build and unsigned Release simulator build both
succeeded. The latest iPhone run again passed all 86 tests. The Release executable
was checked for the synthetic identifier and developer launch markers; all were
absent. Both physical devices were updated to the final signed build and launched
normally, without test flags. The diagnostic status file was no longer available
on either device after normal launch, as intended.


## TestFlight 1.1 (7) preparation — 2026-11-12

App Store Connect's latest existing build was 1.1 (6); both target configurations
were advanced to build 7. Release archive succeeded, and Xcode export/upload
reported Upload succeeded / EXPORT SUCCEEDED at 08:42 Europe/Oslo. The export
used app-store-connect, TestFlight internal testing only, and Production iCloud
entitlements. The distribution signing log explicitly confirmed Production.
The archived executable contained none of the DEBUG schema/test-record markers.

Apple processed build 7, the encryption questionnaire was completed for an app
using only Apple's built-in encryption, and the build became Ready to Test.
The existing Internal group (Terje Moe only) was attached and Norwegian test
instructions were saved. No external testers or public App Store release were
requested. Build record: https://appstoreconnect.apple.com/teams/69a6de6f-0408-47e3-e053-5b8c7c11a4d1/apps/6823035777/testflight/ios/31827cc6-acee-45f6-b7ab-df04b693d0f8

Before TestFlight installation, local app-data copies were taken from both
physical devices while their Lotto processes were briefly suspended and then
resumed. Both copied SQLite stores passed PRAGMA quick_check. These temporary
copies are stored locally under /private/tmp/lotto-before-testflight-7 and were
not uploaded. Device-level Production transport results are recorded below
only after they have been observed.

Production transport progress (observed, 08:51–08:52 Europe/Oslo): both physical
devices reported installed Lotto version 1.1, build 7 after TestFlight installation.
Lotto launched normally on both. The iPad retained its 14 own Eurojackpot rows and
403 saved draws in the observed view. A new manual Lotto ledger record marked
`TEST TF7`, dated 2026-11-12, was saved through the iPhone UI with NOK 100 stake
and NOK 45 prize. The iPhone displayed NOK -55 net. Without creating a record on
iPad, its overview then displayed the same totals and the `TEST TF7` record.
This confirms the initial transfer in the Production environment used by the
TestFlight distribution build.

At 08:52–08:53 Europe/Oslo, the received `TEST TF7` record was opened on iPad,
its prize was changed from NOK 45 to NOK 50, and the change was saved using the
normal Release UI. The iPhone then displayed that same marked record with
NOK 100 stake and NOK 50 prize, without an iPhone-side edit. This confirms
bidirectional Production transport with the actual TestFlight build 1.1 (7).
No debugger test-record hook or development build was used for these mutations.

The Release archive and dSYMs are retained in Xcode's normal Archives directory:
`~/Library/Developer/Xcode/Archives/2026-11-12/Lotto 1.1 (7).xcarchive`.

After explicit user approval, the single `TEST TF7` record (NOK 100 stake,
NOK 50 prize, 2026-11-12) was deleted through the iPhone UI and its confirmation
dialog. At 08:55 Europe/Oslo the iPhone showed zero prize/net and no registered
ledger posts. The iPad, without a local deletion, also showed no registered posts.
Production create, reverse-direction edit, and deletion propagation are therefore
verified on the two physical devices using TestFlight 1.1 (7). Both devices remain
on the TestFlight version. No actual ticket was purchased and no personal ledger
post was edited or removed during this check.

This verifies the manual ledger workflow. Automatic costs from delivered rows
and automatic monetary prizes from payout tables are not implemented in build 7.

### Source update after build 7: automatic ledger
Automatic stakes/prizes now derive from the existing synced delivery log, so there
is no new CloudKit record type or automatic ledger insertion. Clearing the latest
delivery mark removes the derived expense; concurrent identical marks count once.
Public finalized payout tables are cached locally and refetched on each device.
95 tests pass on each simulator and the updated ledger screen opens/closes on both.
These source changes have not been uploaded to TestFlight or verified against
Production on physical devices. The build-7 limitation above remains accurate.

## TestFlight 1.1 (8) — completed Production checks, 2026-11-12

12 November 2026: Release archive succeeded and upload completed at 09:41
Europe/Oslo. Export used app-store-connect, internal testing only and Production
iCloud. Distribution pipeline entitlements explicitly show Production. Release
executable contains none of the DEBUG schema/test-record markers.
Archive/dSYMs: `~/Library/Developer/Xcode/Archives/2026-11-12/Lotto 1.1 (8).xcarchive`.
App Store Connect build `3a6a0ffa-e34d-477c-a36b-566f8338305b` completed processing,
OS-only encryption answer was saved, test notes were saved, and existing Internal
group (one tester) is attached. Status: Testing. No public release.
Physical pre-update backups: `~/Desktop/Lotto-sikkerhetskopier/2026-11-12-for-TestFlight-8`.
Both databases pass quick_check and each retains 1782 own Lotto rows and zero manual
ledger entries. The 52 existing positive delivery keys correspond to NOK 527 in
November standard stakes; these marks must remain unchanged during the new test.
iPhone installed version 1.1 build 8 verified with devicectl after TestFlight installation.
iPad installed version 1.1 build 8 was also verified with devicectl after TestFlight
installation. Both devices were tested with the actual distributed build, not a
local development build.

### Verified automatic calculations and bidirectional transport
- Created two own test rows on iPhone and observed both in an iPad database snapshot.
  Created the Lotto test row on iPad and observed it on iPhone.
- Used otherwise-empty week 45 of 2026, with exact test rows:
  - Lotto 7 November: 1–2–3–4–5–11–19; NOK 5 stake, NOK 50 prize (4 main matches).
  - Vikinglotto 4 November: 1–2–3–11–18–23 + 1; NOK 8 stake, NOK 90 prize (3 main matches).
  - Eurojackpot 3 November: 1–2–3–4–6 + 1–3; NOK 25 stake, NOK 135 prize (1 main + 2 extra matches).
- Marked all three delivered through the iPad weekly-report UI. Independent snapshots
  showed all three positive keys on both devices, 55 active keys rather than 52,
  and zero manual ledger entries.
- Both actual app screens displayed NOK 565 total stake, NOK 275 calculated prize,
  preliminary net NOK -290 and 17 existing pending rows. This is exactly NOK 38
  added stake and NOK 275 added prize. Neither device duplicated expenses.
- Both apps independently fetched identical six finalized draw/payout tables. The
  date-specific per-row payouts (Lotto tier 5, Vikinglotto tier 6, Eurojackpot tier 11)
  were checked from the actual local public-data caches.
- Removed all three delivery marks through the iPhone weekly-report UI. Both device
  snapshots then showed false for the test keys and the original 52 positive keys.
  iPhone showed the restored NOK 527 stake. Final iPad UI showed NOK 527 stake,
  NOK 0 calculated prize, preliminary net NOK -527 and the original 17 pending rows.

### Authorized test cleanup and preservation
The user explicitly approved deletion of these exact three temporary rows. The
two international rows were deleted through iPhone context menus and the Lotto
row through the iPad swipe/confirmation workflow. Final snapshots at 10:13
Europe/Oslo confirm all three are gone on both devices.

Every original row in Result, InternationalLotteryEntry, JackPot, LotteryLedgerEntry,
LotteryFavoriteChange and LotteryDeliveryChange was compared with pre-update
backups (all fields except the framework change counter Z_OPT): none missing or
changed. Final counts per device: 1782 Result, 2458 international entries, 794
JackPot, 0 manual ledger, 26 favorite changes. Six new immutable delivery-log
events retain the three test marks and their three reversals; the latest state is
false, so they contribute no stake/prize and prevent older test marks reappearing.
Original backup SHA256 hashes remain unchanged. Durable evidence and report:
`~/Desktop/Lotto-sikkerhetskopier/2026-11-12-for-TestFlight-8/Testresultat.txt` and
`Sluttkontroll-TestFlight-8.json`.

The iPhone briefly locked during testing and later screen sharing became
unavailable while its microphone/camera was active. Final Lotto deletion was
therefore performed on iPad; a read-only iPhone database snapshot independently
confirmed receipt without interrupting the other phone activity. No simulator
reset, account sign-out or direct device-database write was used.
No actual lottery ticket was purchased and no public App Store release was made.


## Authorized duplicate cleanup — TestFlight 1.1 (9), 12 November 2026

Full fresh store/WAL/support-file and preferences backups were taken from both
physical devices before cleanup. SHA256 manifests remain unchanged. Build 9 was
uploaded successfully and distributed to the existing Internal TestFlight group;
App Store Connect metadata confirms Production CloudKit. Installed build 9 on
Terje sin iPad 10; the iPhone remained on build 8 to receive the deletion changes.

The app maintenance preview found 896 extra Lotto copies, one Vikinglotto copy
and zero Eurojackpot copies. Following explicit user authorization, ran cleanup
ONLY on iPad at 10:43 Europe/Oslo. The app first encoded, trial-restored and read
back a full JSON backup, then deleted individual SwiftData objects in one save.
The backup is retained in iPad Documents/Lotto-backups and on Desktop.

Read-only snapshots at 10:45 confirm the same final state on both devices:
886 Lotto rows, 29 own Vikinglotto rows and 14 own Eurojackpot rows; zero duplicate
own-row keys (game, Oslo draw date, sorted main and extra numbers). All original
unique keys survive, and every retained row has unchanged original fields except
framework Z_OPT. Draw records, 794 JackPot records, 26 favorite changes, 306 delivery
events, zero manual ledger entries and 52 active delivery marks are unchanged.
Both stores pass quick_check and contain no out-of-range Lotto numbers.
Both actual screens showed NOK 527 stake, NOK 0 prize, NOK -527 preliminary net
and 17 pending rows. No direct SQLite writes or independent iPhone cleanup.

99 tests in 16 suites passed on the explicit iPad simulator before upload,
including keeper preservation, full backup reconstruction, idempotency, separate
extra pools/dates, pending-edit refusal and backup failure preventing deletion.
Durable evidence: ~/Desktop/Lotto-sikkerhetskopier/2026-11-12-for-dublettrydding/
(Testresultat.txt, Sluttkontroll.json, Manifest.json, App-backup-for-opprydding.json).
Archive: ~/Library/Developer/Xcode/Archives/2026-11-12/Lotto 1.1 (9).xcarchive.


## Duplicate prevention — TestFlight 1.1 (10), 12 November 2026

Full fresh store/support/preferences backups were retained from both physical
devices before update in ~/Desktop/Lotto-sikkerhetskopier/2026-11-12-for-TestFlight-10/.
102 tests in 17 suites passed on iPad simulator before archive; only the app build
number changed afterward. Release archive and upload succeeded; ASC shows build
10 validated, existing Internal group with one tester, and CloudKit Production.
Archive: ~/Library/Developer/Xcode/Archives/2026-11-12/Lotto 1.1 (10).xcarchive.
TestFlight app list was cached on iPad; reopening only TestFlight refreshed it.
Updated the installed app without uninstalling. Both devices report version 1.1,
bundleVersion 10 via devicectl. No schema change, account sign-out or reset.

### Six actual duplicate-rejection checks
Each was attempted on both iPhone 15 Pro and Terje sin iPad 10:
- Lotto 2026-11-14: existing [4,5,6,10,25,27,31] entered in reverse. Red duplicate
  validation message and disabled Save; no insert.
- Vikinglotto 2026-11-11: [2,9,17,26,35,44] + [3]. Pressing Save kept the form open
  with “Denne rekken er allerede lagret på denne datoen.”
- Eurojackpot 2026-11-13: [26,33,35,41,45] + [1,10]. Same correct error on Save.
All forms were cancelled after observation. No test rows, financial entries,
delivery marks or new sync writes were created. The checks used already-synced
production data, and do not represent a new bidirectional sync-write test or an
offline simultaneous-write test. Local guards cannot guarantee global uniqueness
for independent offline saves on separate devices.

### Preservation audit at 11:05 Europe/Oslo
Read-only snapshots from both devices have 886 Result, 2457 international entries
(29 own Vikinglotto and 14 own Eurojackpot), 794 JackPot, 306 delivery events,
26 favorite events and zero manual ledger entries. All six model tables exactly
match their pre-update snapshots excluding framework Z_OPT: no added, removed or
modified original record. Zero duplicate own-row keys, 52 active delivery marks;
both quick_check results OK. All original backup SHA256 hashes unchanged.
iPhone UI shows NOK 527 stake, NOK 0 calculated prize, NOK -527 preliminary net and
17 pending rows; iPad accounting inputs are identical and unchanged. No live
backup restore was performed; backup deduplication was covered by automated tests.
Durable report/evidence: Testresultat.txt, Sluttkontroll-TestFlight-10.json,
Testplan.json, Manifest.json, Automatiserte-tester.log and upload/archive logs
in the backup folder above.
