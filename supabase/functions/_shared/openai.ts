import { fallbackReply, instructions, responseSchema, validateReply, type CoachReply, type Kind, type Snapshot } from "./coaching.ts";

export type CoachingRequest = {
  key: string; model: string; kind: Kind; snapshot: Snapshot; message: string;
  history: Array<{ role: string; content: string }>; isPro: boolean;
};

/** Injectable transport lets failures be tested without any provider credentials. */
export async function generateCoachReply(request: CoachingRequest, transport: typeof fetch = fetch): Promise<{ reply: CoachReply; providerSucceeded: boolean }> {
  try {
    if (!request.key.trim()) throw new Error("Provider is not configured");
    const response = await transport("https://api.openai.com/v1/responses", {
      method: "POST", signal: AbortSignal.timeout(18000),
      headers: { Authorization: `Bearer ${request.key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: request.model, store: false, max_output_tokens: 1800, instructions,
        input: [{ role: "user", content: JSON.stringify({ kind: request.kind, tier: request.isPro ? "pro" : "free", snapshot: request.snapshot, recent_conversation: request.history, message: request.message }) }],
        text: { format: { type: "json_schema", name: "leanguard_coach", strict: true, schema: responseSchema } },
      }),
    });
    if (!response.ok) throw new Error("Provider unavailable");
    const result = await response.json();
    if (result.status !== "completed") throw new Error("Incomplete response");
    const content = (result.output ?? []).flatMap((item: { content?: Array<{ type: string; text?: string }> }) => item.content ?? []);
    if (content.some((item: { type: string }) => item.type === "refusal")) throw new Error("Provider refusal");
    const text = content.filter((item: { type: string }) => item.type === "output_text").map((item: { text: string }) => item.text).join("");
    return { reply: validateReply(JSON.parse(text), request.snapshot, request.kind), providerSucceeded: true };
  } catch {
    return { reply: fallbackReply(request.snapshot, request.kind), providerSucceeded: false };
  }
}
