defmodule SkillEvals.ChannelPublicTest do
  use ExUnit.Case, async: true

  defmodule Serializer do
    def encode!(message), do: message
  end

  test "an authorized channel delivers the original broadcast" do
    socket = %Phoenix.Socket{
      assigns: %{current_access: true},
      transport_pid: self(),
      serializer: Serializer,
      joined: true,
      topic: "documents:17"
    }

    assert {:ok, socket} = SkillEvals.AccessChannel.join(socket.topic, %{}, socket)
    payload = %{revision: 2, title: "updated"}

    assert {:noreply, _socket} =
             SkillEvals.AccessChannel.handle_out("document_changed", payload, socket)

    assert_receive %Phoenix.Socket.Message{
      topic: "documents:17",
      event: "document_changed",
      payload: ^payload
    }
  end
end
