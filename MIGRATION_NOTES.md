# Migration Notes - Private Gems to Public Gems

This file is a historical note for the repository migration from private-gem assumptions to the current public-gem setup.

## Status

The migration described here has already been completed in this repository. The old checklist is intentionally not treated as current setup guidance.

## What changed

1. Removed repository access entries from `.devcontainer/devcontainer.json`.
2. Updated template-reference docs such as `CODESPACES.md` and `PRIVATE_GEMS.md`.
3. Updated Copilot instructions to point at local documentation.
4. Replaced the old `makeup_artist` dependency with `flat_pack` in the dummy app.

## Current source of truth

Use these files for current behavior instead of the old migration checklist:

1. `README.md` for gem installation, configuration, provider integration, picker usage, and validation.
2. `lib/generators/recording_studio_attachable/install/templates/INSTALL.md` for the generated host-app install checklist.
3. `test/dummy/README.md` for what the dummy app is intended to validate.

## FlatPack note

FlatPack is now the default UI system for both the engine and the dummy app. If you are reviewing older commits or template-history docs, treat any `makeup_artist` references as superseded historical context.
