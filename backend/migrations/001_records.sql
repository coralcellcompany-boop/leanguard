-- PostgreSQL 16+; run as the migration owner, never the API login.
-- A relational primary key partitions all typed JSONB records by tenant.
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='leanguard_service') THEN CREATE ROLE leanguard_service NOLOGIN NOBYPASSRLS; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='leanguard_user') THEN CREATE ROLE leanguard_user NOLOGIN NOBYPASSRLS; END IF;
END $$;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE TABLE IF NOT EXISTS app_records (
  collection text NOT NULL,
  owner text NOT NULL,
  id text NOT NULL CHECK(length(id) BETWEEN 1 AND 256 AND position('/' IN id)=0),
  data jsonb NOT NULL CHECK(jsonb_typeof(data)='object' AND octet_length(data::text)<=524288),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  plan_collection text GENERATED ALWAYS AS (CASE WHEN collection='workouts' AND data->>'plan_id' IS NOT NULL THEN 'strength_plans' END) STORED,
  plan_id text GENERATED ALWAYS AS (CASE WHEN collection='workouts' THEN data->>'plan_id' END) STORED,
  workout_collection text GENERATED ALWAYS AS (CASE WHEN collection='workout_exercises' THEN 'workouts' END) STORED,
  workout_id text GENERATED ALWAYS AS (CASE WHEN collection='workout_exercises' THEN data->>'workout_id' END) STORED,
  exercise_collection text GENERATED ALWAYS AS (CASE WHEN collection='workout_exercises' THEN 'exercises' END) STORED,
  exercise_id text GENERATED ALWAYS AS (CASE WHEN collection='workout_exercises' THEN data->>'exercise_id' END) STORED,
  workout_exercise_collection text GENERATED ALWAYS AS (CASE WHEN collection='workout_sets' THEN 'workout_exercises' END) STORED,
  workout_exercise_id text GENERATED ALWAYS AS (CASE WHEN collection='workout_sets' THEN data->>'workout_exercise_id' END) STORED,
  conversation_collection text GENERATED ALWAYS AS (CASE WHEN collection='coach_messages' THEN 'coach_conversations' END) STORED,
  conversation_id text GENERATED ALWAYS AS (CASE WHEN collection='coach_messages' THEN data->>'conversation_id' END) STORED,
  PRIMARY KEY(collection,owner,id),
  CHECK((owner='' AND collection IN ('account_deletions','revenuecat_events','server_jobs')) OR
    (length(owner) BETWEEN 1 AND 128 AND position('/' IN owner)=0 AND collection IN (
      'user_profiles','goal_profiles','health_connections','medication_support_preferences','strength_plans','workouts','exercises','workout_exercises','workout_sets','daily_targets','daily_activities','protein_entries','weight_entries','body_measurements','weekly_insights','coach_conversations','coach_messages','reminder_preferences','subscription_entitlements','consent_records','plan_proposals','ai_requests','device_tokens','notification_deliveries','notification_inbox','ai_usage','ai_cache','consent_state','server_state'))),
  CHECK(owner='' OR NOT(data ? 'user_id') OR data->>'user_id'=owner),
  FOREIGN KEY(plan_collection,owner,plan_id) REFERENCES app_records(collection,owner,id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(workout_collection,owner,workout_id) REFERENCES app_records(collection,owner,id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(exercise_collection,owner,exercise_id) REFERENCES app_records(collection,owner,id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(workout_exercise_collection,owner,workout_exercise_id) REFERENCES app_records(collection,owner,id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(conversation_collection,owner,conversation_id) REFERENCES app_records(collection,owner,id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX IF NOT EXISTS records_owner_collection ON app_records(owner,collection,id);
CREATE INDEX IF NOT EXISTS records_created_at ON app_records(owner,collection,(data->'created_at') DESC,id);
CREATE INDEX IF NOT EXISTS records_recorded_at ON app_records(owner,collection,(data->'recorded_at') DESC,id);
CREATE INDEX IF NOT EXISTS records_conversation ON app_records(owner,(data->'conversation_id'),(data->'created_at') DESC) WHERE collection='coach_messages';
CREATE INDEX IF NOT EXISTS records_reminders ON app_records((data->'enabled'),(data->'delivery'),owner,id) WHERE collection='reminder_preferences';
CREATE INDEX IF NOT EXISTS records_parent_plan ON app_records(plan_collection,owner,plan_id) WHERE plan_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS records_parent_workout ON app_records(workout_collection,owner,workout_id) WHERE workout_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS records_parent_exercise ON app_records(exercise_collection,owner,exercise_id) WHERE exercise_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS records_parent_workout_exercise ON app_records(workout_exercise_collection,owner,workout_exercise_id) WHERE workout_exercise_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS records_parent_conversation ON app_records(conversation_collection,owner,conversation_id) WHERE conversation_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS records_unique_logical_id ON app_records(owner,collection,(data->>'id')) WHERE data ? 'id';
CREATE UNIQUE INDEX IF NOT EXISTS records_unique_date ON app_records(owner,collection,(data->>'date')) WHERE collection IN ('daily_targets','daily_activities');
CREATE UNIQUE INDEX IF NOT EXISTS records_unique_set ON app_records(owner,(data->>'workout_exercise_id'),(data->>'set_number')) WHERE collection='workout_sets';
CREATE UNIQUE INDEX IF NOT EXISTS records_unique_health_weight ON app_records(owner,(data->>'source'),(data->>'external_id')) WHERE collection='weight_entries' AND data->>'external_id' IS NOT NULL;

CREATE OR REPLACE FUNCTION app_uid() RETURNS text LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.uid',true),'') $$;
-- Fixed search_path + no caller arguments: callers cannot inspect other tenants.
CREATE OR REPLACE FUNCTION app_account_active() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT NOT EXISTS(SELECT 1 FROM public.app_records WHERE collection='account_deletions' AND owner='' AND id=public.app_uid())
$$;
CREATE OR REPLACE FUNCTION app_has_pro() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT EXISTS(SELECT 1 FROM public.app_records WHERE collection='subscription_entitlements' AND owner=public.app_uid() AND id='pro' AND data->>'is_active'='true' AND data->>'entitlement_id'='pro' AND (data->>'access_until_ms')::numeric > extract(epoch from statement_timestamp())*1000)
$$;
REVOKE ALL ON FUNCTION app_account_active(),app_has_pro() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app_account_active(),app_has_pro() TO leanguard_user;
ALTER TABLE app_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY server_all ON app_records TO leanguard_service USING(true) WITH CHECK(true);
CREATE POLICY owner_read ON app_records FOR SELECT TO leanguard_user USING(owner=app_uid() AND app_account_active() AND collection IN (
'user_profiles','goal_profiles','health_connections','medication_support_preferences','strength_plans','workouts','exercises','workout_exercises','workout_sets','daily_targets','daily_activities','protein_entries','weight_entries','body_measurements','weekly_insights','coach_conversations','coach_messages','reminder_preferences','subscription_entitlements','consent_records','plan_proposals','ai_requests','device_tokens','notification_deliveries','notification_inbox'));
CREATE POLICY owner_insert ON app_records FOR INSERT TO leanguard_user WITH CHECK(owner=app_uid() AND app_account_active() AND collection IN (
'user_profiles','goal_profiles','health_connections','medication_support_preferences','strength_plans','workouts','exercises','workout_exercises','workout_sets','daily_targets','daily_activities','protein_entries','weight_entries','body_measurements','coach_conversations'));
CREATE POLICY owner_update ON app_records FOR UPDATE TO leanguard_user USING(owner=app_uid() AND app_account_active() AND collection IN (
'user_profiles','goal_profiles','health_connections','medication_support_preferences','strength_plans','workouts','exercises','workout_exercises','workout_sets','daily_targets','daily_activities','protein_entries','weight_entries','body_measurements','coach_conversations')) WITH CHECK(owner=app_uid() AND app_account_active());
CREATE POLICY owner_delete ON app_records FOR DELETE TO leanguard_user USING(owner=app_uid() AND app_account_active() AND collection IN (
'user_profiles','goal_profiles','health_connections','medication_support_preferences','strength_plans','workouts','exercises','workout_exercises','workout_sets','daily_targets','daily_activities','protein_entries','weight_entries','body_measurements','coach_conversations'));
GRANT USAGE ON SCHEMA public TO leanguard_service,leanguard_user;
GRANT SELECT,INSERT,UPDATE,DELETE ON app_records TO leanguard_service,leanguard_user;

CREATE OR REPLACE FUNCTION validate_client_record() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE allowed text[]; key text; old_advanced jsonb; new_advanced jsonb;
BEGIN
  IF current_user<>'leanguard_user' THEN RETURN NEW; END IF;
  IF NEW.owner<>app_uid() OR NEW.data->>'user_id' IS DISTINCT FROM NEW.owner OR NOT(NEW.data ?& ARRAY['id','user_id','created_at']) OR jsonb_typeof(NEW.data->'id')<>'string' OR length(NEW.data->>'id') NOT BETWEEN 1 AND 128 OR jsonb_typeof(NEW.data->'created_at')<>'string' THEN
    RAISE EXCEPTION 'Invalid owner or base fields' USING ERRCODE='23514';
  END IF;
  IF TG_OP='UPDATE' AND (OLD.owner<>NEW.owner OR OLD.collection<>NEW.collection OR OLD.id<>NEW.id OR OLD.data->'id' IS DISTINCT FROM NEW.data->'id' OR OLD.data->'user_id' IS DISTINCT FROM NEW.data->'user_id' OR OLD.data->'created_at' IS DISTINCT FROM NEW.data->'created_at') THEN
    RAISE EXCEPTION 'Record identity is immutable' USING ERRCODE='23514';
  END IF;
  allowed := CASE NEW.collection
   WHEN 'user_profiles' THEN ARRAY['display_name','units','time_zone','onboarding_completed','analytics_enabled','crash_reporting_enabled','coaching_tone','avatar_path']
   WHEN 'goal_profiles' THEN ARRAY['goals','goal','target_weight_kg','workouts_per_week','protein_target_g','step_target','equipment','dietary_preferences','allergies','limitations','exercise_preferences','session_minutes','training_days']
   WHEN 'health_connections' THEN ARRAY['provider','status','permissions','last_synced_at']
   WHEN 'medication_support_preferences' THEN ARRAY['enabled','clinician_supervised','appetite_level','hydration_reminders','check_ins_enabled']
   WHEN 'strength_plans' THEN ARRAY['name','description','is_active','version','source','schedule']
   WHEN 'exercises' THEN ARRAY['name','muscle_group','equipment','instructions','image_url']
   WHEN 'workouts' THEN ARRAY['plan_id','name','status','scheduled_date','started_at','completed_at','duration_seconds','notes','health_exported_at']
   WHEN 'workout_exercises' THEN ARRAY['workout_id','exercise_id','position','target_sets','target_reps','target_weight_kg','rest_seconds','status']
   WHEN 'workout_sets' THEN ARRAY['workout_exercise_id','set_number','reps','weight_kg','completed','completed_at','rpe']
   WHEN 'daily_targets' THEN ARRAY['date','steps','protein_g']
   WHEN 'daily_activities' THEN ARRAY['date','steps','active_energy_kcal','readiness_score','energy_level','source']
   WHEN 'protein_entries' THEN ARRAY['recorded_at','name','protein_g','meal_type']
   WHEN 'weight_entries' THEN ARRAY['recorded_at','weight_kg','source','external_id']
   WHEN 'body_measurements' THEN ARRAY['recorded_at','waist_cm','chest_cm','hips_cm','arm_cm','thigh_cm']
   WHEN 'coach_conversations' THEN ARRAY['title'] ELSE ARRAY[]::text[] END;
  FOR key IN SELECT jsonb_object_keys(NEW.data) LOOP
    IF NOT(key=ANY(allowed||ARRAY['id','user_id','created_at','updated_at'])) THEN RAISE EXCEPTION 'Unrecognized record field' USING ERRCODE='23514'; END IF;
  END LOOP;
  IF NEW.collection IN ('user_profiles','goal_profiles','medication_support_preferences') THEN
    IF NEW.id<>NEW.owner THEN RAISE EXCEPTION 'Invalid singleton key' USING ERRCODE='23514'; END IF;
  ELSIF NEW.collection='health_connections' THEN
    IF NEW.id IS DISTINCT FROM NEW.data->>'provider' OR NEW.id NOT IN ('apple_health','health_connect') THEN RAISE EXCEPTION 'Invalid health key' USING ERRCODE='23514'; END IF;
  ELSIF NEW.collection IN ('daily_targets','daily_activities') THEN
    IF NEW.id IS DISTINCT FROM NEW.data->>'date' OR NEW.id !~ '^\d{4}-\d{2}-\d{2}$' THEN RAISE EXCEPTION 'Invalid date key' USING ERRCODE='23514'; END IF;
  ELSIF NEW.collection='workout_sets' THEN
    IF NEW.id IS DISTINCT FROM (NEW.data->>'workout_exercise_id')||'_'||(NEW.data->>'set_number') THEN RAISE EXCEPTION 'Invalid set key' USING ERRCODE='23514'; END IF;
  ELSIF NEW.id IS DISTINCT FROM NEW.data->>'id' THEN RAISE EXCEPTION 'Invalid record key' USING ERRCODE='23514';
  END IF;
  IF NEW.collection IN ('daily_activities','weight_entries') AND NEW.data->>'source' IS DISTINCT FROM 'manual' THEN RAISE EXCEPTION 'Health import requires server endpoint' USING ERRCODE='23514'; END IF;
  IF NEW.collection='weight_entries' AND (NEW.data->>'external_id' IS NOT NULL OR NOT((NEW.data->>'weight_kg')::numeric BETWEEN 20 AND 500)) THEN RAISE EXCEPTION 'Invalid manual weight' USING ERRCODE='23514'; END IF;
  IF NEW.collection='medication_support_preferences' AND NEW.data->>'enabled'='true' AND NEW.data->>'clinician_supervised' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Clinician supervision required' USING ERRCODE='23514'; END IF;
  IF NEW.collection='strength_plans' AND NEW.data->>'source' IS DISTINCT FROM 'starter' AND NOT app_has_pro() AND (TG_OP='INSERT' OR (NEW.data-ARRAY['is_active','updated_at']) IS DISTINCT FROM (OLD.data-ARRAY['is_active','updated_at'])) THEN RAISE EXCEPTION 'Manual plan requires Pro' USING ERRCODE='23514'; END IF;
  IF NEW.collection='body_measurements' THEN
    new_advanced:=jsonb_build_array(NEW.data->'chest_cm',NEW.data->'hips_cm',NEW.data->'arm_cm',NEW.data->'thigh_cm');
    old_advanced:=CASE WHEN TG_OP='UPDATE' THEN jsonb_build_array(OLD.data->'chest_cm',OLD.data->'hips_cm',OLD.data->'arm_cm',OLD.data->'thigh_cm') ELSE '[null,null,null,null]'::jsonb END;
    IF new_advanced <> '[null,null,null,null]'::jsonb AND new_advanced IS DISTINCT FROM old_advanced AND NOT app_has_pro() THEN RAISE EXCEPTION 'Advanced measurements require Pro' USING ERRCODE='23514'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER validate_client_record BEFORE INSERT OR UPDATE ON app_records FOR EACH ROW EXECUTE FUNCTION validate_client_record();
