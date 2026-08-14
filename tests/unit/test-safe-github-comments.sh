#!/usr/bin/env bash
# Regression coverage for fail-closed GitHub comment posting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../helpers/test-framework.sh disable=SC1091
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Safe GitHub comment posting"

SAFE_POST="$PROJECT_ROOT/scripts/safe-gh-comment.sh"
GH_ARGS_LOG="$TEST_TMP_DIR/gh-args.log"
GH_BODY_LOG="$TEST_TMP_DIR/gh-body.log"
GH_STDIN_LOG="$TEST_TMP_DIR/gh-stdin.log"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

multiline_match() {
    local pattern="$1"
    shift
    OCTOPUS_TEST_REGEX="$pattern" python3 -c '
import os
from pathlib import Path
import re
import sys

pattern = os.environ["OCTOPUS_TEST_REGEX"].replace("[[:space:]]", r"\s")
targets = [Path(value) for value in sys.argv[1:]]
if targets:
    files = []
    for target in targets:
        if target.is_dir():
            files.extend(path for path in target.rglob("*") if path.is_file())
        elif target.is_file():
            files.append(target)
    data = "\n".join(path.read_text(errors="replace") for path in files)
else:
    data = sys.stdin.read()
try:
    matched = re.search(pattern, data, re.MULTILINE) is not None
except re.error:
    raise SystemExit(2)
raise SystemExit(0 if matched else 1)
' "$@"
}

if [[ -x "$SAFE_POST" ]]; then
    pass "safe GitHub comment helper exists and is executable"
else
    fail "safe GitHub comment helper exists and is executable" \
        "missing executable scripts/safe-gh-comment.sh"
fi

cat > "$MOCK_BIN_DIR/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" > "$GH_ARGS_LOG"
: > "$GH_BODY_LOG"
: > "$GH_STDIN_LOG"

previous=""
for argument in "$@"; do
    if [[ "$previous" == "--body-file" ]]; then
        cp "$argument" "$GH_BODY_LOG"
    elif [[ "$previous" == "--input" ]]; then
        if [[ "$argument" == "-" ]]; then
            cat > "$GH_STDIN_LOG"
        else
            cp "$argument" "$GH_STDIN_LOG"
        fi
    fi
    previous="$argument"
done

if [[ "${GH_IGNORE_TERM:-}" == "1" ]]; then
    trap '' TERM HUP
fi
if [[ -n "${GH_DELAY_SECONDS:-}" ]]; then
    sleep "$GH_DELAY_SECONDS"
fi
if [[ -n "${GH_COMPLETION_LOG:-}" ]]; then
    : > "$GH_COMPLETION_LOG"
fi
MOCK_GH
chmod +x "$MOCK_BIN_DIR/gh"

export GH_ARGS_LOG GH_BODY_LOG GH_STDIN_LOG

safe_body="$TEST_TMP_DIR/safe-body.md"
command_sentinel="$TEST_TMP_DIR/command-substitution-ran"
# shellcheck disable=SC2016 # Literal command substitution is the regression payload.
printf 'Fixed: complete `env` arguments remain literal, as does $(touch %s).\n' \
    "$command_sentinel" > "$safe_body"

set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$safe_body" \
    > "$TEST_TMP_DIR/safe-output.log" 2>&1
safe_rc=$?
set -e

if [[ "$safe_rc" -eq 0 ]] && cmp -s "$safe_body" "$GH_BODY_LOG" && \
        [[ ! -e "$command_sentinel" ]]; then
    pass "PR comments preserve Markdown command syntax literally through a body file"
else
    fail "PR comments preserve Markdown command syntax literally through a body file" \
        "safe body was not transmitted unchanged"
fi

if [[ -f "$GH_ARGS_LOG" ]] && grep -Fxq -- 'pr' "$GH_ARGS_LOG" && \
        grep -Fxq -- 'comment' "$GH_ARGS_LOG" && \
        grep -Fxq -- '42' "$GH_ARGS_LOG" && \
        grep -Fxq -- '--repo' "$GH_ARGS_LOG" && \
        grep -Fxq -- 'octopus/example' "$GH_ARGS_LOG" && \
        grep -Fxq -- '--body-file' "$GH_ARGS_LOG" && \
        ! grep -Fxq -- '--body' "$GH_ARGS_LOG" && \
        ! grep -Eq -- 'Fixed: complete' "$GH_ARGS_LOG"; then
    pass "PR comments pass body content by file rather than inline text"
else
    fail "PR comments pass body content by file rather than inline text" \
        "GitHub CLI invocation did not use --body-file"
fi

: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 - < "$safe_body" \
    > "$TEST_TMP_DIR/stdin-output.log" 2>&1
stdin_rc=$?
set -e
if [[ "$stdin_rc" -eq 0 ]] && cmp -s "$safe_body" "$GH_BODY_LOG" && \
        grep -Fxq -- '--body-file' "$GH_ARGS_LOG"; then
    pass "standard-input bodies are privately snapshotted before posting"
else
    fail "standard-input bodies are privately snapshotted before posting" \
        "stdin body was rejected, changed, or posted without a snapshot"
fi

utf8_body="$TEST_TMP_DIR/utf8-body.md"
printf '%s\n' 'Review complete — verified by Claude Octopus 🐙' > "$utf8_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$utf8_body" \
    > "$TEST_TMP_DIR/utf8-output.log" 2>&1
utf8_rc=$?
set -e
if [[ "$utf8_rc" -eq 0 ]] && cmp -s "$utf8_body" "$GH_BODY_LOG"; then
    pass "valid UTF-8 GitHub text remains postable and unchanged"
else
    fail "valid UTF-8 GitHub text remains postable and unchanged" \
        "valid non-ASCII Markdown was rejected or changed"
fi

credential_body="$TEST_TMP_DIR/credential-body.md"
printf 'PERPLEXITY_API_KEY=%s%s\n' 'pplx-' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' > "$credential_body"
: > "$GH_ARGS_LOG"
set +e
credential_output=$(PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example issue-comment 7 "$credential_body" 2>&1)
credential_rc=$?
set -e

if [[ "$credential_rc" -eq 65 && ! -s "$GH_ARGS_LOG" && \
        "$credential_output" != *"pplx-"* ]]; then
    pass "credential-shaped content is rejected without invocation or disclosure"
else
    fail "credential-shaped content is rejected without invocation or disclosure" \
        "credential payload was accepted, echoed, or sent to GitHub CLI"
fi

private_key_body="$TEST_TMP_DIR/private-key-body.md"
printf '%s%s\n%s\n%s%s\n' '-----BEGIN ' 'PRIVATE KEY-----' \
    'not-a-real-key-but-the-boundary-must-be-blocked' '-----END ' 'PRIVATE KEY-----' \
    > "$private_key_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$private_key_body" \
    > "$TEST_TMP_DIR/private-key-output.log" 2>&1
