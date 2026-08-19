#!/usr/bin/env bash
# Reports whether this repository's documented AI workflow is operational on this machine.
# Every check runs before exiting, so one failure does not hide the rest — hence no `set -e`.
#
# The governing rule for every check below: a check that cannot measure its subject must FAIL,
# never pass. An `ok` has to mean "I looked and it was fine", not "I found nothing to look at".
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -n "$ROOT_DIR" ] && [ -d "$ROOT_DIR" ] || { echo "cannot resolve repository root" >&2; exit 1; }
BIN_DIR="$ROOT_DIR/node_modules/.bin"
FAILED=0

# This script is shared verbatim across every ForgeKit-family repository, so everything
# stack-specific it needs is declared by the repository rather than written in here.
# package.json:
#
#   "forgekit": {
#     "sourceGlobs":      ["*.swift"],        # what counts as source, for index freshness
#     "requiredTools":    ["xcodebuild"],     # machine-level tools this stack cannot work without
#     "nodeSubprojects":  ["app"]             # nested npm projects with their own scripts and bins
#   }
#
# Read with a while-loop rather than `mapfile`: stock macOS ships bash 3.2, which has no
# mapfile, and the shebang resolves there on a machine without a newer bash installed.
read_declared() {
  node -e '
    const fs = require("fs");
    let cfg = {};
    try { cfg = (JSON.parse(fs.readFileSync(process.argv[1], "utf8")).forgekit) || {}; } catch (e) {}
    const value = cfg[process.argv[2]];
    if (Array.isArray(value)) process.stdout.write(value.filter(Boolean).join("\n"));
  ' "$ROOT_DIR/package.json" "$1" 2>/dev/null
}

SOURCE_GLOBS=(); REQUIRED_TOOLS=(); NODE_SUBPROJECTS=()
while IFS= read -r line; do [ -n "$line" ] && SOURCE_GLOBS+=("$line"); done < <(read_declared sourceGlobs)
while IFS= read -r line; do [ -n "$line" ] && REQUIRED_TOOLS+=("$line"); done < <(read_declared requiredTools)
while IFS= read -r line; do [ -n "$line" ] && NODE_SUBPROJECTS+=("$line"); done < <(read_declared nodeSubprojects)

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n        fix: %s\n' "$1" "$2"; FAILED=1; }

# BSD stat and GNU stat spell mtime differently. Decide once rather than relying on one
# form failing quietly into the other — GNU's `-f` means --file-system and prints output
# of its own, which a fallback chain would silently mix into the result.
if stat -f %m "$ROOT_DIR" >/dev/null 2>&1; then
  STAT_MTIME=(-f %m)
else
  STAT_MTIME=(-c %Y)
fi

echo "==> Declared tools"
for tool in openspec codegraph grillme; do
  if [ -x "$BIN_DIR/$tool" ]; then
    pass "$tool"
  else
    fail "$tool is not installed" "pnpm install"
  fi
done

# The stack's own tools, resolved against PATH — unlike the workflow tools above, and unlike
# the citation check further down, which resolves against the declared toolchain precisely to
# avoid asking PATH anything. The difference is not an inconsistency: a compiler or a project
# generator cannot live in node_modules, so PATH is the only place it can be. What that costs
# is a weaker guarantee, and the report says which kind of answer it is giving.
if [ "${#REQUIRED_TOOLS[@]}" -eq 0 ]; then
  echo "  --    no stack tools declared (package.json: forgekit.requiredTools)"
else
  for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      pass "$tool (on PATH)"
    else
      fail "$tool is declared by this repository but is not on PATH" \
           "install $tool, or drop it from forgekit.requiredTools in package.json"
    fi
  done
fi

echo "==> Workflow configuration"
if [ ! -x "$BIN_DIR/openspec" ]; then
  fail "cannot read workflow configuration" "pnpm install"
