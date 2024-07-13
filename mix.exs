defmodule Streaming.MixProject do
  use Mix.Project

  def project do
    [
      app: :streaming,
      description: "Stream comprehensions",
      version: "1.0.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      source_url: "https://github.com/flambard/streaming"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    []
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/flambard/streaming"}
    ]
  end
end
