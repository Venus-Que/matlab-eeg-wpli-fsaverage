# MATLAB EEG wPLI with fsaverage visualization

This repository provides a MATLAB/FieldTrip pilot pipeline for computing
59- or 64-channel sensor-space debiased squared weighted phase-lag index and rendering
the strongest connections on the FreeSurfer fsaverage cortical surface.

## Scope

- Continuous MNE FIF input with a marker CSV fallback.
- Three-column and four-column marker-table support.
- Event-locked 0.5-2.5 s epochs.
- Peak-to-peak trial rejection and deterministic trial selection.
- DPSS multitaper Fourier estimates.
- Theta (4-8 Hz) and alpha (8-13 Hz) matrices.
- Matrix, 2-D network and fsaverage projection figures.
- Batch scan, pilot, resume and failure reporting.
- 59-channel results are generated with an explicit individual-display-only warning; unsupported channel counts are skipped.

## Important limitation

The fsaverage figure is a visualization of sensor-space connectivity projected
onto a cortical surface. It is not source-space connectivity. The current
six-trial setting is project-specific pilot configuration and must not be
treated as a validated diagnostic protocol.

The 59-channel and 64-channel matrices have different node sets and must not be
pooled or compared edge by edge without first defining a common montage.
The pipeline preserves the EEG channels present in each FIF file: it does not
pad 59 channels to 64, reduce 64 channels to 59, or fill connectivity matrices
with zeros or interpolated edges. In the audited project dataset, 19 records
used the 64-channel montage and 12 used the 59-channel montage; their label
intersection contained 54 EEG channels. A joint common-node analysis therefore
requires extracting those 54 channels from the original recordings and
recomputing 54-by-54 connectivity matrices.

See the [Chinese README](README.md) and documentation under `docs/` for the
complete workflow, data layout and interpretation boundaries.

## License

MIT. FieldTrip, MATLAB, FreeSurfer fsaverage and participant data are not
redistributed by this repository.
