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
mix archive.install hex grisp_new 1.0.0
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
`--epmd`, and `--cookie`.

Ethernet is always configured. Wi-Fi is enabled by `--wifi` or implicitly when
an SSID or PSK is supplied. `--grisp-io-linking TOKEN` implicitly enables
GRiSP.io. In non-interactive mode, optional features are disabled unless their
options are supplied.

The generated project depends on `grisp` and `mix_grisp`. Run `mix deps.get`
inside it before using the project-local build, deploy, firmware, and package
tasks.

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
