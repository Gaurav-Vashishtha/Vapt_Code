# WS3 → `config/schedule.yml` (owner: WS8 / integrator)

Source: ARCHITECTURE.md B.8 (retention) and K.3. Append this entry to `config/schedule.yml`
(same format as the existing sidekiq-cron entries):

```yaml
cod_form_session_purge_job:
  cron: "40 3 * * *"
  class: "CodForm::SessionPurgeJob"
  queue: low
```

What it does (daily, 03:40 UTC, `app/workers/cod_form/session_purge_job.rb`):

- deletes `cod_form_sessions` rows older than 90 days (batches of 5 000);
- on `ordered` rows older than 30 days blanks `contact`, `address`, `custom_fields`, `ip`,
  `user_agent`, `phone_normalized`, `email_normalized` and removes the stored order response
  (`quote_snapshot.order_response`, which holds the buyer email for the web pixel);
- marks never-used open sessions (no contact, token expired more than a day ago) as `expired`.

The job takes no arguments and is idempotent.
