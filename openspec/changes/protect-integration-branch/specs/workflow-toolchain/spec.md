## ADDED Requirements

### Requirement: The integration branch is protected from direct commits

Every change to an integration branch — `main` or `master` — SHALL arrive through a separate
branch and a pull request. The workflow SHALL enforce this in two places: locally, so the
mistake is caught before it is committed, and on the remote, so it holds for every clone and
cannot be stepped over by a local flag.

**Locally**, the repository SHALL provide a git hook that refuses a commit while `HEAD` is on an
integration branch, and its output SHALL name the branch and give the command that moves the
staged work onto a new branch. The hook SHALL take no action when `HEAD` is detached or on any
other branch, so that tooling operations and ordinary branch work are untouched. The hook SHALL
be delivered by the same shared-hooks mechanism as the other hooks, so a generated product
carries it and the preflight check already reports whether it can execute.

**On the remote**, the repository SHALL provide a single declared command that applies branch
protection to a repository's default branch: a pull request required before merging, force-pushes
and branch deletion refused, and no actor exempt from the rule. It SHALL be run once per
repository and SHALL be safe to run again, converging on the same protection rather than
stacking a second rule.

Verifying that the remote protection is actually in place on a given repository is out of scope
for the preflight check, which measures the local workflow and does not reach the network.

#### Scenario: A commit is attempted directly on the integration branch

- **WHEN** a commit is made while `HEAD` is on `main` or `master` and the repository's hooks are
  enabled
- **THEN** the commit is refused
- **AND** the hook's output names the branch and gives the command to move the staged work onto
  a new branch

#### Scenario: A commit is made on a working branch

- **WHEN** a commit is made while `HEAD` is on a branch that is not an integration branch
- **THEN** the hook takes no action and the commit proceeds

#### Scenario: A commit is made with no branch checked out

- **WHEN** a commit is made while `HEAD` is detached — a rebase, a bisect, a checked-out commit
- **THEN** the hook takes no action and the commit proceeds

#### Scenario: A generated product carries the hook

- **WHEN** a product is generated from the template and its hooks are enabled
- **THEN** the same protection against direct commits to the integration branch is in effect
- **AND** the preflight check reports the hook as one it verified can execute

#### Scenario: Remote protection is applied to a repository

- **WHEN** the declared branch-protection command is run once inside a repository clone
- **THEN** the repository's default branch requires a pull request before a change can merge
- **AND** force-pushes to it and deletion of it are refused
- **AND** no actor is exempt from the rule

#### Scenario: The remote protection command is run again

- **WHEN** the declared branch-protection command is run a second time on a repository that is
  already protected
- **THEN** the repository ends in the same protected state
- **AND** the protection is defined by one rule, not two
