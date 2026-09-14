defmodule SkillEvals.ChannelHiddenTest do
  use ExUnit.Case, async: true

  defmodule Serializer do
    def encode!(message), do: message
  end

  defp joined(allowed, id) do
    socket = %Phoenix.Socket{
      assigns: %{current_access: allowed},
      transport_pid: self(),
      serializer: Serializer,
      joined: true,
      topic: "documents:#{id}"
    }

    {:ok, socket} = SkillEvals.AccessChannel.join(socket.topic, %{}, socket)
    socket
  end

  test "revocation suppresses delivery on the same channel" do
    socket = joined(true, 17)

    assert {:noreply, socket} =
             SkillEvals.AccessChannel.handle_info({:access_changed, false}, socket)

    assert {:noreply, socket} =
             SkillEvals.AccessChannel.handle_out("document_changed", %{revision: 3}, socket)

    assert socket.topic == "documents:17"
    refute_received %Phoenix.Socket.Message{event: "document_changed"}
  end

  test "grant and regrant change delivery without replacing the socket" do
    socket = joined(false, 29)

    assert {:noreply, socket} =
             SkillEvals.AccessChannel.handle_info({:access_changed, true}, socket)

    first = %{revision: 4, content: %{nested: [1, 2]}}

    assert {:noreply, socket} =
             SkillEvals.AccessChannel.handle_out("document_changed", first, socket)

    assert_received %Phoenix.Socket.Message{
      topic: "documents:29",
      event: "document_changed",
      payload: ^first
    }

    assert {:noreply, socket} =
             SkillEvals.AccessChannel.handle_info({:access_changed, false}, socket)

    assert {:noreply, socket} =
             SkillEvals.AccessChannel.handle_out("document_changed", %{revision: 5}, socket)

    refute_received %Phoenix.Socket.Message{event: "document_changed"}

    assert {:noreply, socket} =
             SkillEvals.AccessChannel.handle_info({:access_changed, true}, socket)

    last = %{revision: 6}

    assert {:noreply, _socket} =
             SkillEvals.AccessChannel.handle_out("document_changed", last, socket)

    assert_received %Phoenix.Socket.Message{
      topic: "documents:29",
      event: "document_changed",
      payload: ^last
    }
  end
end
