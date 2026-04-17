#!/usr/bin/env python3
"""
env - like `env`, but auto-redacts secrets when inside an LLM session.

Redaction uses two signals:
  1. Name pattern   - var name matches known secret keywords
  2. Shannon entropy - value looks random enough to be a secret
     (only applied to values >= MIN_LENGTH chars to avoid false positives)

Flags:
  -r / --redact   force redaction regardless of session context

Tune ENTROPY_THRESHOLD and MIN_LENGTH below if needed.
"""

import math
import os
import re
import sys

# --- tuning knobs -----------------------------------------------------------
ENTROPY_THRESHOLD = 3.8  # bits/char; typical secrets >= 4.0, paths/words < 3.5
MIN_LENGTH = 16           # skip entropy check on very short values
# ----------------------------------------------------------------------------

SECRET_NAME_RE = re.compile(
    r"(SECRET|TOKEN|KEY|PASSWORD|PASSWD|PASS|CREDENTIAL|CREDENTIALS"
    r"|AUTH|APIKEY|API_KEY|PRIVATE|CERT|SIGNING|BEARER|HMAC|SALT"
    r"|ACCESS|REFRESH|CLIENT_SECRET|PRIVATE_KEY)",
    re.IGNORECASE,
)


def shannon_entropy(s: str) -> float:
    if not s:
        return 0.0
    length = len(s)
    freq: dict[str, int] = {}
    for ch in s:
        freq[ch] = freq.get(ch, 0) + 1
    return -sum((c / length) * math.log2(c / length) for c in freq.values())


def should_redact(name: str, value: str) -> bool:
    if SECRET_NAME_RE.search(name):
        return True
    if len(value) >= MIN_LENGTH and shannon_entropy(value) >= ENTROPY_THRESHOLD:
        return True
    return False


def in_llm_session() -> bool:
    if os.environ.get("CLAUDECODE") == "1":
        return True
    try:
        with open(f"/proc/{os.getppid()}/cmdline", "rb") as f:
            cmdline = f.read().replace(b"\x00", b" ").decode(errors="replace")
        return bool(re.match(r"(claude|gemini)", cmdline))
    except OSError:
        return False


def main() -> None:
    args = sys.argv[1:]
    redact = False
    rest: list[str] = []

    for arg in args:
        if arg in ("-r", "--redact"):
            redact = True
        else:
            rest.append(arg)

    # Pass-through: has a non-flag, non-assignment arg -> running a command
    if not redact:
        for arg in rest:
            if arg.startswith("-") or "=" in arg:
                continue
            os.execvp("/usr/bin/env", ["/usr/bin/env"] + rest)

    # Listing mode: redact if forced or inside an LLM session
    if redact or in_llm_session():
        for key, value in sorted(os.environ.items()):
            display = "<REDACTED>" if should_redact(key, value) else value
            print(f"{key}={display}")
    else:
        os.execvp("/usr/bin/env", ["/usr/bin/env"] + rest)


if __name__ == "__main__":
    main()
