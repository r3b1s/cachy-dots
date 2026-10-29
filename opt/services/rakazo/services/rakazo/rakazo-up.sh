# Brings Rakazo up as upstream deploys it: install-images.sh and its Compose
# file, both pinned by default.nix. Run by rakazo.service as the user rakazo in
# /var/lib/rakazo; every step leaves what is already right alone.
#
#   1. the pinned files go into the working directory, and install-images.sh
#      --prepare-only makes .env with random secrets once (back up its
#      ENCRYPTION_KEY: Rakazo's data is encrypted with it);
#   2. this sets the .env keys it owns (below) and writes a Compose override:
#      the web port on every address of the guest (the edge reaches it over the
#      bridge; the API stays on loopback), and the stack's CA for the containers
#      that call out, so they verify Executor through the edge;
#   3. install-images.sh --local pulls and starts the release; Compose recreates
#      only what changed.
#
# The .env keys it owns: the image tags (the release), WEB_ORIGIN,
# BETTER_AUTH_URL, API_URL and RAKAZO_HOST (the edge's origin),
# SANDBOX_COMPUTER_EGRESS=restricted (rakazo-computer-egress.service applies the
# rules), SANDBOX_COMPUTER_DNS (public resolvers: the guest's own resolver is a
# private address the egress rules drop) and SIGNUPS_ENABLED. Nothing else in
# .env is touched, and none of it is printed.
#
# Environment: RAKAZO_TAG, RAKAZO_FILES (the pinned files), SIGNUPS, COMPUTER_DNS,
# STACK_CA, and ORIGIN (from apply.sh's origin.env).

say() { printf 'rakazo-up: %s\n' "$*"; }

# Set KEY=VALUE lines in .env: replace each key's first line, drop its later
# duplicates, append the missing ones. Written (0600) only when it changes.
set_env() {
    local tmp kv changed=()
    for kv; do grep -qxF -- "$kv" .env || changed+=("${kv%%=*}"); done
    [ ${#changed[@]} -gt 0 ] || return 0
    tmp=$(mktemp .env.XXXXXX)
    printf '%s\n' "$@" | awk '
        NR == FNR { k = $0; sub(/=.*/, "", k); want[k] = $0; order[++n] = k; next }
        { k = $0; sub(/=.*/, "", k) }
        k in want { if (!(k in done)) print want[k]; done[k] = 1; next }
        { print }
        END { for (i = 1; i <= n; i++) if (!(order[i] in done)) print want[order[i]] }
    ' - .env > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" .env
    say ".env: set ${changed[*]}"
}

: "${ORIGIN:?no ORIGIN: run apply.sh, which writes /var/lib/cachy-stack/origin.env}"
host=${ORIGIN#*://}
host=${host%%:*}

# 1 ── the pinned files, and .env ─────────────────────────────────────────────
for f in install-images.sh docker-compose.images.yml .env.images.example; do
    cmp -s "$RAKAZO_FILES/$f" "$f" || install -m 0644 "$RAKAZO_FILES/$f" "$f"
done
[ -f .env ] || say "creating .env (random secrets; back up ENCRYPTION_KEY from $PWD/.env)"
bash install-images.sh --local --prepare-only >/dev/null

# 2 ── the keys this owns, and the override ───────────────────────────────────
set_env \
    "RAKAZO_IMAGE_TAG=$RAKAZO_TAG" \
    "RAKAZO_COMPUTER_IMAGE_TAG=$RAKAZO_TAG" \
    "WEB_ORIGIN=$ORIGIN" \
    "BETTER_AUTH_URL=$ORIGIN" \
    "API_URL=$ORIGIN" \
    "RAKAZO_HOST=$host" \
    "SANDBOX_COMPUTER_EGRESS=restricted" \
    "SANDBOX_COMPUTER_DNS=$COMPUTER_DNS" \
    "SIGNUPS_ENABLED=$SIGNUPS"

tmp=$(mktemp override.XXXXXX)
cat > "$tmp" <<YAML
# Written by rakazo-up (cachy-dots opt/services/rakazo); rewritten on every start.
services:
  web:
    ports: !override
      - "5173:5173"
  api:
    environment:
      NODE_EXTRA_CA_CERTS: /etc/cachy-stack-ca.crt
    volumes:
      - $STACK_CA:/etc/cachy-stack-ca.crt:ro
  worker:
    environment:
      NODE_EXTRA_CA_CERTS: /etc/cachy-stack-ca.crt
    volumes:
      - $STACK_CA:/etc/cachy-stack-ca.crt:ro
YAML
if cmp -s "$tmp" docker-compose.override.yml; then rm -f "$tmp"; else mv "$tmp" docker-compose.override.yml; fi

# 3 ── the release ────────────────────────────────────────────────────────────
say "install-images.sh at $RAKAZO_TAG (pulls, then starts what changed)"
bash install-images.sh --local
