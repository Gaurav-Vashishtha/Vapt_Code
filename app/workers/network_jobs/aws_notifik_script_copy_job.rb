require 'aws-sdk-s3'
require 'open-uri'

module NetworkJobs
    class AwsNotifikScriptCopyJob < ApplicationJob  

        def perform
            s3_bucket = 'codkingscript'  # replace with your S3 bucket name

            s3_client = Aws::S3::Client.new(region: 'us-west-2',  access_key_id: ENV.fetch("AWS_SQS_ACCESS_KEY", nil),secret_access_key: ENV.fetch("AWS_SQS_ACCESS_SECRET", nil) ) 

            manifest_path = Rails.root.join('public', 'notifik-svelte-app', 'manifest.json')
            
            unless File.exist?(manifest_path)
                SlackNotifier::CLIENT.ping(
                    text: "AWS Notifik Script Copy Job failed - manifest.json not found at #{manifest_path}",
                )
                return
            end

            manifest = JSON.parse(File.read(manifest_path))
            # Svelte manifest uses 'src/main.js' as the key
            entry = manifest['src/main.js']
            
            unless entry && entry['file']
                SlackNotifier::CLIENT.ping(
                    text: "AWS Notifik Script Copy Job failed - 'src/main.js' entry or 'file' key not found in manifest",
                )
                return
            end

            # Construct asset path like "/notifik-svelte-app/notifik-svelte.xxx.js"
            asset_path = "/notifik-svelte-app/#{entry['file']}"
            # Remove leading slash and construct full path relative to public directory
            file_path = Rails.root.join('public', asset_path.sub(/^\//, ''))

            unless File.exist?(file_path)
                SlackNotifier::CLIENT.ping(
                    text: "AWS Notifik Script Copy Job failed - file not found at #{file_path}",
                )
                return
            end

            # upload the file to S3
            File.open(file_path, 'rb') do |file|
                resp = s3_client.put_object(
                acl: 'public-read',
                body: file,
                bucket: s3_bucket,
                key: 'notifik.js',
                content_type: 'text/javascript' # set the content type to 'text/javascript' or an appropriate value
                )
                SlackNotifier::CLIENT.ping(
                    text: "AWS Notifik Script Copy Job completed - #{resp}",
                  )
            end
        end
    end
end

