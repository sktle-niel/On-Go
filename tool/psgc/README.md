# Place list: PSGC

The location field's suggestions come from the **Philippine Standard
Geographic Code (PSGC)** — the Philippine Statistics Authority's official list
of every region, province, city, municipality and barangay. The app bundles it
as `assets/places/ph_psgc.json`, read by
`lib/services/location/psgc_place_directory.dart`.

## Updating it

The PSA revises the PSGC every quarter.

1. **Download the datafile by hand** from
   <https://psa.gov.ph/classification/psgc> — the latest *PSGC Publication
   Datafile* (`.xlsx`). The PSA site sits behind bot protection, so this step
   cannot be scripted.
2. **Convert it** from the `on_go` directory:

   ```bash
   dart run tool/psgc/convert.dart path/to/PSGC-Publication-Datafile.xlsx
   ```

   It finds the sheet and its code, name and level columns by their headers,
   rebuilds each place's parent from its 10-digit code, and prints counts per
   level, skipped rows, and codes it could not attach to a parent. Read that
   summary: a new edition that changes shape shows up there first.
3. **Commit** the regenerated `assets/places/ph_psgc.json`.

The source edition is recorded inside the asset (`source`), for attribution.

## How parents are found

A 10-digit PSGC code is region (2) · province (3) · city/municipality (2) ·
barangay (3). A place's parent is the nearest prefix of its code, padded with
zeros, that names a real broader row. Two consequences worth knowing:

- Manila's barangays sit under their **sub-municipality** (Tondo I/II, …), and
  those under the City of Manila.
- **Independent cities** (highly urbanized and independent component cities)
  carry their own province digits, so by code they sit directly under their
  **region**, not the province they are geographically in.
