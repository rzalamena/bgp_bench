defmodule BgpBench do
  @moduledoc """
  Documentation for BgpBench.
  """
  use Application

  def start(_type, _args) do
    Bgp.Peer.start_link(%Bgp.Peer.Options{
      neighbor: {127, 0, 0, 1}, neighbor_port: 8179, remote_as: 100,
      local_address: {127, 0, 0, 1}, local_as: 10, router_id: 1,
    })
  end
end
