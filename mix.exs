defmodule GrispNew.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/grisp/grisp_new"

  def project do
    [
      app: :grisp_new,
      version: @version,
      elixir: "~> 1.20",
      description: "Standalone Mix archive for creating GRiSP projects.",
      deps: deps(),
      package: package(),
      source_url: @source_url
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ~w(lib priv .formatter.exs mix.exs README* CHANGELOG* LICENSE*),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      }
    ]
  end
end
