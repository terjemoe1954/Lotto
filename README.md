# Lotto

A simple SwiftUI app for registering lottery rows, storing draws, and viewing stats/predictions.

## Features
- Register your own rows (7 numbers) with date.
- Register winning rows (8 numbers) with week number.
- List views for both rows and draws with delete actions.
- Statistics: frequency, average interval, and next expected date.
- Prediction: suggests numbers based on historical intervals and a selected date.
- Print/PDF reports with headers and page numbers.

## Data and storage
- Uses SwiftData to store `JackPot` and `Result`.
- On first launch, loads `lotto.json` into the database if it is empty.

## Printing
- Reports render as multiple pages when needed.
- Each page has a header (title + date) and footer with page numbers.

## Settings
- Dark/light mode.
- Prediction tolerance (number of days of deviation).

## Running
1. Open the project in Xcode.
2. Select the scheme and run on simulator/device.

## Notes
- Predictions are statistical and provide no guarantee of winning.

## Vikinglotto and Eurojackpot (trial)
- The top selector switches between Lotto and the two international games.
- Existing Lotto models and screens are retained. The new games use the additive
  `InternationalLotteryEntry` SwiftData model, with separate main and extra pools.
- Bundled history: 201 Vikinglotto and 402 Eurojackpot draws, from January 2023
  through November 6, 2026. Every scheduled draw through the last available draw
  was checked for coverage, number counts, ranges, uniqueness and weekday.
- Source: Norsk Tipping's public `LotteryGameInfo/v2/api/results` service;
  Vikinglotto uses `vikinglotto`, Eurojackpot uses `eurojackpot all` (URL encoded).
  Only finalized results are imported. These public website endpoints have no
  availability guarantee; failures are shown and previously saved data remains usable.
- Update fetches from seven days before the latest saved draw in 28-day windows.
  Each window is saved independently and existing dates are checked for conflicts.
- New games support manual draws, own rows, match counts, separate pool frequency
  statistics, suggestions and sharing individual rows. They do not calculate
  prize amounts or submit tickets. Suggestions do not improve winning odds.
- Full backup includes all games; draws-only backup includes draws from all games.
  Old backups remain readable and preserve international entries when restored.
- History before 2023 and printing are not included for the new games in this trial.
  Their statistics and suggestion workflows are described below.
- Test on a backed-up device before release. The new CloudKit record type must be
  included when deploying the CloudKit production schema for a distributed build.

## International game statistics
- Main numbers and Viking/star numbers are calculated separately from stored draws.
- Periods: full history, current calendar year, trailing 12 calendar months and the
  latest 100 stored draws. Future draws, own rows, invalid records and repeated
  copies of the same draw date are excluded.
- Each number shows count, percentage of selected draws, last occurrence, elapsed
  calendar days, stored draws since last occurrence, mean interval in days and
  draws, and longest completed interval. Two occurrences are required for intervals.
- The shared Lotto setting can omit one longest interval (by calendar days) from
  both means when at least two intervals exist. Counts and maxima remain unchanged.
- A top-ten frequency chart, four sort orders, expandable details and text sharing
  are available. Missing scheduled draws between the selected endpoints are shown;
  draw-based intervals always count stored results rather than inventing missing data.
- Calendar calculations use Europe/Oslo, including daylight-saving transitions.
  These are historical summaries, not forecasts of future winning numbers.

## International game suggestions
- History, Mixed and Random modes generate 1–20 unique rows with independently
  sampled main and Viking/star pools. History and Mixed use bounded weights from
  historical frequency, the same ISO week in earlier week-years, and interval
  candidates within the shared Lotto tolerance. Random uses equal weights.
- Historical intervals are descriptive: none of these modes improves winning odds.
  With no history, all modes fall back to equal weights.
- Only valid results earlier than the selected draw, and no later than today, are
  considered. Results on the selected date cannot leak into historical suggestions.
- Dates advance to the next valid draw day. Suggestions can be shared, saved one
  at a time or in bulk, or opened in the manual editor with their date and both pools.
  Saving skips duplicate rows for the same game and date and validates the whole batch
  before writing. Saving a row does not submit a ticket to Norsk Tipping.

