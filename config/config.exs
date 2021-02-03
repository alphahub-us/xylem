import Config

config :tesla, adapter: Tesla.Adapter.Gun

config :xylem,
  bots: [
    sandbox: {Xylem.Bot.Echo, venue: Xylem.Venue.IEx, signal: Xylem.Signal.IEx, market: Xylem.Market.IEx}
  ],
  ledger: [data_dir: "/Users/derek/work/quantonomy/xylem"]

import_config "#{Mix.env()}.exs"
