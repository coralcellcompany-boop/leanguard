import type { Snapshot } from "./coaching.js";
import { trends } from "./metrics.js";
import { list } from "./platform.js";

export async function snapshotFor(userId: string): Promise<Snapshot> {
  const now = new Date();
  const start = new Date(now.getTime() - 28 * 86400000).toISOString();
  const fields: Record<string,string[]> = {
    goal_profiles: ["protein_target_g","step_target","workouts_per_week","equipment","dietary_preferences","allergies","limitations","exercise_preferences","session_minutes","training_days"],
    user_profiles: ["units","coaching_tone","time_zone"], medication_support_preferences: ["enabled","appetite_level","clinician_supervised"],
    weight_entries: ["recorded_at","weight_kg"], workouts: ["id","plan_id","status","created_at","completed_at"],
    workout_sets: ["workout_exercise_id","weight_kg","reps","rpe","completed","completed_at","created_at"], protein_entries: ["recorded_at","protein_g"],
    daily_activities: ["date","steps","readiness_score","energy_level"], strength_plans: ["id","version","is_active"],
    workout_exercises: ["id","exercise_id","workout_id","target_weight_kg","target_sets","target_reps"], exercises: ["id","name"],
  };
  const results = await Promise.all(Object.entries(fields).map(([table, selected]) => list(userId, table, selected)));
  const [goals, profiles, meds, allWeights, allWorkouts, allSets, allProtein, allActivity, allPlans, workoutExercises, library] = results;
  // Bound untrusted free text before placing it in a paid model context. Lists
  // retain only primitive preferences; no nested blobs or profile identifiers.
  const bounded = (value: unknown): unknown => typeof value === "string" ? value.slice(0, 160) : Array.isArray(value) ? value.slice(0, 20).filter(x => ["string", "number", "boolean"].includes(typeof x)).map(bounded) : ["number", "boolean"].includes(typeof value) ? value : null;
  const pick = (row: Record<string, unknown> | undefined, keys: string[]) => row ? Object.fromEntries(keys.filter(key => row[key] !== undefined).map(key => [key, bounded(row[key])])) : null;
  const goal = pick(goals[0], ["protein_target_g", "step_target", "workouts_per_week", "equipment", "dietary_preferences", "allergies", "limitations", "exercise_preferences", "session_minutes", "training_days"]);
  const profile = pick(profiles[0], ["units", "coaching_tone", "time_zone"]);
  const medication = pick(meds[0], ["enabled", "appetite_level", "clinician_supervised"]);
  const weights = allWeights.filter(x => x.recorded_at >= start);
  const workouts = allWorkouts.filter(x => x.created_at >= start || x.status === "planned");
  const sets = allSets.filter(x => x.completed === true && x.created_at >= start);
  const protein = allProtein.filter(x => x.recorded_at >= start);
  const activity = allActivity.filter(x => x.date >= start.slice(0,10)).sort((a,b) => a.date.localeCompare(b.date));
  const plan = allPlans.find(x => x.is_active === true) ?? null;
  const g = goal as Record<string, unknown> | null;
  const pref = profile as { units: string; coaching_tone: string; time_zone: string } | null;
  let timeZone = pref?.time_zone ?? "UTC";
  try { new Intl.DateTimeFormat("en", { timeZone }); } catch { timeZone = "UTC"; }
  const localDate = (date: string) => new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(date));
  const sevenDaysAgo = new Date(now.getTime() - 7 * 86400000).toISOString();
  const today = localDate(now.toISOString());
  const firstDay = new Date(Date.parse(`${today}T12:00:00Z`) - 6 * 86400000).toISOString().slice(0, 10);
  const completed = (workouts as Array<Record<string, unknown>>).filter((w) => w.status === "completed" && String(w.completed_at) >= sevenDaysAgo);
  const facts: string[] = [`${completed.length} strength workouts completed in the last 7 days; weekly goal ${g?.workouts_per_week ?? 3}.`];
  const proteinByDate = new Map<string, number>();
  for (const entry of protein as Array<{ recorded_at: string; protein_g: number }>) {
    const date = localDate(entry.recorded_at);
    if (date < firstDay || date > today) continue;
    proteinByDate.set(date, (proteinByDate.get(date) ?? 0) + Number(entry.protein_g));
  }
  facts.push(`Protein target met on ${[...proteinByDate.values()].filter((grams) => grams >= Number(g?.protein_target_g ?? 120)).length} of the last 7 days; ${proteinByDate.size} days have protein logs; target ${g?.protein_target_g ?? 120} g/day.`);
  const a = (activity as Array<{ date: string; steps: number; readiness_score: number | null }>).filter((x) => x.date >= firstDay && x.date <= today);
  if (a.length) {
    facts.push(`Average ${Math.round(a.reduce((sum, x) => sum + x.steps, 0) / a.length)} steps across ${a.length} logged days; daily target ${g?.step_target ?? 7000}.`);
    const readiness = a.filter((x) => x.readiness_score !== null).at(-1);
    if (readiness) facts.push(`Latest logged readiness ${readiness.readiness_score}/100 on ${readiness.date}; this is a wellness estimate, not a medical score.`);
  } else facts.push("No steps are logged for the last 7 days.");
  const we = workoutExercises as Array<{ id: string; workout_id: string; exercise_id: string; target_weight_kg: number; target_sets: number; target_reps: number }>;
  const ws = workouts as Array<{ id: string; status: string; plan_id: string }>;
  const setData = (sets as Array<{ workout_exercise_id: string; completed_at: string; created_at: string; weight_kg: number; reps: number }>).flatMap((set) => {
    const match = we.find((x) => x.id === set.workout_exercise_id);
    return match ? [{ exercise_id: match.exercise_id, workout_id: match.workout_id, recorded_at: set.completed_at ?? set.created_at, weight_kg: Number(set.weight_kg), reps: set.reps }] : [];
  });
  const trend = trends(weights as Array<{ recorded_at: string; weight_kg: number }>, setData, now);
  if (trend.weeklyWeightLossPercent !== null) facts.push(`Weight decreased ${trend.weeklyWeightLossPercent.toFixed(1)}% comparing recent and prior 7-day averages (negative means gain).`);
  else facts.push("Not enough weight logs in both recent weeks to estimate weight-loss pace.");
  if (trend.strengthChangePercent !== null) facts.push(`Comparable strength estimate changed ${trend.strengthChangePercent.toFixed(1)}% across recent and prior 7-day periods; it is based on logged load and reps, not a direct muscle measurement.`);
  else facts.push("Not enough comparable strength sessions in both recent weeks to estimate a strength trend.");
  const activePlan = plan as { id: string; version: number } | null;
  const planned = we.filter((x) => ws.some((w) => w.id === x.workout_id && w.status === "planned" && w.plan_id === activePlan?.id)).slice(0, 24);
  const recentReadiness = a.filter((x) => x.readiness_score !== null).at(-1)?.readiness_score;
  const eligible = planned.filter((target) => {
    if (trend.risk || (recentReadiness != null && recentReadiness < 50)) return false;
    const matching = (sets as Array<{ workout_exercise_id: string; weight_kg: number; reps: number; rpe: number | null }>).filter((set) => {
      const session = we.find((x) => x.id === set.workout_exercise_id && x.exercise_id === target.exercise_id);
      return session && ws.some((w) => w.id === session.workout_id && w.status === "completed")
        && Number(set.weight_kg) >= Number(target.target_weight_kg) && set.reps >= target.target_reps && (set.rpe == null || Number(set.rpe) <= 8);
    });
    const counts = new Map<string, number>();
    for (const set of matching) {
      const session = we.find((x) => x.id === set.workout_exercise_id)!;
      counts.set(session.workout_id, (counts.get(session.workout_id) ?? 0) + 1);
    }
    return [...counts.values()].filter((count) => count >= target.target_sets).length >= 2;
  }).map((target) => target.id);
  return {
    facts, risk: trend.risk, preferences: { ...g, units: pref?.units ?? "metric", coaching_tone: pref?.coaching_tone ?? "supportive", medication_support: medication },
    plan: activePlan,
    progression_eligible: eligible,
    exercises: planned.map((x) => ({
      workout_exercise_id: x.id, name: (library as Array<{ id: string; name: string }>).find((exercise) => exercise.id === x.exercise_id)?.name ?? "Exercise",
      target_weight_kg: Number(x.target_weight_kg), target_reps: x.target_reps, target_sets: x.target_sets,
    })),
  };
}
