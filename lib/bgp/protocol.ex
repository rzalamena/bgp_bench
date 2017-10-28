defmodule Bgp.Protocol do
  @moduledoc """
  BGP wire protocol library.
  """
  defmodule Message do
    @moduledoc """
    Protocol messages retrieval format. This is what is returned when
    BGP messages are decoded.
    """
    @enforce_keys [:type, :value]
    defstruct [type: nil, value: nil]

    @type message_type :: :open | :update | :notification | :keepalive
    @type t :: %Message{
      type: message_type,
      value: any,
    }
  end

  @type as_number :: 0..65_535
  @type router_id :: 0..4_294_967_295

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
  Gets the next IP address tuple.
  """
  @spec ip4_next(:inet.ip4_address, non_neg_integer) :: :inet.ip4_address
  def ip4_next(ip4, step \\ 1) do
    nip4 = ip4_to_integer(ip4) + step
    <<oct1::8, oct2::8, oct3::8, oct4::8>> = <<nip4::32>>
    {oct1, oct2, oct3, oct4}
  end

  @doc """
  BGP message header:
  * Marker: 16 bytes filled with ones.
  * Length: the length of the message including the header. Minimum value is 19
    and maximum value is 4096. No padding is allowed.
  * Type: message type. Possible values: (1) Open, (2) Update, (3) Notification
          and (4) Keepalive (RFC 2918 defines one more type code).
  """
  @type mh_length :: 0..65_535
  @type mh_type :: 0..255
  @spec message_header(mh_length, mh_type) :: binary
  def message_header(length, type), do: <<
    0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32,
    length + 19::16, type::8
  >>

  @doc """
  Encodes a notification message.

  `code` possible values:
  (1) message header error, (2) OPEN message error, (3) UPDATE message error,
  (4) Holdtime expired, (5) finite state machine error and (6) Cease.
  """
  @spec notification(non_neg_integer, non_neg_integer, binary) :: binary
  def notification(code, subcode, data \\ <<>>) do
    notification = <<
      code::8,
      subcode::8,
      data::binary
    >>
    message_header(byte_size(notification), 3) <> notification
  end

  @doc """
  Encodes a keepalive message.
  """
  @spec keepalive() :: binary
  def keepalive(), do: message_header(0, 4)

  defp decode(<<
    0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32,
    length::16, type::8, data::binary
  >>, acc) when length >= 19 and byte_size(data) >= (length - 19) do
    taillen = length - 19
    <<value::bytes-size(taillen), tail::binary>> = data

    case type do
      1 ->
        case Bgp.Protocol.Open.decode(value) do
          {:ok, openmsg} ->
            decode(tail, [openmsg | acc])
          {:error, notificationmsg} ->
            {:error, notificationmsg}
        end
      2 ->
        # TODO decode update messages value
        decode(tail, [%Message{type: :update, value: <<>>} | acc])
      3 ->
        # TODO decode notification messages value
        decode(tail, [%Message{type: :notification, value: <<>>} | acc])
      4 ->
        decode(tail, [%Message{type: :keepalive, value: <<>>} | acc])
      _ ->
        {:error, notification(1, 3)}
    end
  end

  # Invalid message length
  defp decode(<<
    0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32, 0xFFFFFFFF::32,
    length::16, _::8, _::binary
  >>, _) when length < 19, do: {:error, notification(1, 2)}

  # End of valid data or insufficient data
  defp decode(<<data::binary>>, acc), do: {:ok, acc, data}

  @doc """
  Decode a message.

  Returns `{:ok, message_list, data_tail}` on success with zero or more messages
  parsed, otherwise `{:error, notification_message}` on unrecoverable error.
  """
  @spec decode(binary) :: {:ok, list(Message.t), binary} | {:error, binary}
  def decode(<<data::binary>>), do: decode(data, [])
end
