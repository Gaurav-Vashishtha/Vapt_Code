module AdminJobs
  class RedirectsCleanupJob < ApplicationJob
    sidekiq_options queue: 'administration'

    def perform
      redirects = Redirect.where('created_at<?', DateTime.now-30.day)
      redirects.each do |redirect|

      end
      #Make a call to shopify to delete...

      
    end

  end
end