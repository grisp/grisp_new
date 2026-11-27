defmodule GrispNew.ConfigureTest do
  use ExUnit.Case, async: false

  defmodule HostRustler do
    defmacro __using__(_opts) do
      quote do
        @on_load :host_load
        def host_load, do: {:error, :unexpected_host_nif_load}
      end
    end
  end

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    root =
      System.tmp_dir!()
      |> Path.join("grisp_new_configure_#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    on_exit(fn ->
      File.rm_rf!(root)
      Mix.shell(previous_shell)
    end)

    {:ok, root: root}
  end

  test "does not prompt again for values supplied on the command line", %{root: root} do
    File.cd!(root, fn ->
      GrispNew.Configure.run(
        interactive: true,
        name: "demo",
        otp_version: "29",
        jit: true,
        rust: false,
        c_nif: false,
        dest: "/tmp/grisp",
        wifi: false,
        grisp_io: false,
        epmd: false
      )
    end)

    refute_received {:mix_shell, :prompt, _message}
  end

  test "accepts true and false as explicit jit values", %{root: root} do
    File.cd!(root, fn ->
      Mix.Task.reenable("grisp.new")

      Mix.Tasks.Grisp.New.run([
        "--no-interactive",
        "--name",
        "jit_enabled",
        "--jit",
        "true"
      ])

      Mix.Task.reenable("grisp.new")

      Mix.Tasks.Grisp.New.run([
        "--no-interactive",
        "--name",
        "jit_disabled",
        "--jit",
        "false"
      ])
    end)

    assert File.read!(Path.join(root, "jit_enabled/mix.exs")) =~ "jit: true"
    assert File.read!(Path.join(root, "jit_disabled/mix.exs")) =~ "jit: false"
  end

  test "re-prompts until a valid application name is entered", %{root: root} do
    send(self(), {:mix_shell_input, :prompt, ""})
    send(self(), {:mix_shell_input, :prompt, "valid_name"})

    result =
      File.cd!(root, fn ->
        GrispNew.Configure.run(
          interactive: true,
          name: "",
          otp_version: "29",
          jit: true,
          rust: false,
          c_nif: false,
          dest: "/tmp/grisp",
          wifi: false,
          grisp_io: false,
          epmd: false
        )
      end)

    assert result.name == "valid_name"
    assert_received {:mix_shell, :error, [_message]}
  end

  test "re-prompts for invalid yes or no answers", %{root: root} do
    send(self(), {:mix_shell_input, :prompt, "maybe"})
    send(self(), {:mix_shell_input, :prompt, "n"})

    File.cd!(root, fn ->
      GrispNew.Configure.run(
        interactive: true,
        name: "demo",
        otp_version: "29",
        jit: true,
        rust: false,
        c_nif: false,
        dest: "/tmp/grisp",
        grisp_io: false,
        epmd: false
      )
    end)

    assert_received {:mix_shell, :error, ["Expected yes or no"]}
  end

  test "preserves files when the user accepts an existing project directory", %{root: root} do
    project = Path.join(root, "demo")
    File.mkdir_p!(project)
    File.write!(Path.join(project, "mix.exs"), "# existing project\n")
    send(self(), {:mix_shell_input, :prompt, "y"})

    File.cd!(root, fn ->
      GrispNew.Configure.run(
        interactive: true,
        name: "demo",
        otp_version: "29",
        jit: true,
        rust: false,
        c_nif: false,
        dest: "/tmp/grisp",
        wifi: false,
        grisp_io: false,
        epmd: false
      )
    end)

    assert File.read!(Path.join(project, "mix.exs")) == "# existing project\n"
    assert File.exists?(Path.join(project, "config/config.exs"))
  end

  test "generates an Ethernet configuration without enabling WLAN", %{root: root} do
    result =
      File.cd!(root, fn ->
        GrispNew.Configure.run(
          interactive: false,
          name: "demo"
        )
      end)

    grisp_ini =
      File.read!(Path.join(result.root, "grisp/grisp2/common/deploy/files/grisp.ini.mustache"))

    refute grisp_ini =~ "wlan=enable"
    assert grisp_ini =~ ~s(-kernel inetrc "./erl_inetrc")
    assert grisp_ini =~ "-user elixir -extra +iex --no-halt"
    assert grisp_ini =~ "on_exit = reboot"
    assert grisp_ini =~ "on_crash = reboot"
    refute File.exists?(Path.join(result.root, "native/Cargo.toml"))
    refute File.read!(Path.join(result.root, "mix.exs")) =~ ":cargo"
  end

  test "generates Rust sources and build-only dependencies when requested", %{root: root} do
    File.cd!(root, fn ->
      Mix.Task.reenable("grisp.new")
      Mix.Tasks.Grisp.New.run(["--no-interactive", "--name", "rust_demo", "--rust"])
    end)

    project = Path.join(root, "rust_demo")
    mix = File.read!(Path.join(project, "mix.exs"))
    assert mix =~ "https://github.com/grisp/erlang-cargo.git"
    assert mix =~ ~s(branch: "cross_build_support_0_1_3")
    assert mix =~ ~s({:rustler, "~> 0.38.0", runtime: false})
    assert mix =~ ~s({:grisp, "~> 2.13"})
    assert mix =~ ~s({:mix_grisp, ">= 1.2.1 and < 2.0.0", runtime: false})
    assert mix =~ ~s(cargo_opts: [src_dir: "native"])
    assert mix =~ "build: [toolchain:"
    assert mix =~ "preferred_envs:"
    assert mix =~ ~s|System.put_env("GRISP", "yes")|
    assert {:ok, _} = Code.string_to_quoted(mix)

    assert File.read!(Path.join(project, "native/rust_demo_native/src/lib.rs")) =~
             ~s|rustler::init!("Elixir.RustDemo.RustNif")|

    wrapper = File.read!(Path.join(project, "lib/rust_demo/rust_nif.ex"))
    assert wrapper =~ "defmodule RustDemo.RustNif"
    assert wrapper =~ "if @grisp_target do"
    assert wrapper =~ "{:unix, :rtems}"
    refute File.exists?(Path.join(project, "lib/rust_demo/native.ex"))
    assert File.read!(Path.join(project, "native/Cargo.toml")) =~ "rust_demo_native"
  end

  test "loads the C NIF directly in Elixir with the static init symbol expected by OTP", %{
    root: root
  } do
    File.cd!(root, fn ->
      Mix.Task.reenable("grisp.new")
      Mix.Tasks.Grisp.New.run(["--no-interactive", "--name", "c_demo", "--c-nif"])
    end)

    project = Path.join(root, "c_demo")
    source = File.read!(Path.join(project, "grisp/default/common/build/nifs/c_demo_c_nif.c"))
    assert source =~ "#define STATIC_ERLANG_NIF_LIBNAME c_demo_c"
    assert source =~ "ERL_NIF_INIT(Elixir.CDemo.CNif,"
    refute File.exists?(Path.join(project, "src/c_demo_c_nif.erl"))
    wrapper = File.read!(Path.join(project, "lib/c_demo/c_nif.ex"))
    assert wrapper =~ "defmodule CDemo.CNif"
    assert wrapper =~ "@on_load :load_nif"
    assert wrapper =~ ":erlang.load_nif(:erlang.atom_to_list(__MODULE__), 0)"
    assert {:ok, _} = Code.string_to_quoted(wrapper)
  end

  test "target Rust wrapper cold-loads on the host without loading a shared NIF", %{root: root} do
    previous = System.get_env("GRISP")
    module = ColdLoadDemo.RustNif

    try do
      result =
        File.cd!(root, fn ->
          GrispNew.Configure.run(interactive: false, name: "cold_load_demo", rust: true)
        end)

      source = Path.join(result.root, "lib/cold_load_demo/rust_nif.ex")

      wrapper =
        source
        |> File.read!()
        |> String.replace("use Rustler,", "use GrispNew.ConfigureTest.HostRustler,")

      System.put_env("GRISP", "yes")
      [{^module, beam}] = Code.compile_string(wrapper, source)
      assert apply(module, :load_nif, []) == :ok
      refute apply(module, :__mix_recompile__?, [])
      :code.purge(module)
      :code.delete(module)
      assert {:module, ^module} = :code.load_binary(module, String.to_charlist(source), beam)
      refute apply(module, :__mix_recompile__?, [])
      System.delete_env("GRISP")
      assert apply(module, :__mix_recompile__?, [])
    after
      :code.purge(module)
      :code.delete(module)

      if previous,
        do: System.put_env("GRISP", previous),
        else: System.delete_env("GRISP")
    end
  end

  test "enables Wi-Fi when either credential is supplied", %{root: root} do
    for {name, option} <- [{"ssid_only", {:ssid, "test-network"}}, {"psk_only", {:psk, "secret"}}] do
      result =
        File.cd!(root, fn ->
          GrispNew.Configure.run([{:interactive, false}, {:name, name}, option])
        end)

      files = Path.join(result.root, "grisp/grisp2/common/deploy/files")
      grisp_ini = File.read!(Path.join(files, "grisp.ini.mustache"))

      assert grisp_ini =~ "wlan=enable"
      assert grisp_ini =~ "wpa=wpa_supplicant.conf"
      assert File.exists?(Path.join(files, "wpa_supplicant.conf"))
    end
  end

  test "preserves quoted text in generated Mix configuration", %{root: root} do
    description = ~S(GRiSP "Demo" customer's \lab #{literal}) <> " café"
    destination = ~S(/media/GRiSP "card"\test)
    author = ~S(Sébastien "Merle")

    result =
      File.cd!(root, fn ->
        GrispNew.Configure.run(
          interactive: false,
          name: "quoted_demo",
          desc: description,
          dest: destination,
          author_name: author,
          author_email: "author@example.org"
        )
      end)

    config = Mix.Project.in_project(:quoted_demo, result.root, fn _ -> Mix.Project.config() end)
    assert config[:description] == description
    assert config[:grisp][:deploy][:destination] == destination
    assert config[:package][:maintainers] == ["#{author} <author@example.org>"]
  end

  test "preserves Wi-Fi quotes and backslashes as WPA data", %{root: root} do
    ssid = ~S("__WLAN_PASSWORD__"\#{network})
    password = ~S(pa"ss\word#{literal}__WLAN_SSID__)

    result =
      File.cd!(root, fn ->
        GrispNew.Configure.run(
          interactive: false,
          name: "wifi_demo",
          ssid: ssid,
          psk: password,
          epmd: true,
          cookie: "__WIFI_CONFIG__"
        )
      end)

    wpa =
      File.read!(Path.join(result.root, "grisp/grisp2/common/deploy/files/wpa_supplicant.conf"))

    assert wpa =~ ~s(ssid="#{ssid}")
    assert wpa =~ ~s(psk="#{password}")

    ini =
      File.read!(Path.join(result.root, "grisp/grisp2/common/deploy/files/grisp.ini.mustache"))

    assert ini =~ "-setcookie __WIFI_CONFIG__"
  end

  test "generates a bootable GRiSP.io release configuration", %{root: root} do
    File.cd!(root, fn ->
      Mix.Task.reenable("grisp.new")

      Mix.Tasks.Grisp.New.run([
        "--no-interactive",
        "--name",
        "connected",
        "--ssid",
        "test-network",
        "--psk",
        "secret",
        "--grisp-io-linking",
        "link-token"
      ])
    end)

    project = Path.join(root, "connected")
    mix_exs = File.read!(Path.join(project, "mix.exs"))
    config_exs = File.read!(Path.join(project, "config/config.exs"))
    files = Path.join(project, "grisp/grisp2/common/deploy/files")
    grisp_ini = File.read!(Path.join(files, "grisp.ini.mustache"))

    for dependency <- ~w(certifi grisp_cryptoauth grisp_updater_grisp2 grisp_connect mix_grisp_io) do
      assert mix_exs =~ ":#{dependency}"
    end

    assert mix_exs =~ ~s({:grisp_cryptoauth, "~> 2.6"})
    assert mix_exs =~ ~s({:grisp_connect, "~> 3.0.0"})
    assert mix_exs =~ ~s({:grisp_updater_grisp2, "~> 1.0", runtime: false})
    assert mix_exs =~ ~s({:mix_grisp_io, "~> 1.0", runtime: false})
    assert mix_exs =~ ~s({:grisp, "~> 2.13", override: true})
    assert mix_exs =~ "applications: [sasl: :permanent, grisp_updater_grisp2: :load]"

    assert config_exs =~ "config :grisp_keychain"
    assert config_exs =~ "config :grisp_cryptoauth"
    assert config_exs =~ "config :grisp_connect"
    assert config_exs =~ ~s(device_linking_token: "link-token")
    assert config_exs =~ "config :grisp_updater"
    refute config_exs =~ "config :kernel"
    refute config_exs =~ "logger: []"
    assert {:ok, _quoted} = Code.string_to_quoted(config_exs)

    assert grisp_ini =~ "wlan=enable"
    assert grisp_ini =~ "wpa=wpa_supplicant.conf"
    assert grisp_ini =~ "-kernel logger_level notice"
    refute grisp_ini =~ "__EPMD_ARGS__"
    refute grisp_ini =~ "__GRISP_IO_ARGS__"
    refute grisp_ini =~ "__WIFI_CONFIG__"
    refute config_exs =~ "__GRISP_CONNECT_CONFIG__"
    assert File.exists?(Path.join(files, "wpa_supplicant.conf"))
    assert File.exists?(Path.join(files, "erl_inetrc"))
  end
end
