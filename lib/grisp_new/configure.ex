defmodule GrispNew.Configure do
  @moduledoc false

  @defaults [
    interactive: true,
    name: "robot",
    otp_version: "29",
    jit: true,
    rust: false,
    c_nif: false,
    dest: "/path/to/SD-card",
    desc: "A GRiSP application",
    copyright_year: nil,
    author_name: nil,
    author_email: nil,
    wifi: false,
    grisp_io: false,
    grisp_io_linking: nil,
    epmd: false,
    cookie: "grisp"
  ]

  def run(options) do
    options = infer_options(options)
    supplied = options |> Keyword.keys() |> MapSet.new()
    {author_name, author_email} = default_author_and_email()

    defaults =
      @defaults
      |> Keyword.put(:author_name, author_name)
      |> Keyword.put(:author_email, author_email)

    config =
      options
      |> Keyword.merge(defaults, fn _key, supplied, _default -> supplied end)
      |> Keyword.update!(:copyright_year, &(&1 || Integer.to_string(Date.utc_today().year)))
      |> prompt(supplied)

    validate!(config)
    root = Path.expand(config[:name])
    project_exists? = File.exists?(root)

    if project_exists? do
      confirm_existing!(root, config[:interactive])
    else
      Mix.Task.reenable("new")
      Mix.Tasks.New.run([root, "--app", config[:name], "--sup"])
    end

    created =
      [
        write_elixir(Path.join(root, "mix.exs"), mix_exs(config), project_exists?),
        write_elixir(
          Path.join(root, "config/config.exs"),
          app_config(config),
          project_exists?
        ),
        write(Path.join(root, "README.md"), project_readme(config), project_exists?),
        write(Path.join(root, "LICENSE"), license(config), project_exists?)
      ] ++
        network_files(root, config, project_exists?) ++
        native_files(root, config, project_exists?) ++ rust_files(root, config, project_exists?)

    created = Enum.reject(created, &is_nil/1)

    if project_exists? do
      Mix.shell().info(
        "The project directory already existed; existing files were not overwritten. " <>
          "Review the project configuration before continuing."
      )
    end

    %{name: config[:name], root: root, config: config, created: created}
  end

  defp prompt(config, supplied) do
    if config[:interactive] do
      config
      |> ask_valid_name_unless_supplied(supplied)
      |> ask_unless_supplied(supplied, :otp_version, "Erlang/OTP version", &identity/1)
      |> ask_bool_unless_supplied(supplied, :jit, "Enable the Arm32 JIT patches?")
      |> ask_bool_unless_supplied(supplied, :rust, "Enable Rust NIF support?")
      |> ask_bool_unless_supplied(supplied, :c_nif, "Enable C NIF support?")
      |> ask_unless_supplied(supplied, :dest, "SD card path", &identity/1)
      |> prompt_features(supplied)
    else
      config
    end
  end

  defp prompt_features(config, supplied) do
    config
    |> ask_bool_unless_supplied(supplied, :wifi, "Use Wi-Fi?")
    |> prompt_wifi(supplied)
    |> ask_bool_unless_supplied(supplied, :grisp_io, "Enable GRiSP.io integration?")
    |> prompt_grisp_io(supplied)
    |> ask_bool_unless_supplied(supplied, :epmd, "Enable distributed Erlang?")
    |> prompt_epmd(supplied)
  end

  defp prompt_wifi(config, supplied) do
    if config[:wifi] do
      config
      |> ask_unless_supplied(supplied, :ssid, "Wi-Fi SSID", &identity/1)
      |> ask_unless_supplied(supplied, :psk, "Wi-Fi password", &identity/1)
    else
      config
    end
  end

  defp prompt_grisp_io(config, supplied) do
    if config[:grisp_io] do
      ask_unless_supplied(
        config,
        supplied,
        :grisp_io_linking,
        "Device linking token (leave empty to skip linking)",
        &String.trim/1
      )
    else
      config
    end
  end

  defp prompt_epmd(config, supplied) do
    if config[:epmd],
      do: ask_unless_supplied(config, supplied, :cookie, "Erlang cookie", &identity/1),
      else: config
  end

  defp ask_unless_supplied(config, supplied, key, label, normalize) do
    if MapSet.member?(supplied, key), do: config, else: ask(config, key, label, normalize)
  end

  defp ask_bool_unless_supplied(config, supplied, key, label) do
    if MapSet.member?(supplied, key), do: config, else: ask_bool(config, key, label)
  end

  defp ask_valid_name_unless_supplied(config, supplied) do
    if MapSet.member?(supplied, :name) and valid_name?(config[:name]) do
      config
    else
      ask_valid_name(config)
    end
  end

  defp ask_valid_name(config) do
    config = ask(config, :name, "App name", &identity/1)

    if valid_name?(config[:name]) do
      config
    else
      Mix.shell().error(name_error())
      ask_valid_name(Keyword.put(config, :name, nil))
    end
  end

  defp ask(config, key, label, normalize) do
    default = config[key]
    answer = Mix.shell().prompt("#{label} [#{default || ""}]: ") |> String.trim()
    Keyword.put(config, key, if(answer == "", do: default, else: normalize.(answer)))
  end

  defp ask_bool(config, key, label) do
    default = config[key]
    hint = if default, do: "Y/n", else: "y/N"
    answer = Mix.shell().prompt("#{label} [#{hint}]: ") |> String.trim() |> String.downcase()

    case answer do
      "" ->
        Keyword.put(config, key, default)

      value when value in ["y", "yes", "true"] ->
        Keyword.put(config, key, true)

      value when value in ["n", "no", "false"] ->
        Keyword.put(config, key, false)

      _ ->
        Mix.shell().error("Expected yes or no")
        ask_bool(config, key, label)
    end
  end

  defp validate!(config) do
    unless valid_name?(config[:name]), do: Mix.raise(name_error())

    if config[:grisp_io_linking] && not config[:grisp_io],
      do: Mix.raise("--grisp-io-linking requires --grisp-io")
  end

  defp network_files(root, config, preserve?) do
    base = Path.join(root, "grisp/grisp2/common/deploy/files")
    files = [write(Path.join(base, "grisp.ini.mustache"), grisp_ini(config), preserve?)]

    files =
      if config[:wifi],
        do:
          files ++
            [write(Path.join(base, "wpa_supplicant.conf"), wpa(config), preserve?)],
        else: files

    files ++ [write(Path.join(base, "erl_inetrc"), inetrc(), preserve?)]
  end

  defp write(path, contents, preserve?)

  defp write(path, contents, true) when is_binary(path) do
    if File.exists?(path), do: nil, else: write(path, contents, false)
  end

  defp write(path, contents, false) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
    path
  end

  defp write_elixir(path, contents, preserve?) do
    formatted = contents |> Code.format_string!() |> IO.iodata_to_binary()
    write(path, formatted <> "\n", preserve?)
  end

  defp mix_exs(config) do
    module = Macro.camelize(config[:name])
    native? = config[:rust] or config[:c_nif]
    cargo_config = if config[:rust], do: "\n      cargo_opts: [src_dir: \"native\"],", else: ""

    rust_environment =
      if native?,
        do: """

            if Mix.env() == :grisp do
              System.put_env("GRISP", "yes")
              System.put_env("GRISP_PLATFORM", to_string(grisp()[:platform]))
            end
        """,
        else: ""

    rust_cli =
      if native?,
        do: """

          def cli do
            [preferred_envs: ["grisp.build": :grisp, "grisp.deploy": :grisp,
                              "grisp.firmware": :grisp, "grisp.pack": :grisp]]
          end
        """,
        else: ""

    rust_deps =
      if config[:rust],
        do: """

              {:rustler, "~> 0.38.0", runtime: false},
              {:cargo, git: "https://github.com/grisp/erlang-cargo.git", branch: "cross_build_support_0_1_3", runtime: false},
        """,
        else: ""

    rust_build =
      if native?,
        do: "\n      build: [toolchain: [docker: \"grisp/grisp2-rtems-toolchain:latest\"]],",
        else: ""

    included_epmd = if config[:epmd], do: ", included_applications: [:epmd]", else: ""

    epmd_dep =
      if config[:epmd],
        do:
          "\n      {:epmd, git: \"https://github.com/erlang/epmd\", ref: \"4d1a59\", runtime: false},",
        else: ""

    grisp_io_deps =
      if config[:grisp_io],
        do:
          "\n      {:certifi, \">= 0.0.0\"},\n      {:grisp_cryptoauth, \"~> 2.6\"},\n      {:grisp_updater_grisp2, \"~> 1.0\", runtime: false},\n      {:grisp_connect, \"~> 3.0.0\"},\n      {:mix_grisp_io, \"~> 1.0\", runtime: false},",
        else: ""

    grisp_dep =
      if config[:grisp_io],
        do: "{:grisp, \"~> 2.12\", override: true}",
        else: "{:grisp, \"~> 2.12\"}"

    grisp_io_release_apps =
      if config[:grisp_io],
        do: "\n            applications: [sasl: :permanent, grisp_updater_grisp2: :load],",
        else: ""

    """
    defmodule #{module}.MixProject do
      use Mix.Project

      def project do#{rust_environment}
        [
          app: :#{config[:name]},
          version: "0.1.0",
          elixir: "~> 1.20",
          description: #{inspect(config[:desc])},
          package: [
            licenses: ["Apache-2.0"],
            maintainers: [#{inspect("#{config[:author_name]} <#{config[:author_email]}>")}]
          ],
          start_permanent: Mix.env() == :prod,
          deps: deps(),#{cargo_config}
          grisp: grisp(),
          releases: releases()
        ]
      end

    #{rust_cli}
      def application do
        [extra_applications: [:logger]#{included_epmd}, mod: {#{module}.Application, []}]
      end

      defp deps do
        [#{epmd_dep}#{grisp_io_deps}#{rust_deps}
          #{grisp_dep},
          {:mix_grisp, "~> 1.0", runtime: false}
        ]
      end

      defp grisp do
        [
          platform: :grisp2,
          otp: [version: #{inspect(config[:otp_version])}, jit: #{config[:jit]}],#{rust_build}
          deploy: [destination: #{inspect(config[:dest])}]
        ]
      end

      defp releases do
        [
          #{config[:name]}: [
            overwrite: true,
            cookie: #{inspect(config[:cookie])},#{grisp_io_release_apps}
            include_erts: &MixGrisp.Release.erts/0,
            steps: [&MixGrisp.Release.init/1, :assemble],
            include_executables_for: [],
            strip_beams: Mix.env() == :prod
          ]
        ]
      end
    end
    """
  end

  defp app_config(config) do
    connect_config =
      if config[:grisp_io_linking] do
        "config :grisp_connect,\n  device_linking_token: #{inspect(config[:grisp_io_linking])}\n"
      else
        ""
      end

    base = "import Config\n"

    if config[:grisp_io] do
      rendered =
        "config/grisp_io.exs"
        |> template()
        |> String.replace("__GRISP_CONNECT_CONFIG__", connect_config)

      base <> "\n" <> rendered
    else
      base
    end
  end

  defp grisp_ini(config) do
    wifi = if config[:wifi], do: "wlan=enable\nwpa=wpa_supplicant.conf\n", else: ""
    grisp_io = if config[:grisp_io], do: " -kernel logger_level notice", else: ""

    epmd =
      if config[:epmd],
        do: " -internal_epmd epmd_sup -sname #{config[:name]} -setcookie #{config[:cookie]}",
        else: ""

    "grisp/grisp2/common/deploy/files/grisp.ini.mustache"
    |> template()
    |> String.replace(["__EPMD_ARGS__", "__GRISP_IO_ARGS__", "__WIFI_CONFIG__"], fn
      "__EPMD_ARGS__" -> epmd
      "__GRISP_IO_ARGS__" -> grisp_io
      "__WIFI_CONFIG__" -> wifi
    end)
  end

  defp wpa(config) do
    "grisp/grisp2/common/deploy/files/wpa_supplicant.conf"
    |> template()
    |> String.replace(["__WLAN_SSID__", "__WLAN_PASSWORD__"], fn
      "__WLAN_SSID__" -> config[:ssid] || "WLAN_SSID"
      "__WLAN_PASSWORD__" -> config[:psk] || "WLAN_PASSWORD"
    end)
  end

  defp inetrc, do: template("grisp/grisp2/common/deploy/files/erl_inetrc")

  defp template(relative_path) do
    :grisp_new
    |> Application.app_dir("priv/templates")
    |> Path.join(relative_path)
    |> File.read!()
  end

  defp project_readme(config) do
    rust =
      if config[:rust],
        do: """

        The Rust example is `#{Macro.camelize(config[:name])}.RustNif.hello/0`.
        Select a Rust-enabled GRiSP2 toolchain, then run `mix grisp.build` before
        deploying. Host compilation uses the installed host Rust toolchain.

        If you use the Docker toolchain and already have an older image locally,
        update it before building:

            docker pull grisp/grisp2-rtems-toolchain:latest
        """,
        else: ""

    c_nif =
      if config[:c_nif],
        do: """

        The C NIF example is `#{Macro.camelize(config[:name])}.CNif.hello/0`.
        It is compiled into the GRiSP runtime; run `mix grisp.build` before
        deploying. The C NIF is available on the target runtime.
        """,
        else: ""

    grisp_io =
      if config[:grisp_io],
        do: """

        ## GRiSP.io

        ### Link a device

        If you did not configure a linking token, copy one from
        [GRiSP.io Devices](https://app.grisp.io/grisp-manager/devices) and run
        this once in the device shell:

            :grisp_connect.link_device("TOKEN")

        ### Publish an update

        For projects with NIFs, build the custom OTP first:

            mix grisp.build

        Build a local update package:

            mix grisp.pack

        Authenticate before using the GRiSP.io commands for the first time. Your
        credentials are saved for later commands; then upload the package:

            mix grisp-io.auth
            mix grisp-io.upload

        Upload builds the package if it does not exist locally. Use `--refresh`
        to rebuild an existing package or `--force` to replace an uploaded
        package.

        ### Deploy an update

        Use the GRiSP.io web interface to start an update from the device's
        **Device Details** page. It shows progress and lets you reboot and
        validate. You can also start an update from the command line:

            mix grisp-io.deploy --device SERIAL

        If the update requests a reboot, reboot from the web interface or
        command line. Validate after the device reconnects:

            mix grisp-io.reboot --device SERIAL
            mix grisp-io.validate --device SERIAL

        > **Warning:** Updates install to internal eMMC, not the SD card. If the
        > board booted from an SD card, eject it before rebooting after the
        > update. Otherwise the board will start the old system from the SD
        > card. If validation reports
        > `Error: device needs to be rebooted`, reboot and reconnect the device,
        > then validate again. An update that is not validated can roll back on
        > the next reboot.

        ### Manage packages

        Manage uploaded packages in the web interface, or use these commands.
        `PACKAGE` is the filename shown by `mix grisp-io.list`, not the local
        package file name:

            mix grisp-io.list
            mix grisp-io.delete PACKAGE
        """,
        else: ""

    """
    # #{config[:name]}

    #{config[:desc]}

    ## Build

        mix compile
    #{rust}
    #{c_nif}

    ## Deploy

        mix grisp.deploy --relname #{config[:name]} --relvsn 0.1.0
    #{grisp_io}
    """
  end

  defp native_files(root, config, preserve?) do
    if config[:rust] or config[:c_nif] do
      ignore_path = Path.join(root, ".gitignore")
      ignored = if File.regular?(ignore_path), do: File.read!(ignore_path), else: ""

      ignore =
        write(
          ignore_path,
          ignored <>
            "\n# GRiSP and native build artifacts\n/_grisp/\n/priv/native/\n" <>
            if(config[:rust], do: "/native/target/\n", else: ""),
          preserve?
        )

      c_nif_files =
        if config[:c_nif] do
          name = config[:name]

          [
            write_elixir(
              Path.join(root, "lib/#{name}/c_nif.ex"),
              """
              defmodule #{Macro.camelize(name)}.CNif do
                @moduledoc false

                @on_load :load_nif

                @doc false
                def load_nif do
                  case :os.type() do
                    {:unix, :rtems} -> :erlang.load_nif(:erlang.atom_to_list(__MODULE__), 0)
                    _ -> :ok
                  end
                end

                def hello, do: :erlang.nif_error(:nif_not_loaded)
              end
              """,
              preserve?
            ),
            write(
              Path.join(root, "grisp/default/common/build/nifs/#{name}_c_nif.c"),
              c_nif_source(name),
              preserve?
            )
          ]
        else
          []
        end

      [ignore | c_nif_files]
    else
      []
    end
  end

  defp c_nif_source(name) do
    """
    #ifdef __rtems__
    /* Keep the static init symbol independent of the Elixir module name. */
    #define STATIC_ERLANG_NIF_LIBNAME #{name}_c
    #endif

    #include <erl_nif.h>

    static ERL_NIF_TERM hello(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
    {
        (void)argc;
        (void)argv;
        return enif_make_string(env, "Hello from a C NIF", ERL_NIF_LATIN1);
    }

    static ErlNifFunc nif_funcs[] = {
        {"hello", 0, hello, 0}
    };

    ERL_NIF_INIT(Elixir.#{Macro.camelize(name)}.CNif, nif_funcs, NULL, NULL, NULL, NULL)
    """
  end

  defp rust_files(root, config, preserve?) do
    if config[:rust] do
      name = config[:name]
      module = Macro.camelize(name)

      [
        write_elixir(
          Path.join(root, "lib/#{name}/rust_nif.ex"),
          """
          defmodule #{module}.RustNif do
            @grisp_target System.get_env("GRISP") == "yes"

            if @grisp_target do
              @on_load :load_nif

              @doc false
              def load_nif do
                case :os.type() do
                  {:unix, :rtems} ->
                    :code.purge(__MODULE__)

                    load_path =
                      :#{name}
                      |> Application.app_dir("priv/native/#{name}_native")
                      |> to_charlist()

                    :erlang.load_nif(load_path, 0)

                  _ ->
                    :ok
                end
              end
            else
              use Rustler,
                otp_app: :#{name},
                crate: "#{name}_native",
                path: "native/#{name}_native"
            end

            @doc false
            def __mix_recompile__?, do: (System.get_env("GRISP") == "yes") != @grisp_target

            def hello, do: :erlang.nif_error(:nif_not_loaded)
          end
          """,
          preserve?
        ),
        write(
          Path.join(root, "native/Cargo.toml"),
          """
          [workspace]
          resolver = "2"
          members = ["#{name}_native"]
          """,
          preserve?
        ),
        write(
          Path.join(root, "native/#{name}_native/Cargo.toml"),
          """
          [package]
          name = "#{name}_native"
          version = "0.1.0"
          edition = "2021"

          [lib]
          crate-type = ["cdylib", "rlib"]

          [dependencies]
          rustler = { version = "0.39.0", features = ["allocator", "nif_version_2_17"] }
          """,
          preserve?
        ),
        write(
          Path.join(root, "native/#{name}_native/src/lib.rs"),
          """
          #[rustler::nif]
          fn hello() -> &'static str {
              "Hello from a Rust NIF"
          }

          rustler::init!("Elixir.#{module}.RustNif");
          """,
          preserve?
        ),
        write(
          Path.join(root, ".cargo/config.toml"),
          """
          [profile.release]
          panic = "unwind"
          opt-level = "s"      # optimize for size, not speed
          lto = true           # whole-program dead-code elimination across crates
          codegen-units = 1    # give the optimizer a single unit to work on
          strip = "symbols"    # strip symbol tables from the final artifact
          """,
          preserve?
        )
      ]
    else
      []
    end
  end

  defp license(config) do
    """
    Copyright #{config[:copyright_year]}, #{config[:author_name]} <#{config[:author_email]}>.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    """
  end

  defp identity(value), do: value

  defp default_author_and_email do
    with {:ok, name} <- command("git", ["config", "--global", "user.name"]),
         {:ok, email} <- command("git", ["config", "--global", "user.email"]) do
      {name, email}
    else
      _ -> mercurial_author_and_email()
    end
  end

  defp mercurial_author_and_email do
    with {:ok, identity} <- command("hg", ["showconfig", "ui.username"]),
         [name, email] <- Regex.run(~r/^(.+) <([^>]+)>$/, identity, capture: :all_but_first) do
      {name, email}
    else
      _ -> {"Anonymous", "anonymous@example.org"}
    end
  end

  defp command(executable, args) do
    case System.find_executable(executable) do
      nil ->
        :error

      path ->
        case System.cmd(path, args, stderr_to_stdout: true) do
          {output, 0} -> nonempty(output)
          {_output, _status} -> :error
        end
    end
  end

  defp nonempty(output) do
    case String.trim(output) do
      "" -> :error
      value -> {:ok, value}
    end
  end

  defp infer_options(options) do
    options =
      case Keyword.fetch(options, :grisp_io_linking) do
        {:ok, token} -> Keyword.put(options, :grisp_io_linking, String.trim(token))
        :error -> options
      end

    options
    |> enable_when(:wifi, Keyword.has_key?(options, :ssid) or Keyword.has_key?(options, :psk))
    |> enable_when(:grisp_io, present?(options[:grisp_io_linking]))
  end

  defp enable_when(options, key, true), do: Keyword.put(options, key, true)
  defp enable_when(options, _key, false), do: options

  defp present?(value), do: is_binary(value) and value != ""

  defp valid_name?(name) when is_binary(name), do: Regex.match?(~r/^[a-z][a-z0-9_]*$/, name)
  defp valid_name?(_name), do: false

  defp name_error,
    do: "Application name must contain lowercase letters, numbers, and underscores"

  defp confirm_existing!(root, false), do: Mix.raise("Project directory already exists: #{root}")

  defp confirm_existing!(root, true) do
    answer =
      Mix.shell().prompt(
        "Project directory #{root} already exists. Continue without overwriting files? [y/N]: "
      )
      |> String.trim()
      |> String.downcase()

    case answer do
      value when value in ["y", "yes", "true"] ->
        :ok

      value when value in ["", "n", "no", "false"] ->
        Mix.raise("Project directory already exists: #{root}")

      _ ->
        Mix.shell().error("Expected yes or no")
        confirm_existing!(root, true)
    end
  end
end
