export type Reminder = {
  id: string; user_id: string; kind: string; enabled: boolean; smart: boolean;
  time_of_day: string; days_of_week: number[]; time_zone: string;
  quiet_start: string | null; quiet_end: string | null; delivery: string;
};

export function localClock(now: Date, timeZone: string) {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone, year: "numeric", month: "2-digit", day: "2-digit", weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(now);
  const field = (key: string) => parts.find((p) => p.type === key)!.value;
  return { date: `${field("year")}-${field("month")}-${field("day")}`, minutes: Number(field("hour")) * 60 + Number(field("minute")), weekday: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].indexOf(field("weekday")) + 1 };
}

const minutes = (time: string) => Number(time.slice(0, 2)) * 60 + Number(time.slice(3, 5));
export function isQuiet(minute: number, start: string | null, end: string | null): boolean {
  if (start === null || end === null) return false;
  const a = minutes(start); const b = minutes(end);
  if (a === b) return true; // Equal endpoints intentionally mean all day quiet.
  return a < b ? minute >= a && minute < b : minute >= a || minute < b;
}

export function reminderDue(reminder: Reminder, now = new Date(), pro = false): boolean {
  if (!reminder.enabled || reminder.delivery !== "push" || (reminder.smart && !pro)) return false;
  const local = localClock(now, reminder.time_zone);
  const due = minutes(reminder.time_of_day);
  return reminder.days_of_week.includes(local.weekday) && local.minutes >= due && local.minutes < due + 10
    && !isQuiet(local.minutes, reminder.quiet_start, reminder.quiet_end);
}
