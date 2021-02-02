import Config

config :tesla, adapter: Tesla.Adapter.Gun

config :heartwood,
  bots: [
    sandbox: {Heartwood.Bot.Echo, venue: Heartwood.Venue.IEx, source: Heartwood.Source.IEx, market: Heartwood.Market.IEx}
  ],
  ledger: [data_dir: "/Users/derek/work/quantonomy/heartwood"]

import_config "#{Mix.env()}.exs"
