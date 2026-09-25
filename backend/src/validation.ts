/** Client-write policy. Trusted coaching, billing and consent use separate
 * authenticated handlers; neither a client field nor a URL selects an owner. */
export type RecordData = Record<string, unknown>;
export class RecordValidationError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message); }
}
export const readableTables = new Set([
  'user_profiles', 'goal_profiles', 'health_connections', 'medication_support_preferences',
  'strength_plans', 'exercises', 'workouts', 'workout_exercises', 'workout_sets',
  'daily_targets', 'daily_activities', 'protein_entries', 'weight_entries',
  'body_measurements', 'weekly_insights', 'coach_conversations', 'coach_messages',
  'reminder_preferences', 'subscription_entitlements', 'consent_records', 'plan_proposals',
  'notification_deliveries',
]);
const fields: Record<string, string[]> = Object.fromEntries(Object.entries({
  user_profiles: 'display_name units time_zone onboarding_completed analytics_enabled crash_reporting_enabled coaching_tone avatar_path',
  goal_profiles: 'goals goal target_weight_kg workouts_per_week protein_target_g step_target equipment dietary_preferences allergies limitations exercise_preferences session_minutes training_days',
  health_connections: 'provider status permissions last_synced_at',
  medication_support_preferences: 'enabled clinician_supervised appetite_level hydration_reminders check_ins_enabled',
  strength_plans: 'name description is_active version source schedule',
  exercises: 'name muscle_group equipment instructions image_url',
  workouts: 'plan_id name status scheduled_date started_at completed_at duration_seconds notes health_exported_at',
  workout_exercises: 'workout_id exercise_id position target_sets target_reps target_weight_kg rest_seconds status',
  workout_sets: 'workout_exercise_id set_number reps weight_kg completed completed_at rpe',
  daily_targets: 'date steps protein_g',
  daily_activities: 'date steps active_energy_kcal readiness_score energy_level source',
  protein_entries: 'recorded_at name protein_g meal_type',
  weight_entries: 'recorded_at weight_kg source external_id',
  body_measurements: 'recorded_at waist_cm chest_cm hips_cm arm_cm thigh_cm',
  coach_conversations: 'title',
}).map(([key, value]) => [key, value.split(' ')]));
const singletons = new Set(['user_profiles', 'goal_profiles', 'medication_support_preferences']);
const advancedMeasurements = ['chest_cm', 'hips_cm', 'arm_cm', 'thigh_cm'];
export function assertRecord(condition: unknown, message = 'Check the record fields and values.'): asserts condition {
  if (!condition) throw new RecordValidationError(400, 'invalid_record', message);
}
export const safeId = (value: unknown): value is string => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const text = (value: unknown, max: number): value is string => typeof value === 'string' && value.length <= max;
const number = (value: unknown, min: number, max: number): value is number => typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
const integer = (value: unknown, min: number, max: number) => number(value, min, max) && Number.isInteger(value);
const optional = (row: RecordData, key: string, validate: (value: unknown) => boolean) => row[key] == null || validate(row[key]);
const stringList = (value: unknown, max: number, maxText = 500) => Array.isArray(value) && value.length <= max && value.every(item => text(item, maxText));
const timestamp = (value: unknown) => text(value, 35) && /^\d{4}-\d{2}-\d{2}T/.test(value) && Number.isFinite(Date.parse(value));
const date = (value: unknown) => text(value, 10) && /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
const oneOf = (value: unknown, values: unknown[]) => values.includes(value);
const timeZone = (value: unknown) => {
  if (!text(value, 100) || !value.length) return false;
  try { new Intl.DateTimeFormat('en', { timeZone: value }).format(); return true; } catch { return false; }
};

export function canonicalDocumentId(table: string, row: RecordData): string {
  if (singletons.has(table)) return String(row.user_id);
  if (table === 'health_connections') return String(row.provider);
  if (table === 'daily_activities' || table === 'daily_targets') return String(row.date);
  if (table === 'workout_sets') return `${row.workout_exercise_id}_${row.set_number}`;
  return String(row.id);
}

export type ValidationContext = {
  uid: string; pro: boolean; existing?: RecordData;
  parentExists: (table: string, id: string) => Promise<boolean>;
  hasExistingPlan?: () => Promise<boolean>;
};