else
  probe="preflight-probe-$$"
  probe_dir="$ROOT_DIR/openspec/changes/$probe"
  trap 'rm -rf "$probe_dir"' EXIT
  if "$BIN_DIR/openspec" new change "$probe" >/dev/null 2>&1; then
    rules=$("$BIN_DIR/openspec" instructions proposal --change "$probe" --json 2>/dev/null \
      | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).rules?.length ?? 0' 2>/dev/null || echo 0)
    guidance=$("$BIN_DIR/openspec" instructions apply --change "$probe" --json 2>/dev/null \
      | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).operationGuidance?.length ?? 0' 2>/dev/null || echo 0)
    rm -rf "$probe_dir"
    if [ "$rules" -gt 0 ]; then
      pass "proposal rules readable ($rules)"
    else
      fail "openspec/config.yaml yields no proposal rules" \
           "check rules: in openspec/config.yaml — a plain scalar containing ': ' silently empties the block"
    fi
    if [ "$guidance" -gt 0 ]; then
      pass "apply guidance readable ($guidance)"
    else
      fail "openspec/config.yaml yields no apply guidance" \
           "check operations.apply.guidance in openspec/config.yaml"
    fi
  else
    fail "openspec could not create a probe change" "run: $BIN_DIR/openspec new change probe"
  fi
fi

echo "==> CodeGraph index"
INDEX="$ROOT_DIR/.codegraph/codegraph.db"
if [ ! -f "$INDEX" ]; then
  # A project that has never been indexed needs `init`; `index` refuses with
  # "CodeGraph not initialized". This is the branch a freshly generated product lands on,
  # so naming the wrong command here would misdirect exactly the reader who needs it.
  fail "no CodeGraph index" "pnpm exec codegraph init"
else
  # Compare against the source the index describes, not against HEAD. Committing modifies no
  # source file, so anchoring on commit time would report a correct index as stale after every
  # commit — and a check that cries wolf is one people learn to skip.
  #
  # Known limit: deleting a source file changes no mtime, so a deletion alone does not mark
  # the index stale.
  index_epoch=$(stat "${STAT_MTIME[@]}" "$INDEX" 2>/dev/null)
  if [ "${#SOURCE_GLOBS[@]}" -eq 0 ]; then
    # `git ls-files --` with no pathspec lists every tracked file, so the comparison would
    # still produce a number — a wrong one, moved by a README edit. Quietly measuring
    # something other than source is worse than measuring nothing, so this is a failure.
    fail "no source globs declared, so index freshness cannot be measured" \
         "add forgekit.sourceGlobs to package.json"
  else
    newest_src=$(git -C "$ROOT_DIR" ls-files -z -- "${SOURCE_GLOBS[@]}" 2>/dev/null \
      | xargs -0 stat "${STAT_MTIME[@]}" 2>/dev/null | sort -rn | head -1)
    if [ -z "$index_epoch" ] || [ -z "$newest_src" ]; then
      # Enumeration produced nothing — no git, no stat, or the declared globs match no tracked
      # file. Whatever the cause, the freshness of the index is unknown, and unknown is not ok.
      fail "cannot determine whether the index is current" \
           "check git and stat, and that forgekit.sourceGlobs matches tracked files, then: pnpm exec codegraph index"
    elif [ "$index_epoch" -lt "$newest_src" ]; then
      fail "index is older than the newest source file — impact analysis from it would be out of date" \
           "pnpm exec codegraph index"
    else
      pass "index present and reflects current source"
    fi
  fi
fi

echo "==> Git hooks"
hooks_path=$(git -C "$ROOT_DIR" config --get core.hooksPath || true)
hooks_abs=""
[ -n "$hooks_path" ] && hooks_abs=$(cd "$ROOT_DIR" && cd "$hooks_path" 2>/dev/null && pwd)
expected_abs=$(cd "$ROOT_DIR/.githooks" 2>/dev/null && pwd)
if [ -z "$hooks_abs" ] || [ "$hooks_abs" != "$expected_abs" ]; then
  fail "repository hooks are not enabled" "git config core.hooksPath .githooks"
