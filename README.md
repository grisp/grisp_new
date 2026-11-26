# grisp_new

`grisp_new` provides the standalone `mix grisp.new` task for creating
GRiSP-ready Elixir projects. Its archive has no runtime dependencies and is
intended to be installed globally.

## Installation

Install the latest release from Hex:

```console
mix archive.install hex grisp_new
```

Install a specific release with:

```console
mix archive.install hex grisp_new
```

## Usage

Create a supervised Mix application interactively:

```console
mix grisp.new
```

For non-interactive use:

```console
mix grisp.new --no-interactive --name robot \
  --ssid mywifi --psk mysecret
```

Important options are `--name`, `--otp-version`, `--jit true|false`, `--dest`,
`--wifi`, `--ssid`, `--psk`, `--grisp-io`, `--grisp-io-linking TOKEN`,
`--epmd`, `--rust`, `--c-nif`, and `--cookie`.

Ethernet is always configured. Wi-Fi is enabled by `--wifi` or implicitly when
an SSID or PSK is supplied. `--grisp-io-linking TOKEN` implicitly enables
GRiSP.io. In non-interactive mode, optional features are disabled unless their
options are supplied.

The generated project depends on `grisp` and `mix_grisp`. Run `mix deps.get`
inside it before using the project-local build, deploy, firmware, and package
tasks.

To generate a Rust NIF example:

```console
mix grisp.new --no-interactive --name rust_robot --rust
```

This adds Rustler, the GRiSP Cargo fork as a build-time dependency, a Rust
workspace and an Elixir loader. Select a Rust-enabled GRiSP2 toolchain, then run
`mix grisp.build` before deploying. `mix compile` builds the NIF for the host
using its installed Rust toolchain. The GRiSP build uses the SDK's Rust compiler
and patched Rust dependencies. Projects generated without `--rust` do not need
Cargo or Rustler.

The Rust example is `<App>.RustNif.hello/0`, in `lib/<app>/rust_nif.ex`.

To generate a C NIF example, add `--c-nif`. It places the C source in the GRiSP
build overlay and exposes it as `<App>.CNif.hello/0`. C NIF code is statically
linked into the target runtime and is available on GRiSP, not on the host.
The loader is defined directly in `lib/<app>/c_nif.ex` using `@on_load`.

If the target directory exists, interactive mode asks for confirmation and
creates only missing files. Non-interactive mode refuses to modify an existing
directory.

## Development

Build and install an archive from this checkout:

```console
MIX_ENV=prod mix do archive.build + archive.install
```

Run the test suite with:

```console
mix test
```
