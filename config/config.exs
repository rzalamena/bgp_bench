use Mix.Config

# Sample configuration
config :bgp_bench, peers: [
  %{
    neighbor: {127, 0, 0, 1},
    neighbor_port: 8179,
    remote_as: 100,
    local_address: {127, 0, 0, 1},
    local_as: 10,
    router_id: 1,
  },
]
