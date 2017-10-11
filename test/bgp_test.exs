defmodule BgpTest do
  use ExUnit.Case

  test "encode/decode open messages" do
    msg = Bgp.Protocol.Open.encode(%Bgp.Protocol.Open.Options{
      version: 4,
      my_as: 100,
      holdtime: 180,
      bgpid: 1,
      params: [
        Bgp.Protocol.Capability.multiprotocol_ext(1, 1),
        Bgp.Protocol.Capability.asn4(100),
      ]
    })

    # Assert that the message is successfully decoded
    assert {:ok, msglist, tail} = Bgp.Protocol.decode(msg)
    # Assert that there were no excess data
    assert tail == <<>>

    [msg|tail] = msglist
    # Assert that we have only one message after decoding OPEN
    assert tail == []
    # Assert that the message is what we encoded
    assert msg.type == :open
    assert msg.value == %Bgp.Protocol.Open.Message{
      version: 4,
      remote_as: 100,
      holdtime: 180,
      routerid: 1,
      params: [
        %Bgp.Protocol.Open.Param{
          type: 2,
          value: %Bgp.Protocol.Capability.Capability{
            type: 65,
            value: <<100::32>>
          }
        },
        %Bgp.Protocol.Open.Param{
          type: 2,
          value: %Bgp.Protocol.Capability.Capability{
            type: 1,
            value: <<1::16, 1::16>>
          }
        },
      ]
    }
  end
end
