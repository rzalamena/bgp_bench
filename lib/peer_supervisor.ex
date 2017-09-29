defmodule Bgp.PeerSupervisor do
  use Supervisor

  def start_link(peers) do
    Supervisor.start_link(__MODULE__, peers)
  end

  def init(peers) do
    Supervisor.init(peers, strategy: :one_for_one)
  end
end
