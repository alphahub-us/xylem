import Config

config :tesla, adapter: Tesla.Adapter.Gun

config :xylem, ledger: [data_dir: "/Users/derek/work/quantonomy/xylem"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n"

import_config "#{Mix.env()}.exs"
