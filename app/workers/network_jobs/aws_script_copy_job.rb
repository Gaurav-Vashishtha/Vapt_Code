require 'aws-sdk-s3'
require 'open-uri'

module NetworkJobs
    class AwsScriptCopyJob < ApplicationJob  

        def perform
            s3_bucket = 'codkingscript'  # replace with your S3 bucket name

            s3_client = Aws::S3::Client.new(region: 'us-west-2',  access_key_id: ENV.fetch("AWS_SQS_ACCESS_KEY", nil),secret_access_key: ENV.fetch("AWS_SQS_ACCESS_SECRET", nil) ) 

            script_js_file = JSON.parse(File.read(Rails.root.join('public', 'packs', 'manifest.json')))["script_react_new.js"].split('/').last
            #File.read(Rails.root.join('public', 'packs', 'js',script_js_file))
            # upload the file to S3
            File.open(Rails.root.join('public', 'packs', 'js',script_js_file), 'rb') do |file|
                resp = s3_client.put_object(
                acl: 'public-read',
                body: file,
                bucket: s3_bucket,
                key: 'script.js',
                content_type: 'text/javascript' # set the content type to 'text/javascript' or an appropriate value
                )
                SlackNotifier::CLIENT.ping(
                    text: "AWS Script Copy Job completed - #{resp}",
                  )
            end
        end
    end
end