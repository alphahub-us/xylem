import Config

config :tesla, adapter: Tesla.Adapter.Gun

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n"

import_config "#{Mix.env()}.exs"