else
  pass "core.hooksPath -> .githooks"
  # Git ignores a non-executable hook without saying so. `dotnet new` does not carry the
  # executable bit, so in a generated product every hook arrives unable to fire, silently.
  for hook in "$ROOT_DIR/.githooks"/*; do
    [ -f "$hook" ] || continue
    if [ -x "$hook" ]; then
      pass "$(basename "$hook") is executable"
    else
      fail "$(basename "$hook") is not executable — git will ignore it without reporting anything" \
           "chmod +x .githooks/$(basename "$hook")"
    fi
  done
fi

echo "==> Capabilities cited by workflow instructions"
# Sort by version and take the newest, so a stale cached plugin version is not what gets
# validated against.
PLUGIN_SKILLS=$(ls -d "$HOME"/.claude/plugins/cache/*/superpowers/*/skills 2>/dev/null | sort -V | tail -1)

if [ -z "$PLUGIN_SKILLS" ]; then
  fail "Superpowers plugin is not installed" \
       "open Claude Code in this repository and approve the plugin declared in .claude/settings.json"
fi

INSTRUCTION_FILES=("$ROOT_DIR/AGENTS.md" "$ROOT_DIR/openspec/config.yaml")

# Every backticked token in EVERY cell of every markdown table row, plus structured literals
# and document paths cited anywhere in either instruction file.
#
# Reading every cell rather than a fixed column is deliberate: fixing on one column skips a
# capability cited in another, which is the same "passes because it never looked" hole this
# check exists to close. An unrecognised token fails rather than being ignored, because the
# defect this was written for -- a stale `grilling` -- carries no prefix a pattern could match.
cited=$(
  {
    awk -F'|' '/^[[:space:]]*\|/ { for (i = 2; i <= NF; i++) print $i }' "$ROOT_DIR/AGENTS.md"
    grep -ohE '`(superpowers:[a-z-]+|/opsx:[a-z]+|grillme|codegraph_explore)`' "${INSTRUCTION_FILES[@]}"
    grep -ohE '`(docs/[A-Za-z0-9._/-]*|[A-Za-z0-9._/-]+\.md)`' "${INSTRUCTION_FILES[@]}"
  } | grep -oE '`[^`]+`' | tr -d '`' | sort -u
)

while IFS= read -r cap; do
  [ -z "$cap" ] && continue
  case "$cap" in
    superpowers:*)
      if [ -z "$PLUGIN_SKILLS" ]; then
        : # already reported once, as its own cause
      elif [ -d "$PLUGIN_SKILLS/${cap#superpowers:}" ]; then
        pass "$cap"
      else
        fail "$cap does not resolve" "correct the skill name in AGENTS.md or openspec/config.yaml"
      fi
      ;;
    /opsx:*)
      if [ -f "$ROOT_DIR/.claude/commands/opsx/${cap#/opsx:}.md" ]; then
        pass "$cap"
      else
        fail "$cap does not resolve" "correct the command name in AGENTS.md"
      fi
      ;;
    /code-review)
      pass "$cap (built-in)"
      ;;
    codegraph_explore)
      if [ -f "$ROOT_DIR/.mcp.json" ] && grep -q '"codegraph"' "$ROOT_DIR/.mcp.json"; then
        pass "$cap"
      else
        fail "$cap has no declared MCP server" "declare codegraph in .mcp.json"
      fi
      ;;
    grillme)
      if [ -x "$BIN_DIR/grillme" ]; then
        pass "$cap"
      else
        fail "$cap does not resolve" "pnpm install"
      fi
      ;;
    "pnpm "*|"npm "*)
      # A cited package script rots the same way a skill name does — but only a script can.
      # `pnpm install` and `pnpm exec …` are built-in subcommands with nothing to resolve, and
      # a nested project's scripts live in its own package.json, not the workflow package.
      sub="${cap#* }"
      # `pnpm run x` is the canonical long form of `pnpm x`; without unwrapping it the explicit
      # spelling of a broken citation is the one spelling that goes unchecked.
      [ "${sub%% *}" = "run" ] && sub="${sub#run }"
      first="${sub%% *}"
      case "$first" in
        exec)
          # Resolve what is being executed rather than waving the whole phrase through.
          # `dlx` is excluded deliberately: it exists to run a package that is NOT installed
          # locally, so requiring it in node_modules/.bin would invert its meaning.
          target="${sub#* }"
          target="${target%% *}"
          if [ -z "$target" ] || [ "$target" = "$first" ] || [ -x "$BIN_DIR/$target" ]; then
            pass "$cap"
          else
            fail "$cap runs a binary that is not installed" "pnpm install"
          fi
          ;;
        dlx|install|add|remove|update|why|store|approve-builds)
          pass "$cap (pnpm subcommand)"
          ;;
        *)
          pkg_paths=("$ROOT_DIR/package.json")
          if [ "${#NODE_SUBPROJECTS[@]}" -gt 0 ]; then
            for sub in "${NODE_SUBPROJECTS[@]}"; do pkg_paths+=("$ROOT_DIR/$sub/package.json"); done
          fi
          if node -e 'const n=process.argv[1];
                      const has=p=>{try{return !!(require(p).scripts||{})[n]}catch(e){return false}};
                      process.exit(process.argv.slice(2).some(has)?0:1)' \
               "$first" "${pkg_paths[@]}" 2>/dev/null; then
            pass "$cap"
          else
            fail "$cap names no script in package.json or any declared subproject" \
                 "add the script, or correct the citation"
          fi
          ;;
      esac
      ;;
    *" "*)
      # A phrase, not a citation — `git checkout upstream/main -- api/Anvil`, `chmod +x
      # .githooks/*`. Documentation backticks these, and the path arm below would otherwise
      # resolve them as filenames and fail. Commands with a package manager are handled above.
      :
      ;;
    */*|*.md)
      # A document pointer rots the same way a stale skill name does.
      if [ -e "$ROOT_DIR/$cap" ]; then
        pass "$cap"
      else
        fail "$cap does not exist" "correct the path in AGENTS.md, or restore the document"
      fi
      ;;
    *[![:lower:][:digit:]-]*)
      # Not shaped like a capability name — a type, an identifier, a phrase. Documentation
      # legitimately backticks these, and failing on them would make preflight red on ordinary
      # doc edits, which is the other way a check gets ignored. Say nothing.
      #
      # POSIX classes, not `[!a-z0-9-]`: under en_US.UTF-8 collation the a-z range spans
      # aAbBcC..., so uppercase falls INSIDE it and `ISoftDelete` reached the fail arm.
      :
      ;;
    *)
      # An all-lowercase bare word is the shape of a capability citation — and of a tool name.
      # Resolve it against the toolchain this repository declares, never against PATH: consulting
      # PATH would answer "does something by this name exist on this machine", which passes for a
      # shell builtin, passes for any coincidental binary, and gives a different verdict on a
      # fresh clone than on the author's laptop. What is left is the shape of the stale
      # `grilling` this was written for, resolving to nothing the repository provides.
      resolved=""
      [ -x "$BIN_DIR/$cap" ] && resolved=1
      if [ -z "$resolved" ] && [ "${#NODE_SUBPROJECTS[@]}" -gt 0 ]; then
        for sub in "${NODE_SUBPROJECTS[@]}"; do
          [ -x "$ROOT_DIR/$sub/node_modules/.bin/$cap" ] && { resolved=1; break; }
        done
      fi
      if [ -n "$resolved" ]; then
        pass "$cap (declared tool)"
      else
        fail "\`$cap\` is not in the declared toolchain" \
             "correct it in AGENTS.md, or declare it in package.json"
      fi
      ;;
  esac
done < <(printf '%s\n' "$cited")

echo
if [ "$FAILED" -eq 0 ]; then
  echo "Workflow is operational."
else
  echo "Workflow is not operational. Fix the items above and re-run." >&2
fi
exit "$FAILED"
