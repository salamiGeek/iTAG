# Issue tracker

iTAG tracks issues and specs as local Markdown under `.scratch/`.

## Specs and tickets

- Store each feature in `.scratch/<feature-slug>/` and its spec in `spec.md` inside that directory.
- Store each implementation ticket in its own `issues/<NN>-<slug>.md` file inside the feature directory. Number tickets from `01`.
- Record the triage state in a `Status:` line near the top of each implementation ticket. Use the labels in [Triage labels](triage-labels.md).
- Append comments to the end of an issue under `## Comments`.
- To publish a spec or ticket, create its file at the corresponding path. To fetch a ticket, read the referenced file or resolve its number within the relevant feature.

## Wayfinder

- Store the map in `.scratch/<effort>/map.md` with Notes, Decisions-so-far, and Fog sections.
- Store each child ticket in `.scratch/<effort>/issues/<NN>-<slug>.md`, starting at `01`. Put the question in the body and use `Type:` for `research`, `prototype`, `grilling`, or `task`.
- List dependencies as `Blocked by: NN, NN`. A ticket is unblocked when all listed tickets have `Status: resolved`.
- Select the lowest-numbered open, unblocked, and unclaimed ticket. Set `Status: claimed` before starting.
- To resolve a ticket, append its answer under `## Answer`, set `Status: resolved`, and add a short summary and a link to the ticket under Decisions-so-far in the map.
