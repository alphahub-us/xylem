# Xylem

**xylem** [ zi-lem ] *noun*
1. A vascular tissue in land plants primarily responsible for the distribution
   of water and minerals taken up by the roots; also the primary component of
   wood.

AlphaHub's automated trader. Responsible for handling new signals, turning them to orders, and distributing them where needed. Stores funds and position state for logging and order creation.

# Configuration

To get started, create a file in the `config` folder called `default.config.exs` and add your configuration to it. It should look like the following:

```elixir
import Config

config :xylem,
  ledger: [data_dir: "/path/to/cubdb/folder"],
  venues: %{
    "venue:my_venue" => {
      Xylem.Venue.Alpaca,
      credentials: %{id: "alpaca_api_key_id", secret: "alpaca_api_key_secret"},
      environment: "paper" # or "live"
    },
  },
  data: %{
    "polygon" => {
      Xylem.Data.Polygon,
      credentials: %{api_key: "my_api_key"},
    },
  },
  signals: %{
    "alphahub" => {
      Xylem.Signal.AlphaHub,
      credentials: %{email: "my@email.com", password: "my_password"},
      ids: [14, 16, 17] # or any IDs you want to subscribe to
    },
  },
  bots: %{
    "my_bot" => {
      Xylem.Bot.Production,
      venue: "venue:my_venue",
      data: "polygon",
      signal: {"alphahub", id: 17}, # Xylem.Signal.IEx
      log_path: "/path/to/csv/log.csv"
    },
  }
```

At this point, all you'll need to do is run it:

```elixir
iex -S mix

# Sets funds for a bot
iex(1)> Xylem.Ledger.set_funds("my_bot", 10_000.0)
# Retrieves the history for a bot. Use `Enum.take/2` to extract the most recent N records
iex(2)> Xylem.Ledger.history("my_bot")
iex(3)> Xylem.Ledger.history("my_bot", :funds)
# this adds the events to the ledger, compounding funds available as necessary
iex(4)> events = [
...(4)> %{id: "xylem-my_bot", price: Decimal.new("123.45"), symbol: "ABC", type: :new, side: :buy, qty: 1}
...(4)> # ... more events, i.e. fill events
...(4)> ]
iex(5)> Enum.each(events, &Xylem.Orders.process_event/1)
# You can also check the positions for a particular account
iex(6)> Xylem.Venue.get_positions("venue:my_venue")
```

## Venues

### Alpaca

Connects to an Alpaca account, then listens to order updates over websockets.

### IEx

Allows you to broadcast "order updates" from the IEx console. Mostly used for testing.

## Signals

### AlphaHub

Connects to AlphaHub's WebSockets server, then listens for new signals.

### IEx

Allows you to broadcast "signals" from the IEx console. Mostly used for testing.

## Data

### Polygon

Connects to Polygon, allowing you to subscribe to tickers and receive price updates via WebSockets.

### IEx

Allows you to broadcast "data" from the IEx console. Mostly used for testing.
