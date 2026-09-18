import { authenticate, endpoint, HttpError, json, must } from "../_shared/http.ts";

const tables = ["user_profiles", "goal_profiles", "health_connections", "medication_support_preferences", "strength_plans", "exercises", "workouts", "workout_exercises", "workout_sets", "daily_targets", "daily_activities", "protein_entries", "weight_entries", "body_measurements", "weekly_insights", "coach_conversations", "coach_messages", "reminder_preferences", "subscription_entitlements", "consent_records", "plan_proposals", "notification_deliveries"];

Deno.serve(endpoint(async (req) => {
  const { user, client } = await authenticate(req);
  const exported: Record<string, unknown> = {
    format_version: "1.0", exported_at: new Date().toISOString(), user: { id: user.id, email: user.email },
  };
  // Privacy exports are free and include historical rows regardless of Pro.
  // Cursor pagination avoids Supabase's default 1,000-row truncation.
  let bytes = 0;
  for (const table of tables) {
    const all: unknown[] = [];
    let cursor: string | undefined;
    while (true) {
      let query = client.from(table).select("*").eq("user_id", user.id).order("id").limit(500);
      if (cursor) query = query.gt("id", cursor);
      const rows = must(await query) ?? [];
      bytes += JSON.stringify(rows).length;
      if (bytes > 20_000_000) throw new HttpError(413, "export_too_large", "Your export is larger than the interactive limit. Contact support for a complete secure export.");
      all.push(...rows);
      if (rows.length < 500) break;
      cursor = rows.at(-1).id;
    }
    exported[table] = all;
  }
  return json(exported);
}));
