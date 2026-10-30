module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_client
 
    def connect
      self.current_client = get_current_client
    end
 
    # the connection URL to this actioncable/channel must be
    # domain.tld?cid=the_cid
    def get_current_client
      # this is just how I get the user id, you can keep using cookies,
      # but because this key gets used for redis, I'd 
      # identify_by the user_id instead of the current_user object
      "#{request.params[:cid]}_#{request.params[:uuid]}"
    end
  end
end
