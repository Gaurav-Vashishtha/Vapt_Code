namespace :pricing_jobs do
    desc "Compute charges for Orders."
    task :dynamic_pricing, [] => :environment do |t, args|
    PricingJobs::DynamicChargeJob.perform_async()
    end
end