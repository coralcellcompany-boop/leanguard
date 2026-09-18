#!/usr/bin/env bash
set -euo pipefail
# Firebase CLI reads each value interactively; secrets never appear in arguments,
# terminal history, dotenv files, or the mobile application.
project_id="${1:-leanguard-a58ff}"
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# The pinned CLI wrapper drops unrelated credentials and DEBUG from its
# environment so diagnostic output cannot disclose another service's secrets.
node "$script_directory/firebase.mjs" functions:secrets:set OPENAI_API_KEY --project "$project_id"
node "$script_directory/firebase.mjs" functions:secrets:set REVENUECAT_SECRET_KEY --project "$project_id"
node "$script_directory/firebase.mjs" functions:secrets:set REVENUECAT_WEBHOOK_SECRET --project "$project_id"