export async function validateClientWrite(table: string, documentId: string, input: unknown, context: ValidationContext): Promise<RecordData> {
  const allowed = fields[table];
  if (!allowed) throw new RecordValidationError(403, 'server_owned', 'This record can only be changed through its authorized action.');
  assertRecord(input && typeof input === 'object' && !Array.isArray(input));
  const row = input as RecordData;
  const keys = new Set(['id', 'user_id', 'created_at', 'updated_at', ...allowed]);
  assertRecord(Object.keys(row).every(key => keys.has(key)), 'Unknown record fields are not accepted.');
  assertRecord(row.user_id === context.uid, 'Record ownership cannot be changed.');
  assertRecord(safeId(row.id) && timestamp(row.created_at) && optional(row, 'updated_at', timestamp));
  assertRecord(safeId(documentId) && canonicalDocumentId(table, row) === documentId, 'The record ID does not match its path.');
  const existing = context.existing;
  if (existing) {
    assertRecord(existing.user_id === context.uid);
    assertRecord(row.id === existing.id && row.created_at === existing.created_at, 'Record identity and creation time are immutable.');
  }
  const num = (key: string, min: number, max: number) => number(row[key], min, max);
  const optNum = (key: string, min: number, max: number) => optional(row, key, value => number(value, min, max));
  const txt = (key: string, max: number) => text(row[key], max);
  const optText = (key: string, max: number) => optional(row, key, value => text(value, max));
  const list = (key: string, max: number, maxText = 500) => optional(row, key, value => stringList(value, max, maxText));
  const bool = (key: string, defaultValue?: boolean) => typeof (row[key] ?? defaultValue) === 'boolean';
  const parent = async (tableName: string, key: string) => {
    assertRecord(safeId(row[key]));
    assertRecord(await context.parentExists(tableName, row[key]), 'A related record is unavailable in your account.');
  };
  switch (table) {
    case 'user_profiles':
      assertRecord(txt('display_name', 80) && oneOf(row.units, ['metric', 'imperial']) && timeZone(row.time_zone) && bool('onboarding_completed') && bool('analytics_enabled', false) && bool('crash_reporting_enabled', false) && optText('coaching_tone', 40) && optText('avatar_path', 500));
      break;
    case 'goal_profiles':
      assertRecord(oneOf(row.goal, ['lose_weight', 'build_strength', 'stay_consistent']) && optNum('target_weight_kg', 20, 500) && integer(row.workouts_per_week, 1, 7) && num('protein_target_g', 20, 400) && integer(row.step_target, 500, 50000) && list('goals', 10) && list('equipment', 30) && list('dietary_preferences', 30) && list('allergies', 30) && list('limitations', 30) && list('exercise_preferences', 30) && optNum('session_minutes', 10, 180));
      assertRecord(optional(row, 'training_days', value => Array.isArray(value) && value.length <= 7 && value.every(day => integer(day, 1, 7))));
      break;
    case 'health_connections':
      assertRecord(oneOf(row.provider, ['apple_health', 'health_connect']) && oneOf(row.status, ['connected', 'disconnected', 'denied', 'unavailable']) && list('permissions', 10) && optional(row, 'last_synced_at', timestamp));
      break;
    case 'medication_support_preferences':
      assertRecord(bool('enabled') && bool('clinician_supervised') && (!row.enabled || row.clinician_supervised) && oneOf(row.appetite_level, ['normal', 'low', 'very_low']) && bool('hydration_reminders', false) && bool('check_ins_enabled', false));
      break;
    case 'strength_plans': {
      assertRecord(txt('name', 120) && txt('description', 2000) && bool('is_active') && integer(row.version, 1, 1000000) && oneOf(row.source, ['starter', 'manual', ...(existing?.source === 'coach' ? ['coach'] : [])]) && optional(row, 'schedule', value => Array.isArray(value) && value.length <= 7 && value.every(item => integer(item, 1, 7) || (item && typeof item === 'object' && !Array.isArray(item) && Object.keys(item).every(key => ['day', 'name'].includes(key)) && integer(item.day, 1, 7) && (item.name === undefined || text(item.name, 120))))));
      const deactivatingOnly = existing && row.is_active === false && Object.keys(row).every(key => ['is_active', 'updated_at'].includes(key) || JSON.stringify(row[key]) === JSON.stringify(existing[key]));
      if (!context.pro && !deactivatingOnly) {
        const fixedDays = [1, 4, 6], fixedNames = ['Lower body', 'Upper body', 'Full body'];
        const canonicalSchedule = Array.isArray(row.schedule) && row.schedule.length === 3 && row.schedule.every((item, index) => typeof item === 'number' ? item === fixedDays[index] : item && typeof item === 'object' && item.day === fixedDays[index] && (item.name === undefined || item.name === fixedNames[index]));
        const canonical = row.source === 'starter' && row.name === 'Muscle retention foundation' && row.description === 'A starter 3-day plan. Start with a comfortable load and controlled repetitions.' && canonicalSchedule;
        if (!canonical) throw new RecordValidationError(403, 'pro_required', 'Free includes the starter three-day plan. Personalized plans require Pro.');
        if (!existing && (row.version !== 1 || !context.hasExistingPlan || await context.hasExistingPlan())) throw new RecordValidationError(403, 'pro_required', 'Free includes one starter plan.');
        if (existing) assertRecord(row.version === existing.version || row.version === Number(existing.version) + 1, 'Plan versions must advance one step at a time.');
      }
      break;
    }
    case 'exercises':
      assertRecord(txt('name', 120) && txt('muscle_group', 60) && txt('equipment', 100) && list('instructions', 30, 2000) && optText('image_url', 2000));
      break;
    case 'workouts':
      if (row.plan_id != null) await parent('strength_plans', 'plan_id');
      assertRecord(txt('name', 120) && oneOf(row.status, ['planned', 'in_progress', 'completed', 'skipped']) && optNum('duration_seconds', 0, 86400) && optText('notes', 2000) && optional(row, 'scheduled_date', date) && optional(row, 'started_at', timestamp) && optional(row, 'completed_at', timestamp) && optional(row, 'health_exported_at', timestamp));
      break;
    case 'workout_exercises':
      await parent('workouts', 'workout_id'); await parent('exercises', 'exercise_id');
      assertRecord(integer(row.position, 0, 100) && integer(row.target_sets, 1, 20) && integer(row.target_reps, 1, 100) && num('target_weight_kg', 0, 1000) && num('rest_seconds', 0, 600) && oneOf(row.status, ['planned', 'completed', 'skipped']));
      break;
    case 'workout_sets':
      await parent('workout_exercises', 'workout_exercise_id');
      assertRecord(integer(row.set_number, 1, 100) && integer(row.reps, 0, 200) && num('weight_kg', 0, 1000) && bool('completed') && optional(row, 'completed_at', timestamp) && optNum('rpe', 1, 10));
      break;
    case 'daily_targets':
      assertRecord(date(row.date) && integer(row.steps, 500, 50000) && num('protein_g', 20, 400));
      break;
    case 'daily_activities':
      assertRecord(date(row.date) && row.source === 'manual' && integer(row.steps, 0, 200000) && optNum('active_energy_kcal', 0, 50000) && optNum('readiness_score', 0, 100) && optNum('energy_level', 1, 5));
      break;
    case 'protein_entries':
      assertRecord(timestamp(row.recorded_at) && txt('name', 200) && num('protein_g', 0.1, 300) && oneOf(row.meal_type, ['breakfast', 'lunch', 'dinner', 'snack']));
      break;
    case 'weight_entries':
      assertRecord(timestamp(row.recorded_at) && num('weight_kg', 20, 500) && row.source === 'manual' && row.external_id == null);
      break;
    case 'body_measurements': {
      const noAdvanced = advancedMeasurements.every(key => row[key] == null);
      const unchanged = existing && advancedMeasurements.every(key => (row[key] ?? null) === (existing[key] ?? null));
      assertRecord(timestamp(row.recorded_at) && optNum('waist_cm', 20, 300) && optNum('chest_cm', 20, 300) && optNum('hips_cm', 20, 300) && optNum('arm_cm', 10, 100) && optNum('thigh_cm', 10, 150) && (row.waist_cm != null || !noAdvanced));
      if (!context.pro && !noAdvanced && !unchanged) throw new RecordValidationError(403, 'pro_required', 'Advanced measurements require Pro. Your existing records remain available.');
      break;
    }
    case 'coach_conversations': assertRecord(txt('title', 120)); break;
    default: throw new RecordValidationError(403, 'server_owned', 'This record is read-only.');
  }
  return row;
}

export function pagination(query: Record<string, unknown>): { offset: number; limit: number } {
  const parse = (value: unknown, fallback: number, maximum: number) => {
    if (value === undefined) return fallback;
    assertRecord(typeof value === 'string' && /^\d+$/.test(value), 'Use non-negative integer pagination values.');
    const n = Number(value); assertRecord(Number.isSafeInteger(n) && n <= maximum, 'Pagination is out of range.'); return n;
  };
  const offset = parse(query.offset, 0, 1000000), limit = parse(query.limit, 500, 500);
  assertRecord(limit >= 1, 'Page size must be between 1 and 500.');
  return { offset, limit };
}
