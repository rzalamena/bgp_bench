defmodule Bgp.Protocol do
  @moduledoc """
  BGP wire protocol library.
  """

  @type as_number :: 0..65535
  @type router_id :: 0..4294967295

  @doc """
  Converts an IPv4 tuple (erlang IPv4 format) to integer.
  """
  @spec ip4_to_integer(:inet.ip4_address) :: non_neg_integer
  def ip4_to_integer(ip4) do
    oct1 = elem(ip4, 0)
    oct2 = elem(ip4, 1)
    oct3 = elem(ip4, 2)
    oct4 = elem(ip4, 3)
    <<ip4::32>> = <<oct1::8, oct2::8, oct3::8, oct4::8>>
    ip4
  end

  @doc """
  BGP message header:
  * Marker: 16 bytes filled with ones.
  * Length: the length of the message including the header. Minimum value is 19
    and maximum value is 4096. No padding is allowed.
  * Type: message type. Possible values: (1) Open, (2) Update, (3) Notification
          and (4) Keepalive (RFC 2918 defines one more type code).
  """
  @type mh_length :: 0..65535
  @type mh_type :: 0..255
  @spec message_header(mh_length, mh_type) :: binary
  def message_header(length, type), do: <<
    0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32,
    length + 19::16, type::8
  >>

  @doc """
  Encodes a keepalive message.
  """
  @spec keepalive() :: binary
  def keepalive(), do: message_header(0, 4)

  @doc """
  Decode a message.
  """
  def decode(<<0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32, data::binary>>) do
    <<length::16, type::8, tail::binary>> = data

    case type do
      1 ->
        <<
          version::8,
          remote_as::16,
          holdtime::16,
          routerid::32,
          plen::8,
          params::binary
        >> = tail
        IO.write "<- Open (length #{length}, version #{version}, " <>
          "remote_as #{remote_as}, holdtime #{holdtime}, " <>
          "routerid #{routerid}, parameters length #{plen}, params: "
        case Bgp.Protocol.Open.decode_params(params) do
          {:ok, params} ->
            Enum.each(params, fn x ->
              IO.write "#{x.type}|"
            end)
            IO.write ")\n"
        end
      2 ->
        IO.puts "<- Update | Length #{length}"
      3 ->
        IO.puts "<- Notification | Length #{length}"
      4 ->
        IO.puts "<- Keepalive | Length #{length}"
      _ ->
        IO.puts "<- Unknown message type"
    end
  end
  def decode(_), do: :error
end
