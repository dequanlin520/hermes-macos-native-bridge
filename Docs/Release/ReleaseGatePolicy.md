# Release Gate Policy

Release-candidate gates use four states: `passed`, `failed`,
`conditionallyBlocked`, and `notApplicable`.

All functional and cleanup gates must pass. `CONDITIONAL` is allowed only when
Developer ID signing or notarization credentials are unavailable. Those gates
must be reported as `conditionallyBlocked`, not `passed`.

Any failed functional gate, failed cleanup gate, missing gate, or conditional
blocker outside Developer ID signing and notarization makes the M8-001 result
`FAIL`.
