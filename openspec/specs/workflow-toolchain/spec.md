# workflow-toolchain Specification

## Purpose
Defines what this repository must declare about the tools its documented development workflow
depends on, so that a fresh clone — or a product generated from the template — arrives with the
workflow operational rather than merely described, and can prove it before relying on it.

## Requirements

### Requirement: Declared workflow toolchain

Every tool the repository's own workflow instructions depend on SHALL be declared in a
version-controlled file.

Tools SHALL be distinguished by where they can live. A **workflow tool** — one the repository
could obtain for itself — SHALL become available through a standard install command run at the
repository root, and its availability SHALL NOT depend on machine-global state outside the
repository. A **stack tool** — a compiler, SDK, or project generator that cannot be installed
into the repository — SHALL be declared alongside them, and MAY be resolved against the machine.

Where a tool is resolved against the machine, the report SHALL say so, because that is a weaker
guarantee than resolving against the repository and a reader cannot otherwise tell which kind of
answer they were given. Declaring a tool as a stack tool SHALL NOT be a way of avoiding the
first rule: a tool that could be obtained by the install command belongs there.

#### Scenario: A fresh clone obtains the toolchain

- **WHEN** the repository is cloned on a machine with no workflow tools installed globally, and
  the standard install command is run at the repository root
- **THEN** every declared workflow tool is executable from within the repository
- **AND** no manual per-tool installation step is required for them

#### Scenario: A declared stack tool is absent from the machine

- **WHEN** a tool the repository declares as a stack requirement is not present on the machine
- **THEN** the preflight check reports it as failing, naming the tool
- **AND** the report distinguishes it from a workflow tool the repository could have obtained

#### Scenario: A generated product carries the declarations

- **WHEN** a product is generated from the template
- **THEN** the generated project contains the same toolchain declarations as the base
- **AND** running the standard install command in it obtains the same tools

#### Scenario: The repository's scripts are invoked where file modes are not preserved

- **WHEN** a product is generated from the template, which does not carry the executable bit
- **THEN** the repository's scripts are still invocable through a declared command
- **AND** no manual permission change is required to run them

### Requirement: Hooks are reported when they cannot fire

Git ignores a hook that is not executable, without reporting anything. Where the repository
relies on a hook as a gate, the preflight check SHALL verify the hook can actually run, not
only that hooks are configured.

#### Scenario: The hooks path is set but the hook cannot execute

- **WHEN** `core.hooksPath` points at the repository's hooks directory but a hook file is not
  executable
- **THEN** the preflight check reports it as a failure naming the hook
- **AND** its output gives the command that makes it executable

#### Scenario: Hooks are configured and executable

- **WHEN** `core.hooksPath` is set and every hook in it is executable
- **THEN** the preflight check reports the hooks as passing

### Requirement: Cited capabilities resolve

Every skill, command, plugin, tool, and referenced document named in the repository's workflow
instruction files SHALL resolve to something present. An instruction file SHALL NOT name a
capability the declared toolchain does not provide, nor point at a document that does not exist.

#### Scenario: A named capability is missing

- **WHEN** the workflow instructions name a capability that does not resolve
- **THEN** the preflight check reports it as a failure, naming the capability and the file
  citing it

#### Scenario: A referenced document has been moved or deleted

- **WHEN** the workflow instructions point at a document path that no longer exists
- **THEN** the preflight check reports it as a failure

#### Scenario: A citation is of an unrecognised kind

- **WHEN** the workflow instructions cite something that matches none of the known kinds
- **THEN** the preflight check reports it as unrecognised rather than passing it silently

#### Scenario: All named capabilities resolve

- **WHEN** every capability named in the workflow instructions resolves
- **THEN** the preflight check reports no capability failures

### Requirement: Workflow preflight

The repository SHALL provide a single command that reports whether the workflow is operational
on the current machine. It SHALL check that the declared tools are present, that the repository's
workflow configuration is readable by the installed tool version, that the code index the
instructions require exists and reflects the current source, and that the repository's git hooks
are enabled. Each failure SHALL be reported with the command that resolves it.

Index staleness SHALL be judged against the source the index describes, not against the commit
history. Committing changes no source file, so a check anchored on commit time would report a
correct index as stale and train its readers to ignore it.

#### Scenario: The workflow is operational

- **WHEN** the preflight command runs against a correctly set up clone
- **THEN** it exits zero and reports each check as passing

