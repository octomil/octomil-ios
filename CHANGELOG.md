# Changelog

## Unreleased

- Added `DeviceAuthManager` for backend bootstrap token exchange, refresh, and revoke flows.
- Added runtime auth usage docs for secure short-lived device tokens.
## 1.1.0 (2026-02-26)

### Features

- add funnel event reporting to iOS SDK (#60)
- add client-side training resilience (#61)
- centralize SDK version and add release automation (#62)
- migrate iOS SDK to v2 OTLP envelope format

### Fixes

- replace PAT with GitHub App token for cross-repo dispatch (#63)
- update knope.toml to v0.22+ config format
- add all version files to knope and sync versions
- split chained && command into separate knope steps
