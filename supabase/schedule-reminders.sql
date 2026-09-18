-- Run AFTER deploying the function and creating these Vault secrets in the
-- Supabase dashboard: leanguard_project_url, leanguard_reminder_cron_secret.
-- The cron secret must exactly match REMINDER_CRON_SECRET in Edge secrets.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

select cron.schedule('leanguard-reminders','* * * * *',$$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name='leanguard_project_url') || '/functions/v1/dispatch-reminders',
    headers := jsonb_build_object('Content-Type','application/json',
      'x-cron-secret',(select decrypted_secret from vault.decrypted_secrets where name='leanguard_reminder_cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 50000
  );
$$);
