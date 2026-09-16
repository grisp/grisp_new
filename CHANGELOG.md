# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.1] - 2026-09-16

### Fixed

- Add the `mix_grisp_io` plugin dependency to projects generated with GRiSP.io
  integration enabled.

## [1.0.0] - 2026-09-08

### Added

- Add the standalone `mix grisp.new` project generator as a self-contained Mix
  archive with no runtime dependencies.
- Generate GRiSP releases with Ethernet, optional Wi-Fi, distributed Erlang,
  and GRiSP.io configuration.
- Support safe interactive and non-interactive project creation without
  overwriting existing files.
- Use Git or Mercurial identity settings as author defaults, with anonymous
  values when neither is configured.

[unreleased]: https://github.com/grisp/grisp_new/compare/1.0.1...HEAD
[1.0.1]: https://github.com/grisp/grisp_new/compare/1.0.0...1.0.1
[1.0.0]: https://github.com/grisp/grisp_new/releases/tag/1.0.0
