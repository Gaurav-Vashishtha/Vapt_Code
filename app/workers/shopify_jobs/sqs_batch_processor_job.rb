# app/jobs/shopify_jobs/sqs_batch_processor_job.rb
module ShopifyJobs
    class SqsBatchProcessorJob < ApplicationJob
      sidekiq_options queue: 'default', retry: 3
  
      def perform
          # Process all messages in the queue
          SqsMessageProcessorService.new.process_all_messages
      end
    end
  end