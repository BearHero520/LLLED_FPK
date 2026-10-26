# Compatibility catalog and support policy

The source of truth for the released model catalog is
[models/compatibility.json](../models/compatibility.json). The runtime source
of truth remains the model plugin itself: it is the only component that can
expose a hardware operation.

## Support levels

| Level | Meaning | Hardware commands |
| --- | --- | --- |
| profile-only | A stable model ID and candidate DMI names are registered. No controller map is trusted. | None |
| read-only | The controller identity and every reported value are validated on physical hardware. | Status only |
| reverse-engineered | Command flow and registers are recovered from vendor firmware, but physical validation is pending. | Only with --force --apply and model-specific safeguards |
| supported | Each exposed write path, its safe range, and rollback/exit behavior are validated. | Only declared capabilities |
| blocked | A known conflict, firmware regression, or safety issue prevents use. | None |

A profile must not be upgraded based on shared CPU, chassis, number of bays, or
another model's register map.

## Catalog fields

Every model record must contain:

| Field | Requirement |
| --- | --- |
| id | Stable lowercase plugin ID; never reuse an ID for a different board. |
| plugin | Expected installed shared-object name. |
| dmi_product_names | Exact strings reported by /sys/class/dmi/id/product_name; no fuzzy matching. |
| support_level | One of the levels above. |
| capabilities | State each feature as verified, reverse-engineered, unverified, or blocked. |
| controller | Chip/transport identity, or unverified. |
| evidence | Firmware version, test date, method, and the scope validated. |
| known_conflicts | Vendor modules, kernel versions, or other software that must not run concurrently. |

Unknown facts must be recorded as unverified, not inferred.

## Adding a model safely

1. Add a profile-only plugin and a catalog entry first.
2. Capture its exact DMI string, board revision, firmware version, and stock
   driver/module behavior.
3. Add read-only operations and compare them against the stock firmware on a
   physical device.
4. Enable one write operation at a time. Keep --apply protection and define
   safe ranges in code.
5. Record a test result in the catalog and submit the completed
   [new-model intake template](NEW_MODEL_TEMPLATE.md).

## Compatibility rules

- DMI detection selects a plugin; it does not prove a control map is safe.
- --force is an investigator override, not a compatibility guarantee.
- --force never bypasses exact DMI matching, controller identity, or the
  active vendor-driver conflict check.
- A firmware upgrade can lower a model's support level if it changes the
  controller map or vendor driver behavior.
- A reverse-engineered write path must retain the --force requirement until
  its physical validation record is added to the catalog.
- An incompatible vendor module must be detected before direct I/O. The
  catalog must name the conflict and the remediation.
- Keep firmware-specific differences in separate plugins or explicitly
  versioned code paths; do not silently branch on an assumed register layout.
