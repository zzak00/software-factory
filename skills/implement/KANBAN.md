# Kanban

The issue's card on the factory Project board shows where the work is. Respect the board: start only a ticket that is Ready, and move the card as the work moves.

## Stages

| Status | Set by | When |
| --- | --- | --- |
| Inbox | Project workflow "Item added to project" | The issue is filed |
| Ready | The operator | The issue is approved and unblocked |
| In Progress | `implement` | Work on the ticket starts |
| In Review | Project workflow "Pull request linked to issue" (must be turned on in the board settings) | A pull request that closes the issue is opened |
| Done | Project workflows "Item closed" and "Pull request merged" | The operator merges or closes |

`implement` makes the only agent move, Ready -> In Progress. Never set any other Status; tell the operator instead.

## Every move waits for a yes

Show the exact move (`#<issue>: Ready -> In Progress`) and make it only after the user agrees. Ask it together with the question the step already asks, not as a separate stop.

## Read the card

```bash
gh api graphql -F owner='{owner}' -F repo='{repo}' -F number=<issue> -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      projectItems(first: 20) {
        nodes {
          id
          status: fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
          project {
            id
            shortDescription
            field(name: "Status") { ... on ProjectV2SingleSelectField { id options { id name } } }
          }
        }
      }
    }
  }
}' --jq '.data.repository.issue.projectItems.nodes[]
  | select(.project.shortDescription == "Managed by Software Factory")
  | {item: .id, project: .project.id, field: .project.field.id, status: .status.name, options: .project.field.options}'
```

Run it from the item's checkout so `{owner}` and `{repo}` resolve to its repository. No result means the issue has no factory card: say so and continue without board moves.

## Move the card

```bash
gh project item-edit --id <item> --project-id <project> --field-id <field> --single-select-option-id <option id of the target Status>
```

Read the card again; the move is done when `status` equals the target.
