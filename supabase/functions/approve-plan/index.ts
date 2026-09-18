import { authenticate, body, endpoint, HttpError, json, uuid } from "../_shared/http.ts";

Deno.serve(endpoint(async (req) => {
  const { client } = await authenticate(req);
  const input = await body(req);
  if (!uuid(input.proposal_id) || typeof input.approved !== "boolean") throw new HttpError(400, "invalid_request", "A proposal and explicit approval decision are required.");
  const { data, error } = await client.rpc("approve_plan_proposal", { p_proposal_id: input.proposal_id, p_approved: input.approved });
  if (error) throw new HttpError(409, "proposal_unavailable", "This proposal is expired, no longer eligible, or your plan has changed. Request a fresh review.");
  return json(data);
}));
