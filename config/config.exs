import Config

config :heartwood,
  venues: [
    ping: {Heartwood.Venue.Ping, delay: 5}
  ],
  bots: [
    {Heartwood.Bot.Echo, venue: :ping, source: Heartwood.Source.IEx, market: Heartwood.Market.IEx}
  ]
