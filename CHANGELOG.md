# Changelog

## 0.3.1 - 2026-07-17

- Validated the four required matrix variables directly from every output MAT file.
- Replaced the hard-coded successful band count with the verified MAT field count.
- Stopped a record immediately when an older two-band function is resolved by mistake.

## 0.3.0 - 2026-07-17

- Expanded every subject-phase record into separate O1-O6 and S1-S6 condition runs.
- Kept O and S epochs, matrices and figures independent throughout the pipeline.
- Added per-condition marker event counts and an explicit missing-condition status.
- Updated the single-subject example to generate both condition result sets.
- Preserved P-only legacy phase2 records as explicit fallback condition runs.

## 0.2.0 - 2026-07-17

- Expanded spectral connectivity from theta/alpha to delta, theta, alpha and beta.
- Assigned 4, 8 and 13 Hz boundary bins to one band only.
- Added four-band matrix, 2-D network and 2-by-2 fsaverage figures.
- Kept the legacy theta/alpha MAT variable names and added structured four-band outputs.
- Added batch detection of v0.1.x two-band results so they are recomputed instead of skipped.

## 0.1.3 - 2026-07-15

- Clarified that native 59-channel and 64-channel montages are preserved without padding, deletion or connectivity-matrix interpolation.
- Documented the project audit: 19 records used the 64-channel montage, 12 used the 59-channel montage, and the two layouts shared 54 channel labels.
- Added the requirement to recompute connectivity from original recordings when using a common 54-channel analysis.

## 0.1.2 - 2026-07-14

- Added per-record phase2 O/P event-prefix detection for mixed marker-table conventions.

## 0.1.1 - 2026-07-14

- Added 59-channel computation and visualization support.
- Added explicit 59-channel individual-display-only warnings to figure titles and batch CSV status.
- Kept unsupported channel counts excluded and documented that 59-node and 64-node matrices must not be pooled directly.

## 0.1.0 - 2026-07-14

- Added single-record debiased squared wPLI computation.
- Added robust import of three-column and four-column marker CSV files.
- Added automatic `O` events for phase1/phase3 and `P` events for phase2.
- Added batch progress, resume, error and non-64-channel skip reporting.
- Added `standard_1005` sensor coordinates and fsaverage surface visualization.
- Added documentation on quality-control gates and interpretation limits.
