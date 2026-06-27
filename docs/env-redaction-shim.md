# env Secret-Redaction Shim

A drop-in replacement for `env` that redacts secret values when invoked inside an
LLM coding harness (Claude Code, Gemini), while behaving exactly like the real
`env` in a normal human shell.

## Goal

When an LLM agent runs `env` to inspect the environment, it will inevitably print
your secrets into the session transcript. This shim intercepts that: the variable
name still prints, but the value becomes `<REDACTED>`. Outside an LLM session the
shim is a transparent passthrough to `/usr/bin/env`, so interactive use is
unchanged.

## Mechanism: a PATH shim, not a shell function

The shim is a single executable named `env` placed in `~/bin`, which sits ahead of
`/usr/bin` on `PATH`. Because `PATH` is inherited by non-interactive shells and
subprocesses, a bare `env` call resolves to the shim in every context, including
the non-interactive Bash tool an LLM harness uses.

A shell function (`function env(){ ... }`) was tried first and does not work for
this threat model, for four independent reasons:

1. It was never sourced anywhere.
2. It pointed at a `~/bin/env.py` that did not exist on disk.
3. A `.zshrc` function only loads in interactive shells. The LLM Bash tool runs
   non-interactive shells, which never read `.zshrc`, so the function is absent in
   exactly the context that matters.
4. The installer linked it as `~/bin/env.py` (wrong name). Nothing ever invokes
   `env.py`, so it shadowed nothing.

The PATH shim defeats all four at once.

## Files and install

- Source of truth: `helpful/bin/env.py` in `git@github.com:scottidler/helpful`.
- Install declaration: the `scottidler/helpful:` block in
  `dotfiles/manifest.yml`, which links `bin/env.py` to `~/bin/env`.
- New machine flow: clone `dotfiles` and `helpful`, run `manifest`. It recreates
  `~/bin/env` pointing at `helpful/bin/env.py`. The shim is live immediately
  because `~/bin` already precedes `/usr/bin` on `PATH`.

## Detection logic

`in_llm_session()` returns true when either:

- `CLAUDECODE=1` is set in the environment, or
- `/proc/<ppid>/cmdline` starts with `claude` or `gemini`.

Per-variable redaction fires when either signal matches:

- Name regex: SECRET, TOKEN, KEY, PASSWORD, AUTH, CREDENTIAL, PRIVATE, CERT,
  SIGNING, BEARER, HMAC, SALT, ACCESS, REFRESH, CLIENT_SECRET, and similar.
- Shannon entropy at or above 3.8 bits/char on values of length 16 or more.

Tuning knobs at the top of `env.py`: `ENTROPY_THRESHOLD` and `MIN_LENGTH`.

## Behavior matrix

| Invocation                | Outside LLM session        | Inside LLM session            |
|---------------------------|----------------------------|-------------------------------|
| `env`                     | real listing (full values) | listing with secrets redacted |
| `env -r` / `env --redact` | listing, redacted (forced) | listing, redacted             |
| `env FOO=bar cmd`         | passthrough to real env    | passthrough to real env       |
| `/usr/bin/env ...`        | real env (shebangs safe)   | real env (shebangs safe)      |

## Verified live

- Bare `env` resolves to `~/bin/env` in a fresh non-interactive shell.
- Inside the harness (`CLAUDECODE=1`): `ANTHROPIC_API_KEY`, `GITHUB_PAT_*`, etc.
  print as `<REDACTED>`.
- Outside a harness: full values shown, identical to real `env`.
- `env FOO=bar cmd` passthrough and `/usr/bin/env` shebangs unaffected.

## Known gaps and follow-ups

1. Flags-only invocations are mis-handled inside a session. `env --help`,
   `env --version`, `env -0`/`--null` start with `-`, so the passthrough check
   (which only fires on a bareword or `NAME=VALUE` argument) skips them, and the
   shim falls into the redacted listing branch. Outside a session these pass
   through correctly. Desired fix: pass non-listing flags (`--help`, `--version`)
   through to real `env` even inside a session, while keeping listing variants
   (`-0`, `--null`) on the redaction path so they cannot be used to dump raw
   values.
2. Codex is not yet detected. `in_llm_session()` matches `claude`/`gemini` and
   `CLAUDECODE` only. Add a Codex env var or cmdline check if you use it.
3. Other dump vectors bypass the shim entirely: `printenv`,
   `cat /proc/self/environ`, `declare -x`, and a hard-coded `/usr/bin/env` with no
   command. A `printenv` shim would be the highest-value addition.
4. Direct shell expansion bypasses the shim and CANNOT be shimmed. `echo "$SECRET"`,
   `printf '%s' "$SECRET"`, and presence-checks like `echo "${VAR:-MISSING}"` expand
   the value via the shell builtin before any binary runs, so there is no executable
   on `PATH` to intercept. This is the vector that leaked `ANTHROPIC_API_KEY` and
   `OPENAI_API_KEY` on 2026-06-27 (see History). The only mitigation is discipline,
   not a shim: never use `${VAR:-...}` for a presence check (it substitutes the value
   when set); use `${VAR:+present}` alone, or `[ -n "$VAR" ] && echo present`. This
   rule is also codified in the agent's env-secrets memory.

## History

- Logic authored in `helpful/bin/env.py` (commit `move env redaction to
  bin/env.py, thin shell wrapper to env.sh`).
- Enablement completed 2026-06-27: installed as `~/bin/env`, manifest retargeted
  to `~/bin/env`, dead function shim (`helpful/env.sh`) and the old
  always-redacting copy (`~/bin/env.sh`) removed.
- 2026-06-27 leak: an agent ran `echo "...: ${ANTHROPIC_API_KEY:+present}${ANTHROPIC_API_KEY:-MISSING}"`
  (and the same for `OPENAI_API_KEY`) to check provider availability. The broken
  `${VAR:-MISSING}` idiom expanded the real values, and direct shell expansion does
  not pass through the shim. Both keys were exposed and rotated. Recorded as gap 4.
