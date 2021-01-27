import Config

config :heartwood,
  bots: [
    sandbox: {Heartwood.Bot.Echo, venue: Heartwood.Venue.IEx, source: Heartwood.Source.IEx, market: Heartwood.Market.IEx}
  ]

import_config "#{Mix.env()}.exs"
