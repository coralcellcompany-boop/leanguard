export type Subscriber = {
  entitlements?: Record<string, { expires_date: string | null; grace_period_expires_date?: string | null; product_identifier: string; purchase_date?: string }>;
  subscriptions?: Record<string, { expires_date?: string | null; grace_period_expires_date?: string | null; billing_issues_detected_at?: string | null; unsubscribe_detected_at?: string | null; refunded_at?: string | null; is_sandbox?: boolean; period_type?: string; auto_resume_date?: string | null }>;
  management_url?: string | null;
};

export function normalizeEntitlement(subscriber: Subscriber, now = Date.now(), allowSandbox = false) {
  const entitlement = subscriber.entitlements?.pro;
  const subscription = entitlement ? subscriber.subscriptions?.[entitlement.product_identifier] : undefined;
  const expires = entitlement?.expires_date ?? null;
  const grace = subscription?.grace_period_expires_date ?? entitlement?.grace_period_expires_date ?? null;
  const sandbox = subscription?.is_sandbox === true;
  const inGrace = !!grace && Date.parse(grace) > now;
  const active = !!entitlement && !subscription?.refunded_at
    && (!expires || Date.parse(expires) > now || inGrace) && (!sandbox || allowSandbox);
  let status = "expired";
  if (active) {
    status = inGrace ? "grace_period" : subscription?.billing_issues_detected_at ? "billing_issue"
      : subscription?.unsubscribe_detected_at ? "cancelled" : subscription?.period_type === "trial" ? "trial" : "active";
  } else if (subscription?.auto_resume_date) status = "paused";
  let managementUrl: string | null = null;
  try {
    const url = new URL(subscriber.management_url ?? "");
    if (url.protocol === "https:" && ["apps.apple.com", "play.google.com"].includes(url.hostname)) managementUrl = url.href;
  } catch { /* RevenueCat may not provide a management URL. */ }
  return {
    entitlement_id: "pro", is_active: active, product_id: entitlement?.product_identifier ?? null,
    expires_at: expires, grace_period_expires_at: grace, status,
    will_renew: active && !subscription?.unsubscribe_detected_at && !subscription?.billing_issues_detected_at,
    management_url: managementUrl, is_sandbox: sandbox,
  };
}
