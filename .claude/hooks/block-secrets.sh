#!/usr/bin/env bash
#
# PreToolUse hook: Block access to sensitive Rails files.
# Exit codes: 0 = allow, 2 = block
#

INPUT=$(cat)

# Extract file_path from JSON input
FILE_PATH=$(echo "$INPUT" | ruby -rjson -e 'puts JSON.parse(STDIN.read).dig("tool_input", "file_path").to_s' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")

# Block .env files
case "$BASENAME" in
  .env|.env.*)
    echo "BLOCKED: Environment file access ($BASENAME)" >&2
    echo "Use .env.example for templates. Use Rails credentials for secrets." >&2
    exit 2
    ;;
esac

# Block Rails credentials/keys
case "$FILE_PATH" in
  *config/master.key|*config/credentials.yml.enc|*config/credentials/*.key)
    echo "BLOCKED: Rails credentials file ($BASENAME)" >&2
    echo "Use: bin/rails credentials:edit" >&2
    exit 2
    ;;
esac

# Block Kamal secrets
case "$FILE_PATH" in
  *.kamal/secrets)
    echo "BLOCKED: Kamal secrets file" >&2
    exit 2
    ;;
esac

# Block private keys
case "$BASENAME" in
  *.pem|*.key|*.p12|*.pfx|id_rsa|id_ed25519|id_ecdsa)
    echo "BLOCKED: Private key file ($BASENAME)" >&2
    exit 2
    ;;
esac

exit 0
