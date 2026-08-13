defmodule MillionSend.MixProject do
  use Mix.Project

  def project do
    [
      app: :millionsend,
      version: "0.0.1",
      elixir: "~> 1.14",
      description:
        "Official Elixir SDK for MillionSend — the open-source email platform. Under active development; this release reserves the package name.",
      package: package(),
      deps: []
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/MillionSend/millionsend-elixir"}
    ]
  end
end
