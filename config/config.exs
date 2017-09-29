use Mix.Config

# Sample configuration
config :bgp_bench, peers: [
  %{
    neighbor: {192, 168, 0, 1},
    neighbor_port: 179,
    remote_as: 100,
    local_address: {192, 168, 0, 2},
    local_as: 10,
    router_id: 1,
    prefix_start: {10, 0, 0, 1},
    prefix_amount: 500_000,
  },
]

# Disable logging to avoid wasting CPU cycles printing debug / info
config :logger, level: :warn