## Weekly report and delivery checklist
- The shared Weekly report button above the game views combines saved own rows from
  all three games. Choose ISO week-year and week number (Monday–Sunday, Europe/Oslo),
  enable the desired games and mark individual rows or select all. Both Eurojackpot
  draw days are included, while equal week numbers from other years stay separate.
- Export selection and registration marks are separate. Registration marks turn rows
  gray; the hide switch removes them from the visible list and current export. They
  can be shown and unmarked again. New week/game filters select all visible rows;
  explicitly clearing the selection disables both exports.
- Registration marks persist locally and are included in full backups. Old backups
  without marks preserve the current marks. Lotto marks interoperate with the older
  Mine rekker “Overført” marks. Marking a row does not submit it to Norsk Tipping.
- Excel exports native .xlsx with typed numbers/dates, separate main/Viking/star
  columns, week-year, week number, registration status, a frozen header and filter.
  The small OOXML/ZIP exporter runs entirely on the device without new dependencies.
- Paper uses a paginated A4 PDF with repeating column headings, registration boxes
  and page numbers. Preview the selected rows, then tap Print for the iOS print dialog.
  Rows are never split across pages. Export files use a week/year filename.

## iCloud delivery status
- The existing CloudKit container and automatic private-sync configuration are retained.
  A new additive SwiftData model stores immutable registered/unregistered changes.
- Both the Weekly report and older Lotto Mine rekker screen read the same resolved
  status. An unmark remains as a change, so older synced positive marks do not win.
- Legacy local marks are imported idempotently using an old baseline timestamp.
  Current backups include the latest state, including false values. Restoring a full
  backup creates new changes; older backups without mark data preserve current marks.
- Settings includes an account-access check, not a claim that sync has completed.
- Actual server synchronization and the Production schema still need verification
  with signed builds on two devices. See [iCloud testing](ICLOUD_TESTING.md).

## Offline and backup verification
- Settings → Backup → Check backup file trial-restores a selected JSON backup into
  an isolated local database and reports own-row, draw and registered-row counts.
  The check never replaces live data and works without CloudKit access.
- Full restore validates draw data, readable dates and status records before replacement;
  pending individual deletes/inserts are committed together. Draws-only import
  leaves own rows, delivery changes and preferences untouched.
- The same backup-store implementation is used by Settings and integration tests,
  including full-file round trip, reopening a restored disk store, legacy formats,
  invalid-data rejection and offline persistence. See ICLOUD_TESTING.md for which
  physical two-device checks have actually been completed.

### Historical own-row compatibility
Backup check and full restore preserve old own Lotto rows exactly even when they
contain an out-of-range number, a repeated number or a non-Saturday date. These
are reported as warnings with row/date/numbers instead of blocking recovery.
New row entry still enforces all Lotto rules. Unreadable dates and malformed
files remain errors. The backup-check error label now correctly says check,
rather than incorrectly reporting that a restore failed.

## Favorite numbers
- Optional first-launch setup allows 0–7 Lotto, 0–6 Vikinglotto or 0–5 Eurojackpot
  main favorites, plus optional Viking/star favorites in their separate pools.
- The setup begins with a prominent statement that the app does not increase
  winning chances. It can be skipped, and Favorites remains available above the
  game selector. The first-setup prompt is device-local; the preferences themselves
  use a new additive private-CloudKit model.
- Enabled favorites are included in every generated suggestion in all modes.
  Remaining numbers follow the selected mode. Manual own-row forms prefill the
  active favorites; transferred suggestions retain their full existing row.
  Winning-draw entry never prefills personal favorites.
- Batches are limited by the number of possible unique rows. Filling all slots
  fixes a single row. A bounded completion fallback prevents biased sampling
  from yielding duplicate rows or an unnecessarily short batch.
- Favorites can be disabled without forgetting the selected numbers, or cleared.
  Changes resolve per game by date and a stable change-ID tie break. No global
  cross-game transfer silently changes number ranges.
- Full backups include favorites. Older backups lacking that field preserve
  current preferences, and draws-only exports/imports exclude preferences.

## Privacy and review preparation
Settings contains Personvern og kontakt. Hosting-ready policy: docs/privacy.html.
Draft metadata: APP_STORE_REVIEW.md. Remaining distribution checks:
RELEASE_READINESS.md. These files have not been published or submitted.
