defmodule SkillEvals.AccessChannel do
  use Phoenix.Channel

  intercept(["document_changed"])

  def join("documents:" <> _id, _payload, socket) do
    {:ok, socket}
  end

  def handle_info({:access_changed, allowed}, socket) when is_boolean(allowed) do
    {:noreply, assign(socket, :current_access, allowed)}
  end

  def handle_out("document_changed", payload, socket) do
    if socket.assigns.current_access do
      push(socket, "document_changed", payload)
    end

    {:noreply, socket}
  end
end
