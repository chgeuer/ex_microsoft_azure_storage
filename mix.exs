defmodule ExMicrosoftAzureStorage.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_microsoft_azure_storage,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      dialyzer: dialyzer(),
      deps: deps()
    ]
  end

  def dialyzer do
    # Dialyzer will emit a warning when the name of the plt file is set
    # as people misused it in the past. Without setting a name caching of
    # this file is much more trickier, so we still use this functionality.
    [
      plt_file: {:no_warn, "priv/dialyzer/dialyzer.plt"},
      plt_add_apps: [:eex, :mix, :jason]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, :eex]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 1.0", runtime: false, only: :dev},
      {:hackney, "~> 1.16"},
      {:tesla, "~> 1.3"},
      {:poison, ">= 1.0.0", optional: true},
      {:jason, "~> 1.1", optional: true},
      {:sweet_xml, "~> 0.6.5"},
      {:xml_builder, "~> 2.1"},
      {:named_args, "~> 0.1.1"},
      {:timex, "~> 3.2"}
    ]
  end
end
