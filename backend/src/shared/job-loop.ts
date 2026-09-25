/** A single process never overlaps jobs. Database locking additionally guards
 * workers in other containers; no unauthenticated scheduler URL exists. */
export function startJobLoop(options: {
  intervalMs: number;
  run: () => Promise<void>;
  onFailure?: () => void;
  now?: () => number;
}) {
  let stopped = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let pending: Promise<void> = Promise.resolve();
  const now = options.now ?? Date.now;
  let lastSuccess = 0;
  const tick = () => {
    if (stopped) return;
    pending = (async () => {
      try { await options.run(); lastSuccess = now(); }
      catch { options.onFailure?.(); }
      finally { if (!stopped) timer = setTimeout(tick, options.intervalMs); }
    })();
  };
  tick();
  return {
    get lastSuccess() { return lastSuccess; },
    async stop() { stopped = true; if (timer) clearTimeout(timer); await pending; },
  };
}
