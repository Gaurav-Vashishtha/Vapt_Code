# NetworkJobs::SenderIdRegisterationJob.perform_async

module NetworkJobs
    class SenderIdRegisterationJob < ApplicationJob  

        def perform

            Shop.where(country_code:'AE').each do|shop|
                WelcomeMailer.free_sender_id_ae(shop.id).deliver_later
            end
        end
    end
end