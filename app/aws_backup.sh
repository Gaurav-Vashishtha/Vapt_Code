AWS_SQS_ACCESS_KEY=$(heroku config:get AWS_SQS_ACCESS_KEY -a cod-king)
AWS_SQS_ACCESS_SECRET=$(heroku config:get AWS_SQS_ACCESS_SECRET -a cod-king)

aws  configure set aws_access_key_id "${AWS_SQS_ACCESS_KEY}"
aws  configure set aws_secret_access_key  "${AWS_SQS_ACCESS_SECRET}"

heroku pg:backups:capture --app cod-king
OUTPUT="$(heroku pg:backups:url --app cod-king | cat)"

curl -L ${OUTPUT} -o "$(date +%d).dump"

aws s3 cp "$(date +%d).dump" "s3://codkingdata/" --region us-west-2

rm "$(date +%d).dump" 