# Repository Guidelines

## Project Structure & Module Organization

BoojieFriendDots is a lightweight World of Warcraft addon. The active source lives at the repository root:

- `BoojieFriendDots.lua` contains runtime logic, settings UI, friend-status notifications, and minimap/world-map dot rendering.
- `BoojieFriendDots.toc` declares addon metadata, the saved-variable tables (`BoojieFriendDotsDB` and legacy `FriendDotsDB`), optional dependencies, and load order.
- `BoojieFriendDotsDot.tga` is the rendered marker texture.

Packaged release artifacts may lag behind the root files. Make changes to the root sources first; refresh packaged copies only when preparing a release.

## Build, Test, and Development Commands

There is no compilation step or automated test suite. Install this directory under `_retail_/Interface/AddOns/BoojieFriendDots`, start WoW, and enable the addon in the character-selection addon list.

- `/reload` reloads the UI after Lua or TOC edits.
- `/boojiefrienddots` opens the addon settings window for manual checks; `/frienddots` remains a compatibility alias.
- `zip -r BoojieFriendDots-<version>.zip BoojieFriendDots/` creates a release archive after synchronizing the staging directory.

Before packaging, update `## Version` in `BoojieFriendDots.toc` and ensure `## Interface` matches the supported WoW client build.

## Coding Style & Naming Conventions

Use four spaces for Lua indentation and keep one statement per line. Follow the existing naming patterns: `PascalCase` for local functions (`CreateDot`), `camelCase` for local state (`minimapDots`), and `UPPER_SNAKE_CASE` for constants (`UPDATE_INTERVAL`). Prefer `local` declarations, early returns, and small helpers. Use WoW API globals as documented, and guard optional APIs or integrations before calling them.

## Testing Guidelines

Validate changes in-game with Lua errors enabled. Exercise login/logout notices, class and custom colors, dot sizing, minimap rotation and shape behavior, world-map dots, saved settings across `/reload`, and behavior with and without ElvUI. Check solo, party, and raid contexts when map logic changes. Confirm the packaged addon loads from a clean directory before release.

## Commit & Pull Request Guidelines

Git history is not available in this checkout, so use concise imperative commits such as `Fix rotated minimap dot placement`. Keep unrelated changes separate. Pull requests should explain user-visible behavior, list manual test scenarios, mention the tested WoW client version, and include screenshots for settings or map-display changes. Note any TOC, saved-variable, or release-archive updates explicitly.
