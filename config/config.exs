import Config

config :tesla, adapter: Tesla.Adapter.Gun

config :xylem, ledger: [data_dir: "/Users/derek/work/quantonomy/xylem"]

import_config "#{Mix.env()}.exs"
