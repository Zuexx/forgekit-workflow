## ADDED Requirements

### Requirement: Dependabot merges itself when the change is boring

The workflow SHALL provide an automated path that merges a Dependabot-authored pull request
without a person or agent reviewing it, restricted to the case where the change carries the
least risk: exactly one dependency, bumped by a patch or minor version, with every other check
on that pull request reporting success. The automation SHALL merge such a pull request as a
merge commit, matching the family's merge-method default, and SHALL delete its branch after.

The automation SHALL NOT act on a pull request that updates more than one dependency (a grouped
update) or that carries a major version bump; those SHALL remain open for manual review, as they
did before this requirement existed. The automation SHALL NOT merge while any other check on the
pull request is still pending, and SHALL NOT merge if any other check has failed.

#### Scenario: A single patch or minor update merges itself

- **WHEN** a Dependabot pull request updates exactly one dependency by a patch or minor version
- **AND** every other check on that pull request has completed successfully
- **THEN** the pull request is merged as a merge commit
- **AND** its branch is deleted

#### Scenario: A grouped update is left for manual review

- **WHEN** a Dependabot pull request updates more than one dependency in one pull request
- **THEN** the automation takes no merging action, regardless of the checks' outcome

#### Scenario: A major version bump is left for manual review

- **WHEN** a Dependabot pull request bumps a single dependency by a major version
- **THEN** the automation takes no merging action, regardless of the checks' outcome

#### Scenario: A still-pending check blocks the merge

- **WHEN** a Dependabot pull request is otherwise eligible, but at least one of its other checks
  has not yet completed
- **THEN** the automation waits rather than merging
- **AND** it does not report success until every other check has completed

#### Scenario: A failing check blocks the merge

- **WHEN** a Dependabot pull request is otherwise eligible, but at least one of its other checks
  has failed
- **THEN** the pull request is not merged
- **AND** the automation's own run reports failure, leaving the pull request open
