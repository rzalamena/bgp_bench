defmodule Bgp.Peer do
  @moduledoc """
  BGP peer handling library.
  """
  use GenServer

  defmodule Options do
    @enforce_keys [:neighbor, :remote_as, :local_address, :local_as, :router_id]
    defstruct neighbor: nil, neighbor_port: 179, remote_as: nil,
      local_address: nil, local_as: nil, router_id: nil

    @type t :: %Options{
      neighbor: :inet.ip4_address,
      neighbor_port: :inet.port_number,
      remote_as: Bgp.Protocol.as_number,
      local_address: :inet.ip4_address,
      local_as: Bgp.Protocol.as_number,
      router_id: Bgp.Protocol.router_id,
    }
  end

  defmodule State do
    @enforce_keys [:options]
    defstruct options: nil, socket: nil, bstate: :idle

    @type bgp_state :: :idle | :open_sent | :established
    @type t :: %State{
      options: Options.t,
      socket: port,
      bstate: bgp_state,
    }
  end

  #
  # Client-side
  #

  @doc """
  Start peer with options.
  """
  @spec start_link(Options.t) :: GenServer.on_start
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  #
  # Server-side
  #

  def init(opts) do
    conn_opts = [
      active: :once, ip: opts.local_address, mode: :binary
    ]
    case :gen_tcp.connect(opts.neighbor, opts.neighbor_port, conn_opts) do
      {:ok, socket} ->
        open_msg = Bgp.Protocol.encode(%Bgp.Protocol.OpenOptions{
          bgpid: opts.router_id,
          my_as: opts.local_as,
          params: [
            Bgp.Protocol.Capability.multiprotocol_ext(1, 1),
            Bgp.Protocol.Capability.rr_cisco(),
            Bgp.Protocol.Capability.rr(),
            Bgp.Protocol.Capability.asn4(opts.local_as),
            Bgp.Protocol.Capability.add_path(1, 1, 1),
            Bgp.Protocol.Capability.fqdn("bgpd", "local"),
            Bgp.Protocol.Capability.graceful_restart(120),
          ],
        })
        :gen_tcp.send(socket, open_msg)
        {:ok, %State{options: opts, socket: socket}}
      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    {:stop, "error: #{reason}", state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, "connection closed", state}
  end

  def handle_info({:tcp, socket, data}, state) do
    Bgp.Protocol.decode(data)

    <<paddr::32>> = <<10, 0, 100, 10>>
    update_msg = Bgp.Protocol.Update.encode(%Bgp.Protocol.Update.Route{
      pattrs: [
        Bgp.Protocol.Update.pattr_origin(0),
        Bgp.Protocol.Update.pattr_aspath(2, [state.options.local_as]),
        Bgp.Protocol.Update.pattr_nexthop(
          Bgp.Protocol.ip4_to_integer(state.options.local_address)),
      ],
      prefix: paddr,
      prefixlen: 32,
    })
    :gen_tcp.send(socket, update_msg)

    {:noreply, state}
  end
end
