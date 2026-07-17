# Changelog

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