#### Scenario: A prerequisite is missing

- **WHEN** the preflight command runs where a declared tool, the code index, or the git hooks
  configuration is absent
- **THEN** it exits non-zero
- **AND** its output names each failing check and the command that fixes it

#### Scenario: The code index is stale

- **WHEN** the code index exists but is older than the most recently modified source file
- **THEN** the preflight command reports it as failing rather than passing
- **AND** its output states that impact analysis based on it would be out of date

#### Scenario: A commit is made without editing source

- **WHEN** the code index reflects every source file and a commit is then made
- **THEN** the preflight command still reports the index as current

### Requirement: A check that cannot measure its subject fails

Every check SHALL report success only after examining the thing it guards. Where a check cannot
reach its subject — a tool absent, an enumeration empty, a file unreadable — it SHALL fail. A
reported `ok` means "I looked and it was fine", never "I found nothing to look at".

Where a declaration the repository supplies is the **subject** of a measurement — it says what
the check is to look at — an absent or empty declaration SHALL be treated as an inability to
measure and reported as a failure. It SHALL NOT fall back to a default that measures something
broader, because a check that quietly changes its own subject reports a result no reader can
interpret.

A declaration that instead **scopes** a search is different: empty is a real answer there, not an
absent one, and failing on it would refuse to accept a repository that legitimately has none of
that thing. Such a declaration SHALL be reported as empty rather than passed over in silence,
because silence about a narrowed search reads exactly like having searched everywhere.

#### Scenario: A check has nothing to examine

- **WHEN** a check's subject cannot be enumerated or read
- **THEN** the check reports failure, naming what it could not determine

#### Scenario: A citation that resolves to nothing

- **WHEN** an instruction file cites something no check knows how to resolve
- **THEN** it is reported as unresolved rather than passed over, provided it is shaped like a
  capability rather than like ordinary prose or an identifier

#### Scenario: A declaration naming a check's subject is missing

- **WHEN** a check's subject is named by a repository declaration that is absent or empty
- **THEN** the check reports failure naming the missing declaration
- **AND** it emits no verdict about that subject in the same run

#### Scenario: A declaration that only scopes a search is empty

- **WHEN** a repository declares none of something a check would otherwise search more widely for
- **THEN** the run states that the declaration is empty and what the search was narrowed to
- **AND** it does not report failure, because having none of that thing is a valid state

#### Scenario: An enumeration a check depends on yields nothing

- **WHEN** a check enumerates the things it is to examine and the enumeration is empty
- **THEN** the check reports failure rather than printing nothing and continuing

### Requirement: Configuration verified by reading it back

The preflight check SHALL confirm the repository's workflow configuration is usable by reading
its values back through the installed tool and asserting they are present, rather than by
comparing a declared version against an expected one. A configuration that parses without error
but yields no values SHALL be reported as failing.

#### Scenario: Configuration silently yields nothing

- **WHEN** the workflow configuration is well-formed but a section produces no values through
  the installed tool
- **THEN** the preflight check reports that section as failing

#### Scenario: An unrecognised tool version

- **WHEN** the installed tool version differs from the one recorded but still returns the
  expected configuration values
- **THEN** the preflight check reports the configuration as passing

### Requirement: Version policy for workflow tools

Declared workflow tools SHALL track the newest release compatible with the repository's
workflow configuration, and SHALL NOT adopt a release that could change that configuration's
format without an explicit decision. The reasoning behind each tool's version policy SHALL be
recorded alongside the repository's other dependency constraints.

#### Scenario: A compatible release is published

- **WHEN** a tool publishes a release compatible with the current configuration format
- **THEN** the declared policy permits it without a change to the declaration

#### Scenario: A format-breaking release is published

- **WHEN** a tool publishes a release that could change the configuration format
- **THEN** the declared policy excludes it until it is adopted deliberately

### Requirement: Scope interview precedes change proposals

The workflow SHALL provide a tool that turns an underspecified request into a written scope
decision before any change proposal is created, and the workflow instructions SHALL describe it
at that position. It SHALL be declared in the toolchain rather than left to be installed when
first needed.

#### Scenario: An underspecified request arrives

- **WHEN** a request is too vague for a proposal to state what is included and excluded
- **THEN** the workflow instructions direct the scope interview to be run first
- **AND** its written output is available as input to the change proposal

#### Scenario: The interview tool is described accurately

