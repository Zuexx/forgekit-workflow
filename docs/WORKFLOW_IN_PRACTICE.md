# The ForgeKit Workflow in Practice

How a change actually moves through a ForgeKit-family repository, and what each tool is for.

## Two loops, and who owns which

**OpenSpec** decides *what may be built and whether it counts as done*.
**Superpowers** decides *how it gets built and whether it was built correctly*.

Neither knows the other exists. The seam between them is the `apply` and `archive` guidance in
`openspec/config.yaml` — ten entries and three, all shared from `openspec/rules.yaml`.

Feature-level tasks live in `openspec/changes/<slug>/tasks.md`. Minute-level steps live in the
Superpowers plan, which cites those task ids under an `## OpenSpec Coverage` heading. The two
granularities must stay apart; collapsing them makes the citation meaningless.

Note the vocabulary trap: Superpowers' own guidance says "each step is one action (2–5 minutes)",
under a heading that says *Task* Granularity. It is describing **steps**. A *task* is sized by a
different rule entirely — "the smallest unit that carries its own test cycle and is worth a fresh
reviewer's gate."

So there are three levels, not two:

| Level | Defined by | Granularity |
|---|---|---|
| OpenSpec task (`1.1`, `2.1`) | `openspec/config.yaml` | a unit of the change a reviewer would recognise |
| Plan task | Superpowers | carries its own test cycle and review gate |
| Plan step | Superpowers | one action, 2–5 minutes |

## The sequence

```
grillme            settle scope with a human, one decision question at a time
  ↓                (only when the request is too vague to state what it excludes)
/opsx:propose      proposal, delta specs, design, tasks
  ↓
writing-plans      expand feature-level tasks into minute-level steps
  ↓
implement          subagent-driven if its decision tree routes there, otherwise manual
  ↓
requesting-code-review
  ↓
/opsx:archive      verify against the spec deltas, not the task checkboxes
```

## The tools

**CodeGraph** answers "what does this change affect" from a pre-built symbol graph, including
dynamic-dispatch hops that grep cannot follow. The first planning rule requires the Impact
section of a proposal to be grounded in it rather than in an estimate. It indexes symbols, so a
contract addressed by string — an HTTP header, a notification name, a config key — is invisible
to it and needs a literal search of its own, which the Impact section must say it did.

**The pre-push hook** resolves the OpenSpec task ids a plan claims to cover and names every
number it could not read. It exists because nothing else validates that link. It was, for a long
time, unable to fire at all: `dotnet new` does not carry the executable bit, and git ignores a
non-executable hook without reporting anything — so every generated product had a hook that had
never run.

**preflight** answers whether any of this actually works on this machine: are the declared tools
installed, does `openspec/config.yaml` still yield its rules through the installed version, does
the code index reflect current source, can the hooks fire, and does every capability the
instruction files cite still resolve.

That last check exists because of a specific defect. `AGENTS.md` cited a skill called `grilling`
that had been renamed. Nothing noticed. A citation that resolves to nothing is indistinguishable
from a working one until an agent tries to use it.

## Setting up a fresh clone

```bash
git clone <repo> && cd <repo>
pnpm install
git config core.hooksPath .githooks
pnpm exec codegraph init
pnpm preflight          # exits non-zero until the workflow genuinely works
```

`pnpm preflight` is the acceptance test for the setup itself. Each failure it reports names the
command that fixes it.

## Where changes to the workflow go

A consuming repository receives the workflow and its specification but cannot evolve them — the
next sync overwrites both, so an edit made there disappears without a word. A change to what the
workflow *does*, or what it is *required* to do, is proposed and archived in `forgekit-workflow`.

`codegraph_explore` returns nothing in that repository: everything there is shell, YAML, JSON or
Markdown, and CodeGraph ships no extractor for any of them. The planning rule about grounding
Impact is satisfied through the alternative the rule itself names — search the literal, and say
in the Impact section that you did.