private_key_rc=$?
set -e
if [[ "$private_key_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "private-key boundaries fail closed"
else
    fail "private-key boundaries fail closed" \
        "private-key boundary reached GitHub CLI"
fi

short_authorization_body="$TEST_TMP_DIR/short-authorization.md"
printf '%s\n' 'Authorization: Basic dTpw' > "$short_authorization_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$short_authorization_body" \
    > "$TEST_TMP_DIR/short-authorization-output.log" 2>&1
short_authorization_rc=$?
set -e
if [[ "$short_authorization_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "short Authorization credentials fail closed"
else
    fail "short Authorization credentials fail closed" \
        "short Authorization credential reached GitHub CLI"
fi

quoted_authorization_body="$TEST_TMP_DIR/quoted-authorization.md"
printf '%s\n' '{"Authorization":"Basic dTpw"}' > "$quoted_authorization_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example issue-comment 7 "$quoted_authorization_body" \
    > "$TEST_TMP_DIR/quoted-authorization-output.log" 2>&1
quoted_authorization_rc=$?
set -e
if [[ "$quoted_authorization_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "quoted JSON authorization headers fail closed"
else
    fail "quoted JSON authorization headers fail closed" \
        "quoted authorization value reached GitHub CLI"
fi

multiline_authorization_body="$TEST_TMP_DIR/multiline-authorization.md"
cat > "$multiline_authorization_body" <<'MULTILINE_AUTHORIZATION'
"Authorization":
  "Basic dTpw"
MULTILINE_AUTHORIZATION
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example issue-comment 7 "$multiline_authorization_body" \
    > "$TEST_TMP_DIR/multiline-authorization-output.log" 2>&1
multiline_authorization_rc=$?
set -e
if [[ "$multiline_authorization_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "multiline authorization values fail closed"
else
    fail "multiline authorization values fail closed" \
        "multiline authorization value reached GitHub CLI"
fi

sensitive_assignment_body="$TEST_TMP_DIR/sensitive-assignment.md"
printf 'SERVICE_TOKEN=%s%s\n' 'high-entropy-' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' > "$sensitive_assignment_body"
: > "$GH_ARGS_LOG"
set +e
sensitive_output=$(PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-review 42 "$sensitive_assignment_body" \
    2>&1)
sensitive_rc=$?
set -e

if [[ "$sensitive_rc" -eq 65 && ! -s "$GH_ARGS_LOG" && \
        "$sensitive_output" != *"high-entropy"* ]]; then
    pass "sensitive environment assignments fail closed"
else
    fail "sensitive environment assignments fail closed" \
        "sensitive assignment reached GitHub CLI"
fi

secret_key_body="$TEST_TMP_DIR/secret-key-assignment.md"
printf '%s\n' 'STRIPE_SECRET_KEY=hunter2' > "$secret_key_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example issue-comment 7 "$secret_key_body" \
    > "$TEST_TMP_DIR/secret-key-output.log" 2>&1
secret_key_rc=$?
set -e
if [[ "$secret_key_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "SECRET_KEY-suffixed assignments fail closed"
else
    fail "SECRET_KEY-suffixed assignments fail closed" \
        "SECRET_KEY assignment reached GitHub CLI"
fi

stripe_key_body="$TEST_TMP_DIR/stripe-key.md"
printf '%s%s\n' 'sk_' \
    'live_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' > "$stripe_key_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$stripe_key_body" \
    > "$TEST_TMP_DIR/stripe-key-output.log" 2>&1
stripe_key_rc=$?
set -e
if [[ "$stripe_key_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "Stripe live credential formats fail closed"
else
    fail "Stripe live credential formats fail closed" \
        "Stripe live credential format reached GitHub CLI"
fi

aws_assignment_body="$TEST_TMP_DIR/aws-assignment.md"
printf 'AWS_SECRET_ACCESS_KEY=%s\n' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' > "$aws_assignment_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example issue-comment 7 "$aws_assignment_body" \
    > "$TEST_TMP_DIR/aws-output.log" 2>&1
aws_assignment_rc=$?
set -e
if [[ "$aws_assignment_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "AWS secret access assignments fail closed"
else
    fail "AWS secret access assignments fail closed" \
        "AWS secret access assignment reached GitHub CLI"
fi

aws_temporary_id_body="$TEST_TMP_DIR/aws-temporary-id.md"
printf 'AWS_ACCESS_KEY_ID=%s%s\n' 'ASIA' \
    'AAAAAAAAAAAAAAAA' > "$aws_temporary_id_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example issue-comment 7 "$aws_temporary_id_body" \
    > "$TEST_TMP_DIR/aws-temporary-id-output.log" 2>&1
aws_temporary_id_rc=$?
set -e
if [[ "$aws_temporary_id_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "AWS temporary access-key IDs fail closed"
else
    fail "AWS temporary access-key IDs fail closed" \
        "AWS temporary access-key ID reached GitHub CLI"
fi

bare_assignment_body="$TEST_TMP_DIR/bare-assignment.md"
printf '%s\n' 'TOKEN=hunter2' > "$bare_assignment_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$bare_assignment_body" \
    > "$TEST_TMP_DIR/bare-assignment-output.log" 2>&1
bare_assignment_rc=$?
set -e
if [[ "$bare_assignment_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "bare sensitive names with short values fail closed"
else
    fail "bare sensitive names with short values fail closed" \
        "bare short sensitive assignment reached GitHub CLI"
fi

prefixed_assignment_body="$TEST_TMP_DIR/prefixed-assignment.md"
printf '%s\n' '+ SERVICE_PASSWORD=hunter2' > "$prefixed_assignment_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example review-reply 42 9001 "$prefixed_assignment_body" \
    > "$TEST_TMP_DIR/prefixed-assignment-output.log" 2>&1
prefixed_assignment_rc=$?
set -e
if [[ "$prefixed_assignment_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "Markdown and diff-prefixed sensitive assignments fail closed"
else
    fail "Markdown and diff-prefixed sensitive assignments fail closed" \
        "prefixed sensitive assignment reached GitHub CLI"
fi

additional_prefix_failures=0
for prefixed_secret in \
    '* SERVICE_TOKEN=hunter2' \
    '1. SERVICE_TOKEN=hunter2' \
    'declare -x SERVICE_TOKEN=hunter2' \
    'Leaked: SERVICE_TOKEN=hunter2'; do
    printf '%s\n' "$prefixed_secret" > "$TEST_TMP_DIR/additional-prefix.md"
    : > "$GH_ARGS_LOG"
    set +e
    PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
        --repo octopus/example pr-comment 42 "$TEST_TMP_DIR/additional-prefix.md" \
        > "$TEST_TMP_DIR/additional-prefix-output.log" 2>&1
    additional_prefix_rc=$?
    set -e
    if [[ "$additional_prefix_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
        additional_prefix_failures=$((additional_prefix_failures + 1))
    fi
done
if [[ "$additional_prefix_failures" -eq 4 ]]; then
    pass "generated Markdown and shell prefixes cannot hide sensitive assignments"
else
    fail "generated Markdown and shell prefixes cannot hide sensitive assignments" \
        "only $additional_prefix_failures of 4 prefixed assignments were blocked"
fi

generic_key_body="$TEST_TMP_DIR/generic-key-assignment.md"
printf '%s\n' 'ENCRYPTION_KEY=hunter2' > "$generic_key_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example issue-comment 7 "$generic_key_body" \
    > "$TEST_TMP_DIR/generic-key-output.log" 2>&1
generic_key_rc=$?
set -e
if [[ "$generic_key_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "generic KEY-suffixed assignments fail closed"
else
    fail "generic KEY-suffixed assignments fail closed" \
        "generic KEY assignment reached GitHub CLI"
fi

database_url_body="$TEST_TMP_DIR/database-url-assignment.md"
printf '%s\n' 'DATABASE_URL=postgres://user:hunter2@db.internal/app' > "$database_url_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$database_url_body" \
    > "$TEST_TMP_DIR/database-url-output.log" 2>&1
database_url_rc=$?
set -e
if [[ "$database_url_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "database URL assignments with credentials fail closed"
else
    fail "database URL assignments with credentials fail closed" \
        "credentialed database URL assignment reached GitHub CLI"
fi

connection_url_body="$TEST_TMP_DIR/connection-url.md"
printf '%s\n' 'mongodb+srv://user:hunter2@cluster.example/app' > "$connection_url_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$connection_url_body" \
    > "$TEST_TMP_DIR/connection-url-output.log" 2>&1
connection_url_rc=$?
set -e
if [[ "$connection_url_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "embedded credentials in non-HTTP connection URLs fail closed"
else
    fail "embedded credentials in non-HTTP connection URLs fail closed" \
        "credentialed non-HTTP URL reached GitHub CLI"
fi

password_only_url_body="$TEST_TMP_DIR/password-only-url.md"
printf '%s\n' 'redis://:hunter2@redis.internal/0' > "$password_only_url_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$password_only_url_body" \
    > "$TEST_TMP_DIR/password-only-url-output.log" 2>&1
password_only_url_rc=$?
set -e
if [[ "$password_only_url_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "password-only credential URLs fail closed"
else
    fail "password-only credential URLs fail closed" \
        "password-only credential URL reached GitHub CLI"
fi

lowercase_assignment_body="$TEST_TMP_DIR/lowercase-assignment.md"
printf '%s\n' 'service_token=hunter2' > "$lowercase_assignment_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example issue-comment 7 "$lowercase_assignment_body" \
    > "$TEST_TMP_DIR/lowercase-assignment-output.log" 2>&1
lowercase_assignment_rc=$?
set -e
if [[ "$lowercase_assignment_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "lowercase sensitive assignments fail closed"
else
    fail "lowercase sensitive assignments fail closed" \
        "lowercase sensitive assignment reached GitHub CLI"
fi

concatenated_assignment_body="$TEST_TMP_DIR/concatenated-assignment.md"
printf '%s\n' "SERVICE_TOKEN='example'hunter2" > "$concatenated_assignment_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$concatenated_assignment_body" \
    > "$TEST_TMP_DIR/concatenated-assignment-output.log" 2>&1
concatenated_assignment_rc=$?
set -e
if [[ "$concatenated_assignment_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "concatenated sensitive assignments fail closed"
else
    fail "concatenated sensitive assignments fail closed" \
        "concatenated sensitive assignment reached GitHub CLI"
fi

structured_secret_failures=0
for structured_secret in \
        '{"SERVICE_TOKEN":"hunter2"}' \
        'PASSWORD: hunter2'; do
    printf '%s\n' "$structured_secret" > "$TEST_TMP_DIR/structured-secret.md"
    : > "$GH_ARGS_LOG"
    set +e
    PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
        --repo octopus/example issue-comment 7 "$TEST_TMP_DIR/structured-secret.md" \
        > "$TEST_TMP_DIR/structured-secret-output.log" 2>&1
    structured_secret_rc=$?
    set -e
    if [[ "$structured_secret_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
        structured_secret_failures=$((structured_secret_failures + 1))
    fi
done
if [[ "$structured_secret_failures" -eq 2 ]]; then
    pass "JSON and YAML sensitive values fail closed"
else
    fail "JSON and YAML sensitive values fail closed" \
        "only $structured_secret_failures of 2 structured secrets were blocked"
fi

common_secret_name_failures=0
common_secret_name_index=0
for common_secret_name_body in \
        '{"apiKey":"hunter2"}' \
        "'SERVICE_TOKEN': 'hunter2'" \
        'SECRET_KEY_BASE=hunter2'; do
    common_secret_name_index=$((common_secret_name_index + 1))
    common_secret_name_file="$TEST_TMP_DIR/common-secret-name-${common_secret_name_index}.md"
    printf '%s\n' "$common_secret_name_body" > "$common_secret_name_file"
    : > "$GH_ARGS_LOG"
    set +e
    PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
        --repo octopus/example pr-comment 42 "$common_secret_name_file" \
        > "$TEST_TMP_DIR/common-secret-name-${common_secret_name_index}-output.log" 2>&1
    common_secret_name_rc=$?
    set -e
    if [[ "$common_secret_name_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
        common_secret_name_failures=$((common_secret_name_failures + 1))
    fi
done
if [[ "$common_secret_name_failures" -eq 3 ]]; then
    pass "common camelCase, quoted, and base secret names fail closed"
else
    fail "common camelCase, quoted, and base secret names fail closed" \
        "only $common_secret_name_failures of 3 common secret names were blocked"
fi

prefixed_camel_secret_failures=0
prefixed_camel_secret_index=0
for prefixed_camel_secret_body in \
        '{"stripeApiKey":"hunter2"}' \
        'servicePassword: hunter2' \
        'awsClientSecret=hunter2'; do
    prefixed_camel_secret_index=$((prefixed_camel_secret_index + 1))
    prefixed_camel_secret_file="$TEST_TMP_DIR/prefixed-camel-secret-${prefixed_camel_secret_index}.md"
    printf '%s\n' "$prefixed_camel_secret_body" > "$prefixed_camel_secret_file"
    : > "$GH_ARGS_LOG"
    set +e
    PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
        --repo octopus/example pr-comment 42 "$prefixed_camel_secret_file" \
        > "$TEST_TMP_DIR/prefixed-camel-secret-${prefixed_camel_secret_index}-output.log" 2>&1
    prefixed_camel_secret_rc=$?
    set -e
    if [[ "$prefixed_camel_secret_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
        prefixed_camel_secret_failures=$((prefixed_camel_secret_failures + 1))
    fi
done
if [[ "$prefixed_camel_secret_failures" -eq 3 ]]; then
    pass "prefixed camelCase credential names fail closed"
else
    fail "prefixed camelCase credential names fail closed" \
        "only $prefixed_camel_secret_failures of 3 prefixed camelCase names were blocked"
fi

nested_structured_body="$TEST_TMP_DIR/nested-structured-secret.md"
printf '%s\n' '{"config":{"SERVICE_TOKEN":"hunter2"}}' > "$nested_structured_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$nested_structured_body" \
    > "$TEST_TMP_DIR/nested-structured-output.log" 2>&1
nested_structured_rc=$?
set -e
if [[ "$nested_structured_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "nested structured sensitive fields fail closed"
else
    fail "nested structured sensitive fields fail closed" \
        "nested structured secret reached GitHub CLI"
fi

multiline_structured_body="$TEST_TMP_DIR/multiline-structured-secret.md"
cat > "$multiline_structured_body" <<'MULTILINE_STRUCTURED_SECRET'
"SERVICE_TOKEN":
  "hunter2"
MULTILINE_STRUCTURED_SECRET
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$multiline_structured_body" \
    > "$TEST_TMP_DIR/multiline-structured-output.log" 2>&1
multiline_structured_rc=$?
set -e
if [[ "$multiline_structured_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "multiline structured sensitive values fail closed"
else
    fail "multiline structured sensitive values fail closed" \
        "multiline structured secret reached GitHub CLI"
fi

safe_prose_body="$TEST_TMP_DIR/safe-prose.md"
printf '%s\n' 'Use a cache key: a stable composite identifier.' > "$safe_prose_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$safe_prose_body" \
    > "$TEST_TMP_DIR/safe-prose-output.log" 2>&1
safe_prose_rc=$?
set -e
if [[ "$safe_prose_rc" -eq 0 ]] && cmp -s "$safe_prose_body" "$GH_BODY_LOG"; then
    pass "ordinary prose labels are not misclassified as credentials"
else
    fail "ordinary prose labels are not misclassified as credentials" \
        "safe prose label was blocked or changed"
fi

github_actions_placeholder_body="$TEST_TMP_DIR/github-actions-placeholder.md"
printf '%s\n' 'token: ${{ secrets.GITHUB_TOKEN }}' > "$github_actions_placeholder_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$github_actions_placeholder_body" \
    > "$TEST_TMP_DIR/github-actions-placeholder-output.log" 2>&1
github_actions_placeholder_rc=$?
set -e
if [[ "$github_actions_placeholder_rc" -eq 0 ]] && \
        cmp -s "$github_actions_placeholder_body" "$GH_BODY_LOG"; then
    pass "GitHub Actions secret references are accepted as placeholders"
else
    fail "GitHub Actions secret references are accepted as placeholders" \
        "safe GitHub Actions placeholder was blocked or changed"
fi

equality_body="$TEST_TMP_DIR/equality-expression.md"
printf '%s\n' 'The guard checks TOKEN == null before dispatch.' > "$equality_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$equality_body" \
    > "$TEST_TMP_DIR/equality-expression-output.log" 2>&1
equality_rc=$?
set -e
if [[ "$equality_rc" -eq 0 ]] && cmp -s "$equality_body" "$GH_BODY_LOG"; then
    pass "equality expressions are not misclassified as assignments"
else
    fail "equality expressions are not misclassified as assignments" \
        "safe equality expression was blocked or changed"
fi

environment_body="$TEST_TMP_DIR/environment-body.md"
cat > "$environment_body" <<'ENVIRONMENT_BODY'
HOME=/tmp/example
PATH=/usr/bin:/bin
SHELL=/bin/bash
USER=example
PWD=/tmp/project
ENVIRONMENT_BODY
: > "$GH_ARGS_LOG"
set +e
environment_output=$(PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$environment_body" \
    2>&1)
environment_rc=$?
set -e

if [[ "$environment_rc" -eq 65 && ! -s "$GH_ARGS_LOG" && \
        "$environment_output" != *"HOME="* ]]; then
    pass "environment-dump shaped content fails closed"
else
    fail "environment-dump shaped content fails closed" \
        "environment dump reached GitHub CLI"
fi

prefixed_environment_body="$TEST_TMP_DIR/prefixed-environment-body.md"
cat > "$prefixed_environment_body" <<'PREFIXED_ENVIRONMENT_BODY'
* HOME=/tmp/example
* PATH=/usr/bin:/bin
* SHELL=/bin/bash
* USER=example
* PWD=/tmp/project
PREFIXED_ENVIRONMENT_BODY
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$prefixed_environment_body" \
    > "$TEST_TMP_DIR/prefixed-environment-output.log" 2>&1
prefixed_environment_rc=$?
set -e
if [[ "$prefixed_environment_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "Markdown-prefixed environment dumps fail closed"
else
    fail "Markdown-prefixed environment dumps fail closed" \
        "prefixed environment dump reached GitHub CLI"
fi

placeholder_body="$TEST_TMP_DIR/placeholder-body.md"
cat > "$placeholder_body" <<'PLACEHOLDER_BODY'
Use SERVICE_TOKEN=${SERVICE_TOKEN}, API_KEY=<redacted>, or PASSWORD=REDACTED.
PLACEHOLDER_BODY
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example issue-comment 7 "$placeholder_body" \
    > "$TEST_TMP_DIR/placeholder-output.log" 2>&1
placeholder_rc=$?
set -e

if [[ "$placeholder_rc" -eq 0 ]] && cmp -s "$placeholder_body" "$GH_BODY_LOG"; then
    pass "explicit credential placeholders remain postable"
else
    fail "explicit credential placeholders remain postable" \
        "safe placeholder documentation was rejected or changed"
fi

: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-create "fix: safe posting" feature/safe-posting "$safe_body" \
    > "$TEST_TMP_DIR/pr-create-output.log" 2>&1
pr_create_rc=$?
set -e
if [[ "$pr_create_rc" -eq 0 ]] && grep -Fxq -- 'pr' "$GH_ARGS_LOG" && \
        grep -Fxq -- 'create' "$GH_ARGS_LOG" && \
        grep -Fxq -- '--body-file' "$GH_ARGS_LOG" && \
        grep -Fxq -- 'fix: safe posting' "$GH_ARGS_LOG" && \
        grep -Fxq -- 'feature/safe-posting' "$GH_ARGS_LOG"; then
    pass "PR creation uses a validated body file"
else
    fail "PR creation uses a validated body file" \
        "PR creation did not use the safe file-based path"
fi

valid_head_count=0
for valid_head in 'release/1.2.3+build@4' 'octocat:feature/safe+fast@2'; do
    : > "$GH_ARGS_LOG"
    set +e
    PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
        --repo octopus/example pr-create "fix: valid head" "$valid_head" "$safe_body" \
        > "$TEST_TMP_DIR/valid-head-output.log" 2>&1
    valid_head_rc=$?
    set -e
    if [[ "$valid_head_rc" -eq 0 ]] && grep -Fxq -- "$valid_head" "$GH_ARGS_LOG"; then
        valid_head_count=$((valid_head_count + 1))
    fi
done
if [[ "$valid_head_count" -eq 2 ]]; then
    pass "valid Git and fork PR head syntax remains supported"
else
    fail "valid Git and fork PR head syntax remains supported" \
        "only $valid_head_count of 2 valid PR heads were accepted"
fi

: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example issue-create "security: safe posting" "$safe_body" \
    > "$TEST_TMP_DIR/issue-create-output.log" 2>&1
issue_create_rc=$?
set -e
if [[ "$issue_create_rc" -eq 0 ]] && grep -Fxq -- 'issue' "$GH_ARGS_LOG" && \
        grep -Fxq -- 'create' "$GH_ARGS_LOG" && \
        grep -Fxq -- '--body-file' "$GH_ARGS_LOG"; then
    pass "issue creation uses a validated body file"
else
    fail "issue creation uses a validated body file" \
        "issue creation did not use the safe file-based path"
fi

: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example review-reply 42 9001 "$safe_body" \
    > "$TEST_TMP_DIR/reply-output.log" 2>&1
reply_rc=$?
set -e

reply_body=""
if [[ -s "$GH_STDIN_LOG" ]]; then
    reply_body=$(jq -r '.body // empty' "$GH_STDIN_LOG" 2>/dev/null || true)
fi
if [[ "$reply_rc" -eq 0 && "$reply_body" == "$(<"$safe_body")" ]] && \
        grep -Fxq -- '--silent' "$GH_ARGS_LOG" && \
        grep -Fxq -- '--input' "$GH_ARGS_LOG" && \
        grep -Fxq -- 'repos/octopus/example/pulls/42/comments/9001/replies' "$GH_ARGS_LOG" && \
        ! grep -Eq -- 'Fixed: complete' "$GH_ARGS_LOG"; then
    pass "review replies use silent JSON input and preserve the body"
else
    fail "review replies use silent JSON input and preserve the body" \
        "review reply did not use the silent JSON path"
fi

: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example review-reply 42 9001 "$credential_body" \
    > "$TEST_TMP_DIR/reply-credential-output.log" 2>&1
reply_credential_rc=$?
set -e

if [[ "$reply_credential_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "review replies cannot bypass credential rejection"
else
    fail "review replies cannot bypass credential rejection" \
        "credential-shaped review reply reached GitHub CLI"
fi

: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example review-line 42 deadbeef src/example.sh 19 "$safe_body" \
    > "$TEST_TMP_DIR/review-line-output.log" 2>&1
review_line_rc=$?
set -e

review_line_body=""
review_line_path=""
review_line_number=""
if [[ -s "$GH_STDIN_LOG" ]]; then
    review_line_body=$(jq -r '.body // empty' "$GH_STDIN_LOG" 2>/dev/null || true)
    review_line_path=$(jq -r '.path // empty' "$GH_STDIN_LOG" 2>/dev/null || true)
    review_line_number=$(jq -r '.line // empty' "$GH_STDIN_LOG" 2>/dev/null || true)
fi
if [[ "$review_line_rc" -eq 0 && "$review_line_body" == "$(<"$safe_body")" && \
        "$review_line_path" == "src/example.sh" && "$review_line_number" == "19" ]] && \
        grep -Fxq -- 'repos/octopus/example/pulls/42/comments' "$GH_ARGS_LOG"; then
    pass "inline review findings use validated silent JSON input"
else
    fail "inline review findings use validated silent JSON input" \
        "inline review finding did not use the validated JSON path"
fi

invalid_cases=0
for invalid_invocation in \
    "--repo -R pr-comment 42 $safe_body" \
    "--repo octopus/example pr-comment not-a-number $safe_body" \
    "--repo octopus/example review-reply 42 not-a-number $safe_body" \
    "--repo octopus/example unknown-operation 42 $safe_body"; do
    : > "$GH_ARGS_LOG"
    set +e
    # shellcheck disable=SC2086 # Intentional word splitting for fixed test cases.
    PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" $invalid_invocation \
        > "$TEST_TMP_DIR/invalid-output.log" 2>&1
    invalid_rc=$?
    set -e
    if [[ "$invalid_rc" -eq 64 && ! -s "$GH_ARGS_LOG" ]]; then
        invalid_cases=$((invalid_cases + 1))
    fi
done
if [[ "$invalid_cases" -eq 4 ]]; then
    pass "invalid repositories, identifiers, and operations fail before GitHub CLI"
else
    fail "invalid repositories, identifiers, and operations fail before GitHub CLI" \
        "only $invalid_cases of 4 hostile argument cases failed safely"
fi

: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example review-line 42 deadbeef dir/.. 19 "$safe_body" \
    > "$TEST_TMP_DIR/trailing-dotdot-output.log" 2>&1
trailing_dotdot_rc=$?
set -e
if [[ "$trailing_dotdot_rc" -eq 64 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "review paths ending in dot-dot fail before GitHub CLI"
else
    fail "review paths ending in dot-dot fail before GitHub CLI" \
        "trailing path traversal reached GitHub CLI"
fi

: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$TEST_TMP_DIR/missing-body.md" \
    > "$TEST_TMP_DIR/missing-body-output.log" 2>&1
missing_body_rc=$?
set -e
if [[ "$missing_body_rc" -eq 66 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "missing body files fail before GitHub CLI"
else
    fail "missing body files fail before GitHub CLI" \
        "missing body file did not fail with the input error contract"
fi

oversized_body="$TEST_TMP_DIR/oversized-body.md"
head -c 65537 /dev/zero | tr '\000' 'a' > "$oversized_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$oversized_body" \
    > "$TEST_TMP_DIR/oversized-output.log" 2>&1
oversized_rc=$?
set -e
if [[ "$oversized_rc" -eq 66 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "oversized bodies fail before GitHub CLI"
else
    fail "oversized bodies fail before GitHub CLI" \
        "oversized body did not fail with the input error contract"
fi

if grep -Eq -- 'head -c.*MAX_BODY_BYTES' "$SAFE_POST"; then
    pass "body snapshot reads are hard-bounded before validation"
else
    fail "body snapshot reads are hard-bounded before validation" \
        "missing the positive bounded-read contract"
fi

: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 - \
    < "$oversized_body" > "$TEST_TMP_DIR/oversized-stdin-output.log" 2>&1
oversized_stdin_rc=$?
set -e
if [[ "$oversized_stdin_rc" -eq 66 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "oversized standard input is bounded before GitHub CLI"
else
    fail "oversized standard input is bounded before GitHub CLI" \
        "oversized stdin reached GitHub CLI or returned $oversized_stdin_rc"
fi

if grep -Eq -- 'grep -Eic -- .*pattern.*body_file.*>/dev/null' "$SAFE_POST" && \
        ! grep -Eq -- 'grep -Ei?q' "$SAFE_POST"; then
    pass "credential matching uses the pipefail-safe counting form"
else
    fail "credential matching uses the pipefail-safe counting form" \
        "body_matches does not use grep -Eic redirected to /dev/null"
fi

binary_body="$TEST_TMP_DIR/binary-body.md"
printf '\377binary-without-a-nul\n' > "$binary_body"
: > "$GH_ARGS_LOG"
set +e
PATH="$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example issue-comment 7 "$binary_body" \
    > "$TEST_TMP_DIR/binary-output.log" 2>&1
binary_rc=$?
set -e
if [[ "$binary_rc" -eq 65 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "non-UTF-8 binary bodies fail closed"
else
    fail "non-UTF-8 binary bodies fail closed" \
        "non-UTF-8 body reached GitHub CLI"
fi

awk_failure_bin="$TEST_TMP_DIR/awk-failure-bin"
awk_failure_count="$TEST_TMP_DIR/awk-failure-count"
mkdir -p "$awk_failure_bin"
cat > "$awk_failure_bin/awk" <<'FAILING_AWK'
#!/usr/bin/env bash
set -euo pipefail
if [[ ! -e "$AWK_FAILURE_COUNT" ]]; then
    : > "$AWK_FAILURE_COUNT"
    exit 2
fi
exec "$REAL_AWK" "$@"
FAILING_AWK
chmod +x "$awk_failure_bin/awk"
export AWK_FAILURE_COUNT="$awk_failure_count"
REAL_AWK=$(command -v awk)
export REAL_AWK
: > "$GH_ARGS_LOG"
set +e
PATH="$awk_failure_bin:$MOCK_BIN_DIR:$PATH" "$SAFE_POST" \
    --repo octopus/example pr-comment 42 "$safe_body" \
    > "$TEST_TMP_DIR/awk-failure-output.log" 2>&1
awk_failure_rc=$?
set -e
if [[ "$awk_failure_rc" -eq 70 && ! -s "$GH_ARGS_LOG" ]]; then
    pass "sensitive-assignment scanner errors fail closed"
else
    fail "sensitive-assignment scanner errors fail closed" \
        "scanner failure returned $awk_failure_rc or reached GitHub CLI"
fi

signal_tmp="$TEST_TMP_DIR/signal-tmp"
signal_completion="$TEST_TMP_DIR/signal-completion"
mkdir -p "$signal_tmp"
: > "$GH_ARGS_LOG"
set +e
TMPDIR="$signal_tmp" GH_DELAY_SECONDS=2 GH_IGNORE_TERM=1 \
    GH_COMPLETION_LOG="$signal_completion" \
    PATH="$MOCK_BIN_DIR:$PATH" \
    "$SAFE_POST" --repo octopus/example pr-comment 42 "$safe_body" \
    > "$TEST_TMP_DIR/signal-output.log" 2>&1 &
signal_pid=$!
signal_ready=0
for _ in {1..100}; do
    if [[ -s "$GH_ARGS_LOG" ]]; then
        signal_ready=1
        break
    fi
    sleep 0.02
done
kill -TERM "$signal_pid" 2>/dev/null
wait "$signal_pid"
signal_rc=$?
set -e
signal_temp_count=$(find "$signal_tmp" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d '[:space:]')
if [[ "$signal_ready" -eq 1 && "$signal_rc" -eq 143 && "$signal_temp_count" == "0" && \
        ! -e "$signal_completion" ]]; then
    pass "TERM cleans snapshots and cancels the in-flight GitHub write"
else
    fail "TERM cleans snapshots and cancels the in-flight GitHub write" \
        "ready=$signal_ready, TERM returned $signal_rc with $signal_temp_count snapshots or a completed GitHub write"
fi

launch_race_env="$TEST_TMP_DIR/launch-race-env.sh"
launch_race_completion="$TEST_TMP_DIR/launch-race-completion"
cat > "$launch_race_env" <<'LAUNCH_RACE_ENV'
if [[ "${OCTOPUS_LAUNCH_RACE_TEST:-}" == "1" ]]; then
    set -T
    octopus_launch_race_triggered=0
    trap 'if [[ "$octopus_launch_race_triggered" == "0" && "$BASH_COMMAND" == "child_pid=\$!" ]]; then octopus_launch_race_triggered=1; kill -TERM "$$"; fi' DEBUG
fi
LAUNCH_RACE_ENV
: > "$GH_ARGS_LOG"
set +e
BASH_ENV="$launch_race_env" OCTOPUS_LAUNCH_RACE_TEST=1 \
    GH_DELAY_SECONDS=0.25 GH_IGNORE_TERM=1 \
    GH_COMPLETION_LOG="$launch_race_completion" \
    PATH="$MOCK_BIN_DIR:$PATH" \
    "$SAFE_POST" --repo octopus/example pr-comment 42 "$safe_body" \
    > "$TEST_TMP_DIR/launch-race-output.log" 2>&1
launch_race_rc=$?
for _ in {1..100}; do
    [[ -e "$launch_race_completion" ]] && break
    sleep 0.02
done
set -e
if [[ "$launch_race_rc" -eq 143 && ! -e "$launch_race_completion" ]]; then
    pass "TERM in the launch PID-assignment gap cancels the GitHub write"
else
    fail "TERM in the launch PID-assignment gap cancels the GitHub write" \
        "launch-gap TERM returned $launch_race_rc or left the GitHub write running"
fi

integration_plugin="$TEST_TMP_DIR/integration-plugin"
integration_args="$TEST_TMP_DIR/integration-args.log"
integration_body="$TEST_TMP_DIR/integration-body.log"
integration_source_path="$TEST_TMP_DIR/integration-source-path.log"
mkdir -p "$integration_plugin/scripts"
cat > "$integration_plugin/scripts/safe-gh-comment.sh" <<'INTEGRATION_HELPER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$INTEGRATION_ARGS"
last_argument=""
for argument in "$@"; do
    last_argument="$argument"
done
printf '%s\n' "$last_argument" > "$INTEGRATION_SOURCE_PATH"
if [[ "$last_argument" == "-" ]]; then
    cat > "$INTEGRATION_BODY"
else
    cp "$last_argument" "$INTEGRATION_BODY"
fi
if [[ -n "${INTEGRATION_DELAY_SECONDS:-}" ]]; then
    sleep "$INTEGRATION_DELAY_SECONDS"
fi
INTEGRATION_HELPER
chmod +x "$integration_plugin/scripts/safe-gh-comment.sh"
export INTEGRATION_ARGS="$integration_args"
export INTEGRATION_BODY="$integration_body"
export INTEGRATION_SOURCE_PATH="$integration_source_path"

# shellcheck source=../../scripts/lib/review.sh disable=SC1091
source "$PROJECT_ROOT/scripts/lib/review.sh"
log() { :; }
set +e
PLUGIN_DIR="$PROJECT_ROOT" CLAUDE_PLUGIN_ROOT="$integration_plugin" \
    review_post_safe_body octopus/example "$(<"$safe_body")" pr-comment 42 \
    > "$TEST_TMP_DIR/integration-output.log" 2>&1
integration_rc=$?
set -e
if [[ "$integration_rc" -eq 0 ]] && cmp -s "$safe_body" "$integration_body" && \
        grep -Fxq -- 'pr-comment' "$integration_args" && \
        grep -Fxq -- '-' "$integration_source_path"; then
    pass "review integration streams bodies through the configured helper"
else
    fail "review integration streams bodies through the configured helper" \
        "review_post_safe_body did not stream through the configured helper"
fi

interrupted_tmp="$TEST_TMP_DIR/interrupted-review-tmp"
mkdir -p "$interrupted_tmp"
: > "$integration_source_path"
set +e
TMPDIR="$interrupted_tmp" INTEGRATION_DELAY_SECONDS=2 \
    PLUGIN_DIR="$PROJECT_ROOT" CLAUDE_PLUGIN_ROOT="$integration_plugin" \
    review_post_safe_body octopus/example "$(<"$safe_body")" pr-comment 42 \
    > "$TEST_TMP_DIR/interrupted-review-output.log" 2>&1 &
interrupted_pid=$!
interrupted_ready=0
for _ in {1..100}; do
    if [[ -s "$integration_source_path" ]]; then
        interrupted_ready=1
        break
    fi
    sleep 0.02
done
kill -TERM "$interrupted_pid" 2>/dev/null
wait "$interrupted_pid" 2>/dev/null
interrupted_rc=$?
set -e
interrupted_file_count=$(find "$interrupted_tmp" -mindepth 1 -type f | wc -l | tr -d '[:space:]')
if [[ "$interrupted_ready" -eq 1 && "$interrupted_rc" -eq 143 && \
        "$interrupted_file_count" == "0" ]]; then
    pass "interrupted review posting leaves no caller-owned body file"
else
    fail "interrupted review posting leaves no caller-owned body file" \
        "ready=$interrupted_ready, interrupted review returned $interrupted_rc with $interrupted_file_count caller files"
fi

batch_findings="$TEST_TMP_DIR/batch-findings.json"
jq -n --arg blocked_detail "$(printf '%s=%s' SERVICE_TOKEN hunter2)" \
    '{findings:[
      {file:"src/blocked.sh",line:7,severity:"normal",title:"Blocked finding",detail:$blocked_detail},
      {file:"src/safe.sh",line:11,severity:"nit",title:"Safe finding",detail:"Use a local variable."}
    ]}' > "$batch_findings"
batch_calls="$TEST_TMP_DIR/batch-calls.log"
batch_posted="$TEST_TMP_DIR/batch-posted.log"
: > "$batch_calls"
: > "$batch_posted"
# shellcheck disable=SC2329 # Invoked indirectly by post_inline_comments.
gh() {
    if [[ "$1 $2" == "repo view" ]]; then
        printf '%s\n' 'octopus/example'
    elif [[ "$1 $2" == "pr view" ]]; then
        printf '%s\n' 'deadbeef'
    fi
}
# shellcheck disable=SC2329 # Invoked indirectly by post_inline_comments.
review_post_safe_body() {
    local body="$2"
    local operation="$3"
    printf '%s\n' "$operation" >> "$batch_calls"
    if [[ "$operation" == "pr-review" || "$body" == *'SERVICE_TOKEN='* ]]; then
        return 65
    fi
    printf '%s\n' "$body" >> "$batch_posted"
}
set +e
post_inline_comments 42 "$batch_findings" \
    > "$TEST_TMP_DIR/batch-output.log" 2>&1
batch_rc=$?
set -e
batch_call_count=$(wc -l < "$batch_calls" | tr -d '[:space:]')
if [[ "$batch_rc" -ne 0 && "$batch_call_count" == "3" ]] && \
        grep -Eq -- 'Safe finding' "$batch_posted" && \
        ! grep -Eq -- 'SERVICE_TOKEN=' "$batch_posted"; then
    pass "blocked review comments do not suppress later safe findings"
else
    fail "blocked review comments do not suppress later safe findings" \
        "batch returned $batch_rc after $batch_call_count calls without safely continuing"
fi
unset -f gh review_post_safe_body

if grep -Eq -- 'safe-gh-comment\.sh' "$PROJECT_ROOT/scripts/lib/review.sh" && \
        ! grep -Eq -- 'gh pr review .*--body|-f body=' "$PROJECT_ROOT/scripts/lib/review.sh" && \
        ! grep -Eq -- '\[\[ "\$response".*post_inline_comments.*\|\| render_terminal_report' \
            "$PROJECT_ROOT/scripts/lib/review.sh"; then
    pass "production review posting uses the safe helper"
else
    fail "production review posting uses the safe helper" \
        "scripts/lib/review.sh still bypasses the safe helper"
fi

instruction_files_ok=0
for instruction_file in "$PROJECT_ROOT/AGENTS.md" "$PROJECT_ROOT/CLAUDE.md" \
        "$PROJECT_ROOT/RTK.md"; do
    if grep -Eq -- 'safe-gh-comment\.sh' "$instruction_file"; then
        instruction_files_ok=$((instruction_files_ok + 1))
    fi
done
if [[ "$instruction_files_ok" -eq 3 ]]; then
    pass "repository agent instructions require the safe helper"
else
    fail "repository agent instructions require the safe helper" \
        "one or more agent instruction files omit the safe posting contract"
fi

unsafe_post_pattern='gh[[:space:]]+(pr|issue)[[:space:]]+(create|comment|review)([^\n]*\n){0,12}[^\n]*["\x27]?(--body-file|--body|-b)["\x27]?([ =]|$)|gh[[:space:]]+api([^\n]*\n){0,12}[^\n]*((["\x27]?(-f|-F)["\x27]?[[:space:]]*|["\x27]?(--field|--raw-field)["\x27]?([[:space:]]+|=))["\x27]?body=|--input([ =]|$))'
unsafe_skill_posts=""
if multiline_match "$unsafe_post_pattern" \
        "$PROJECT_ROOT/.claude/skills" "$PROJECT_ROOT/skills"; then
    unsafe_skill_posts="found"
fi
api_alias_matches=0
for api_alias_fixture in \
        'gh api repos/example/issues/1/comments -F body=value' \
        'gh api repos/example/issues/1/comments --raw-field body=value' \
        'gh api repos/example/issues/1/comments --field=body=value' \
        'gh api repos/example/issues/1/comments --raw-field=body=value' \
        'gh api repos/example/issues/1/comments -f "body=$body"' \
        "gh api repos/example/issues/1/comments -F 'body=value'" \
        'gh api repos/example/issues/1/comments --field="body=value"' \
        "gh api repos/example/issues/1/comments --raw-field='body=value'" \
        'gh api repos/example/issues/1/comments "-f" "body=$body"' \
        'gh pr comment 42 "--body" "$body"'; do
    if printf '%s\n' "$api_alias_fixture" | multiline_match "$unsafe_post_pattern"; then
        api_alias_matches=$((api_alias_matches + 1))
    fi
done
safe_skill_files=0
for skill_root in "$PROJECT_ROOT/.claude/skills" "$PROJECT_ROOT/skills"; do
    for skill_name in skill-code-review skill-staged-review flow-deliver skill-finish-branch skill-intake; do
        if grep -Eq -- 'safe-gh-comment\.sh' "$skill_root/$skill_name/SKILL.md"; then
            safe_skill_files=$((safe_skill_files + 1))
        fi
    done
done
if [[ "$api_alias_matches" -eq 10 ]]; then
    pass "unsafe-posting detector matches all known inline body forms"
else
    fail "unsafe-posting detector matches all known inline body forms" \
        "matched $api_alias_matches of 10 detector fixtures"
fi
if [[ -z "$unsafe_skill_posts" && "$safe_skill_files" -eq 10 ]]; then
    pass "GitHub-posting skill guidance uses the safe helper"
else
    fail "GitHub-posting skill guidance uses the safe helper" \
        "unsafe posts=${unsafe_skill_posts:-none}; safe files=$safe_skill_files of 10"
fi

unknown_write_guidance=0
for workflow_file in \
        "$PROJECT_ROOT/.claude/skills/flow-deliver/SKILL.md" \
        "$PROJECT_ROOT/.claude/skills/skill-code-review/SKILL.md" \
        "$PROJECT_ROOT/.claude/skills/skill-staged-review/SKILL.md"; do
    if grep -Fc -- 'GitHub write state is unknown' "$workflow_file" >/dev/null && \
            grep -Eq -- 'gh pr view .*--comments' "$workflow_file"; then
        unknown_write_guidance=$((unknown_write_guidance + 1))
    fi
done
finish_branch_file="$PROJECT_ROOT/.claude/skills/skill-finish-branch/SKILL.md"
if grep -Fc -- 'GitHub write state is unknown' "$finish_branch_file" >/dev/null && \
        grep -Eq -- 'gh pr list .*--head' "$finish_branch_file"; then
    unknown_write_guidance=$((unknown_write_guidance + 1))
fi
if [[ "$unknown_write_guidance" -eq 4 ]]; then
    pass "skill workflows verify unknown GitHub write state before retrying"
else
    fail "skill workflows verify unknown GitHub write state before retrying" \
        "only $unknown_write_guidance of 4 write paths document a read-before-retry check"
fi

if grep -Eq -- 'PR_TITLE=' "$finish_branch_file" && \
        grep -Ec -- 'pr-create "[$]PR_TITLE"' "$finish_branch_file" >/dev/null && \
        ! grep -Eq -- '\[(What changed|Why it changed|description)\]' "$finish_branch_file"; then
    pass "finish-branch PR creation uses completed title and body values"
else
    fail "finish-branch PR creation uses completed title and body values" \
        "finish-branch still sends placeholder-shaped PR content"
fi

streaming_guidance_files=0
for streaming_file in "$PROJECT_ROOT/scripts/release.sh" \
        "$PROJECT_ROOT/.claude/skills/flow-deliver/SKILL.md" \
        "$PROJECT_ROOT/.claude/skills/skill-code-review/SKILL.md" \
        "$PROJECT_ROOT/.claude/skills/skill-staged-review/SKILL.md" \
        "$PROJECT_ROOT/.claude/skills/skill-finish-branch/SKILL.md"; do
    if grep -Eq -- 'safe-gh-comment\.sh' "$streaming_file" && \
            grep -Eq -- '<<<' "$streaming_file" && \
            ! grep -Eq -- 'mktemp .*octopus-(release-pr|deliver-report|review-body|staged-review|pr-body)' \
                "$streaming_file"; then
        streaming_guidance_files=$((streaming_guidance_files + 1))
    fi
done
if [[ "$streaming_guidance_files" -eq 5 ]]; then
    pass "release and skill posting leaves no caller-owned body files"
else
    fail "release and skill posting leaves no caller-owned body files" \
        "only $streaming_guidance_files of 5 posting paths stream directly to the helper"
fi

if multiline_match '\n___\n\*Multi-AI validation by Claude Octopus' \
        "$PROJECT_ROOT/.claude/skills/flow-deliver/SKILL.md" && \
        multiline_match '\n___\n\*Multi-AI validation by Claude Octopus' \
        "$PROJECT_ROOT/.claude/skills/flow-deliver/flow-deliver.tmpl" && \
        multiline_match '\n___\n\*Multi-AI validation by Claude Octopus' \
        "$PROJECT_ROOT/skills/flow-deliver/SKILL.md"; then
    pass "source and portable delivery skills preserve the footer separator"
else
    fail "source and portable delivery skills preserve the footer separator" \
        "delivery footer separator was lost during skill generation"
fi

if grep -Eq -- 'safe-gh-comment\.sh' "$PROJECT_ROOT/scripts/release.sh" && \
        ! multiline_match 'gh pr create([^\n]*\n){0,12}[^\n]*--body([ =]|$)' \
            "$PROJECT_ROOT/scripts/release.sh"; then
    pass "release PR creation uses the outbound credential gate"
else
    fail "release PR creation uses the outbound credential gate" \
        "scripts/release.sh still creates a PR with an inline body"
fi

test_summary