- **WHEN** the workflow instructions refer to the scope interview tool
- **THEN** they name it by the identifier that invokes it
- **AND** they describe how it is invoked, rather than presenting it as an agent-invoked skill

### Requirement: Shared workflow files are owned upstream

A defined set of workflow files SHALL be owned by a single upstream repository and delivered to
each consuming repository by a sync command rather than maintained separately in each. A
consuming repository SHALL NOT be the place those files are edited: the sync overwrites them, so
a local edit survives only until the next sync and then disappears without any report.

Each consuming repository SHALL retain sole ownership of the parts that differ between stacks —
its own project context, its own verification command, and its own dependency manifest.

The repository SHALL document which files are shared and which it owns, so that the boundary is
discoverable without reading the sync implementation.

#### Scenario: A shared file is edited locally

- **WHEN** a shared workflow file is edited in a consuming repository and the sync is then run
- **THEN** the upstream version replaces the local edit
- **AND** the documented boundary identifies that file as one owned upstream

#### Scenario: A repository-owned file is left alone

- **WHEN** the sync runs in a consuming repository
- **THEN** the repository's own project context, verification command, and dependency manifest
  are unchanged

### Requirement: Synchronising the workflow is repeatable

The sync SHALL produce the same result whether it is run once or many times. Where it merges
shared content into a file the repository also owns, it SHALL replace the previously merged
region rather than append alongside it, and SHALL leave the repository's own content in that
file untouched.

The sync SHALL report each file it updated, and SHALL report rather than silently skip a shared
file that upstream no longer publishes.

A sync that could not deliver a shared file SHALL NOT report success. It SHALL say so on the
same stream it reports success on, and SHALL exit with a failing status, so that a caller
chaining it to a later command stops rather than continuing against a repository that is now
holding a local copy of a file upstream no longer has.

Where merged content is derived from a shared file, the sync SHALL NOT perform that merge from a
copy it did not deliver in the same run. Merging from the copy left by an earlier sync would
assert a freshness the file does not have, and the result is indistinguishable from a current
one.

#### Scenario: The sync runs twice

- **WHEN** the sync is run and then run again with no upstream change
- **THEN** the second run leaves the repository in the same state as the first
- **AND** the merged region appears exactly once

#### Scenario: A shared file no longer exists upstream

- **WHEN** the sync runs and a file it expects is absent upstream
- **THEN** it reports that file as missing rather than leaving a stale copy unremarked
- **AND** it exits with a failing status, naming the undelivered file on the stream it would
  otherwise have reported success on

#### Scenario: Merged content would come from an undelivered file

- **WHEN** the sync cannot deliver the shared file a merge draws from
- **THEN** it does not perform the merge
- **AND** the previously merged content is left as it was

### Requirement: A failed merge leaves the previous configuration intact

Where the sync merges shared content into the repository's workflow configuration, it SHALL
verify the merged result before replacing the existing file. If the result does not contain the
sections the merge exists to deliver, the sync SHALL fail and leave the existing file unchanged.

A partially merged configuration is worse than an unmerged one: the tooling reads it without
error and produces nothing, which is the failure mode the configuration readback requirement
exists to catch.

#### Scenario: The merged result is missing its sections

- **WHEN** the merged configuration would not contain the shared sections
- **THEN** the sync reports a failure
- **AND** the repository's existing configuration file is left as it was

### Requirement: Stack-specific inputs are declared by the repository

The preflight check SHALL be usable without modification across repositories of different
technology stacks. Every input that varies by stack — which files count as source, which
machine-level tools the stack requires, and which nested package directories exist — SHALL be
declared by the repository rather than written into the shared check.

A tool a repository declares as a stack requirement SHALL count as part of that repository's
declared toolchain wherever instruction files cite it, so that a correct citation of a real tool
is not reported as unresolved.

Machine-level tools SHALL be reported as resolved against the machine rather than against the
repository's own toolchain, because that is a weaker guarantee and the report is the only place
a reader can learn which kind of answer they were given.

#### Scenario: The same check runs against a different stack

- **WHEN** the preflight check runs in a repository whose declaration names a different set of
  source file types and machine-level tools
- **THEN** it measures that repository's sources and tools without the check itself differing

#### Scenario: An instruction file cites a declared stack tool

- **WHEN** an instruction file cites a tool the repository declares as a stack requirement
- **THEN** the citation resolves rather than being reported as outside the declared toolchain
