class CustomerChannel < ApplicationCable::Channel

  def subscribed
    stream_from "customer_#{params[:cid]}"

    ConnectedList.add(
      params[:shop], params[:cid],
      params[:uuid], params[:bd]
    )

    ActionCable.server.broadcast("customer_#{params[:cid]}", {
      subscribers: ConnectedList.get(
        params[:shop], params[:cid]
      )
    })
  end

  def unsubscribed
    ConnectedList.remove(
      params[:shop], params[:cid],
      params[:uuid], params[:bd]
    )

    ActionCable.server.broadcast("customer_#{params[:cid]}", {
      subscribers: ConnectedList.get(
        params[:shop], params[:cid]
      )
    })
  end

  def receive(payload)
    # message = Message.create(chatcid_id: payload["chatcid_id"], content: payload["message"])
    # ActionCable.server.broadcast('messages', {message: message.content, chatcid_id: message.chatcid_id})
  end

  def send_message(data)
    # your_message_mechanic
  end

end

# ActionCable.server.connections.length
# CustomerChannel.connections.length
# CustomerChannel.broadcast_to("customer_#{params[:cid]}", { cid: params[:cid] })