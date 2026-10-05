---
# The docs manifest the documentation tools read. Generated from the family's manifest
# table: change a key there and regenerate. The two prose lines below may be sharpened.
product: statifier_examples
family: statifier
audience: Developers evaluating the family who want to see one whole workflow
tone: "plain, second person, no marketing"
terminology:
  use:
    - execution
    - chart
    - document
    - revision
  avoid:
    - "run (noun)"
    - workflow instance
example_world: library-loan
docs_root: docs
quadrants:
  tutorials: docs/guides
  how_to: docs/how-to
  reference: docs/reference
  explanation: docs/explanation
readme: README.md
reference_generator: none
publish: github
contributor_paths:
  - docs/adr
  - docs/plans
  - docs/spikes
  - docs/research
  - docs/design
  - docs/measurements
  - CLAUDE.md
executed_snippets: []
readme_max_lines: 250
---

A Phoenix application that runs the family's worked examples end to end.
Examples are written in the library loan: a copy of a book lent to a patron, due, renewed, returned or lost.
