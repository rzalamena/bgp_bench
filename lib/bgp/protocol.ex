defmodule Bgp.Protocol do
  @moduledoc """
  BGP wire protocol library.
  """

  @type as_number :: 0..65535
  @type router_id :: 0..4294967295

  @type mh_length :: 0..65535
  @type mh_type :: 0..255

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
  @spec message_header(mh_length, mh_type) :: binary
  def message_header(length, type), do: <<
    0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32,
    length + 19::16, type::8
  >>


  defmodule OpenOptions do
    @enforce_keys [:bgpid, :my_as]
    defstruct version: 4, holdtime: 30, bgpid: nil, my_as: nil,
              paramslen: 0, params: <<>>

    @type version :: 0..255
    @type holdtime :: 0..65535
    @type paramslen :: 0..255
    @type t :: %OpenOptions{
      version: version,
      holdtime: holdtime,
      bgpid: Bgp.Protocol.router_id,
      params: list(binary),
    }
  end

  @doc """
  OPEN Message Format:
  * Version: 1 byte unsigned integer. Current version is 4.
  * My Autonomous System: 2 bytes.
  * Hold Time: 2 byte unsigned integer. Maximum time in seconds to receive
    keepalive.
  * BGP Identifier: 4 bytes unsigned integer. Router identification.
  * Optional Parameters len: 1 byte.
  * Parameters: 0 or more bytes.
  """
  @spec encode(OpenOptions.t) :: binary
  def encode(%OpenOptions{} = open_opts) do
    params = Enum.reduce(open_opts.params, <<>>, fn(param, acc) ->
      acc <> param
    end)
    open_header = <<
      open_opts.version::8,
      open_opts.my_as::16,
      open_opts.holdtime::16,
      open_opts.bgpid::32,
      byte_size(params)::8,
      params::binary
    >>
    message_header(byte_size(open_header), 1) <> open_header
  end

  defmodule Param do
    @enforce_keys [:type, :value]
    defstruct [type: nil, value: %{}]

    @type param_type :: 0..255
    @type t :: %Param{
      type: param_type,
      value: any,
    }
  end

  @spec decode_params(binary, list(Param.t)) :: {:ok, list(Param.t)} | :error
  defp decode_params(<<type::8, length::8, data::binary>>, acc) do
    # Extract param value and point tail to next param
    <<value::bytes-size(length), tail::binary>> = data

    # Store param and go to the next one
    case type do
      2 -> # Capability (RFC 4271)
        case Bgp.Protocol.Capability.decode(data) do
          {:ok, cap} ->
            decode_params(tail, [%Param{type: type, value: cap} | acc])
          :error ->
            decode_params(tail, [%Param{type: type, value: value} | acc])
        end
      _ -> # Unhandled
        decode_params(tail, [%Param{type: type, value: value} | acc])
    end
  end
  defp decode_params(<<>>, acc), do: {:ok, acc}
  defp decode_params(_, _), do: :error
  defp decode_params(data), do: decode_params(data, [])

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
        case decode_params(params) do
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
