require 'aws-sdk-s3'
require 'open-uri'
require 'zlib'
#NetworkJobs::AwsDumpCopyJob.perform_async("https://xfrtu.s3.amazonaws.com/cd99463f-3feb-43f0-b76f-4880c0035a99/2024-09-05T06%3A49%3A01Z/c9f57bd9-b6ab-4fd1-98c3-5a1e35591eb7?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAQKF7VQWOC3H3AUYK%2F20240905%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20240905T065117Z&X-Amz-Expires=3600&X-Amz-SignedHeaders=host&X-Amz-Signature=3a7f51927d496cbbb5dd8222f2c4528b5b4da3da7e491c666799eac0a37e1970")
module NetworkJobs
    class AwsDumpCopyJob  < ApplicationJob  
        sidekiq_options queue: 'db_backup', retry: false, concurrency: 1

        def perform(s3_url)
            begin
              SlackNotifyJob.perform_async(":heart:(#{Rails.env})\n  *Starting AwsDumpCopyJob #{s3_url}")
              # Set S3 bucket and client
              s3_bucket_name = 'codkingdata' # change this to your S3 bucket name
              region = 'us-west-2'
              s3 = Aws::S3::Resource.new(region: region)
              s3_client = Aws::S3::Client.new(region: 'us-west-2', access_key_id: ENV.fetch("AWS_SQS_ACCESS_KEY", nil), secret_access_key: ENV.fetch("AWS_SQS_ACCESS_SECRET", nil))
        
              # Read script_js_file from S3
              script_js_file_url = s3_url
              script_js_file_name = script_js_file_url.split('/').last
              script_js_file = open(script_js_file_url)
        
              # Set upload parameters
              file_size = script_js_file.size
              part_size = 5 * 1024 * 1024 # 5MB
              upload_id = s3_client.create_multipart_upload(bucket: s3_bucket_name, key: "#{DateTime.now.day}.dump.gz").upload_id
              parts = []
        
              # Break the file into parts and upload them to S3
              script_js_file_size = script_js_file.size
              offset = 0
              part_number = 1
              while offset < script_js_file_size
                part_size = [part_size, script_js_file_size - offset].min
                part = script_js_file.read(part_size)
                resp = s3_client.upload_part(
                  body: part,
                  bucket: s3_bucket_name,
                  key: "#{DateTime.now.day}.dump.gz",
                  part_number: part_number,
                  upload_id: upload_id
                )
                parts << {
                  part_number: part_number,
                  etag: resp.etag
                }
                offset += part_size
                part_number += 1
              end
        
              # Complete the multipart upload
              resp = s3_client.complete_multipart_upload(
                bucket: s3_bucket_name,
                key: "#{DateTime.now.day}.dump.gz",
                multipart_upload: {
                  parts: parts
                },
                upload_id: upload_id
              )
        
              # Notify after upload is complete
              SlackNotifyJob.perform_async(":heart:(#{Rails.env})\n  *Completed AwsDumpCopyJob #{resp['location']} from S3_URL #{s3_url}")
            rescue Exception => e
              SlackNotifyJob.perform_async(":rage:(#{Rails.env})\n *Error* AwsDumpCopyJob parse \n error: #{e.message} #{e.backtrace}")
            ensure
              script_js_file.close() if script_js_file
            end
          end
    end
end