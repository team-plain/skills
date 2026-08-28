---
name: plain-support
description: Access to Plain customer support platform. Read customers, threads, timeline, help center content, and broadcasts. Add notes to threads. Create, update, and publish help center articles. Draft broadcasts and manage broadcast audiences.
license: MIT
compatibility: Requires curl, jq, and PLAIN_API_KEY environment variable
metadata:
  author: plain
  version: "2.3"
allowed-tools: Bash Read
---

# Plain API Skill

Access to the Plain customer support platform via GraphQL API. This skill provides commands to read customers, support threads, timeline entries, help center content, broadcasts, and more. Notes can be added to threads. Help center articles can be created, updated, and published directly. Broadcasts and broadcast audiences can be drafted and edited, but never scheduled or sent.

## Prerequisites

- `PLAIN_API_KEY` environment variable set with your API key
- `curl` and `jq` installed

## Quick Reference

### Customers (Read Only)

```bash
# List customers
scripts/plain-api.sh customer list --first 10

# Get customer by ID
scripts/plain-api.sh customer get c_01ABC...

# Get customer by email
scripts/plain-api.sh customer get-by-email user@example.com

# Get customer by external ID
scripts/plain-api.sh customer get-by-external-id your-system-id

# Search customers
scripts/plain-api.sh customer search "john doe"
```

### Threads (Read + Write)

```bash
# List threads (TODO status by default)
scripts/plain-api.sh thread list --first 20

# List all threads including done
scripts/plain-api.sh thread list --status all

# List done threads
scripts/plain-api.sh thread list --status DONE

# List threads by priority
scripts/plain-api.sh thread list --priority urgent
scripts/plain-api.sh thread list --priority high
scripts/plain-api.sh thread list --status TODO --priority low

# Get thread details
scripts/plain-api.sh thread get th_01ABC...

# Search threads
scripts/plain-api.sh thread search "billing issue"

# Get thread timeline (all messages, events, status changes)
scripts/plain-api.sh thread timeline th_01ABC... --first 50

# Paginate through timeline
scripts/plain-api.sh thread timeline th_01ABC... --first 20 --after "cursor_from_previous_page"

# Add a note to a thread (internal note, not visible to customer)
scripts/plain-api.sh thread note th_01ABC... --text "This is an internal note"

# Add a note with markdown formatting
scripts/plain-api.sh thread note th_01ABC... --text "Note text" --markdown "**Bold** and *italic*"

# Add a note from a file (for longer notes)
scripts/plain-api.sh thread note th_01ABC... --text-file /path/to/note.txt
```

**Thread note options:**
| Option | Required | Description |
|--------|----------|-------------|
| `--text` | Yes* | Plain text content of the note |
| `--text-file` | Yes* | Path to file containing note text |
| `--markdown` | No | Markdown formatted version of the note |

*Either `--text` or `--text-file` is required.

**Thread list options:**
| Option | Description |
|--------|-------------|
| `--status` | Filter by status: `TODO`, `SNOOZED`, `DONE`, or `all` |
| `--priority` | Filter by priority: `urgent`, `high`, `normal`, `low` |
| `--customer` | Filter by customer ID |
| `--first` | Number of results (default: 10) |

**Thread priorities:** `urgent` > `high` > `normal` (default) > `low`

### Thread Links (Read + Write)

Attach external issues (GitHub, etc.) to a thread. Plain fetches title, URL, description, and status from the integration server-side — only the ref is needed.

```bash
# Add a GitHub issue or PR — accepts URL, shorthand, or canonical sourceId
scripts/plain-api.sh thread link add th_01ABC... https://github.com/owner/repo/issues/45
scripts/plain-api.sh thread link add th_01ABC... https://github.com/owner/repo/pull/45
scripts/plain-api.sh thread link add th_01ABC... owner/repo#45
scripts/plain-api.sh thread link add th_01ABC... owner/repo/45

# List links on a thread
scripts/plain-api.sh thread link list th_01ABC...
```

**Thread link add options:**
| Option | Required | Description |
|--------|----------|-------------|
| `<thread_id>` | Yes | Thread to attach the link to |
| `<ref>` | Yes | GitHub URL, `owner/repo#N`, or `owner/repo/N` |
| `--source` | No | Source type (default: `github_issue`). Other values: `shortcut_issue`, `rootly_incident`, `incidentio_incident` — for these, pass the integration's native sourceId as `<ref>` |

**Notes:**
- The workspace must have the relevant integration configured (e.g., GitHub) for Plain to resolve metadata. If not, the `add` call returns an error.
- Removing links is not supported via API key — delete from the Plain UI.
- Plain does not expose `searchThreadLinkCandidates` to machine users, so the agent must supply the ref directly (parse from a URL the customer pasted, etc.).

### Companies (Read Only)

```bash
# List companies
scripts/plain-api.sh company list --first 10

# Get company by ID
scripts/plain-api.sh company get co_01ABC...
```

### Tenants (Read Only)

```bash
# List tenants
scripts/plain-api.sh tenant list --first 10

# Get tenant by ID
scripts/plain-api.sh tenant get ten_01ABC...
```

### Labels (Read Only)

```bash
# List available label types
scripts/plain-api.sh label list --first 20
```

### Help Center (Read + Write)

```bash
# List help centers
scripts/plain-api.sh helpcenter list

# Get help center details
scripts/plain-api.sh helpcenter get hc_01ABC...

# List articles in help center
scripts/plain-api.sh helpcenter articles hc_01ABC... --first 20

# Get article by ID
scripts/plain-api.sh helpcenter article get hca_01ABC...

# Get article by slug
scripts/plain-api.sh helpcenter article get-by-slug hc_01ABC... my-article-slug

# Create new article (defaults to DRAFT status)
scripts/plain-api.sh helpcenter article upsert hc_01ABC... \
  --title "How to reset password" \
  --description "Step-by-step guide for resetting your password" \
  --content "<h1>Reset Password</h1><p>Follow these steps...</p>"

# Create and publish article directly
scripts/plain-api.sh helpcenter article upsert hc_01ABC... \
  --title "Getting Started" \
  --description "Quick start guide for new users" \
  --content "<p>Welcome!</p>" \
  --status PUBLISHED

# Update existing article
scripts/plain-api.sh helpcenter article upsert hc_01ABC... \
  --id hca_01ABC... \
  --title "Updated Title" \
  --description "Updated description" \
  --content "<p>New content</p>"

# Use --content-file for large HTML content (recommended)
scripts/plain-api.sh helpcenter article upsert hc_01ABC... \
  --title "Detailed Guide" \
  --description "Comprehensive documentation" \
  --content-file /path/to/article.html \
  --status PUBLISHED

# Get article group
scripts/plain-api.sh helpcenter group get hcag_01ABC...

# Create article group
scripts/plain-api.sh helpcenter group create hc_01ABC... --name "Getting Started"

# Create nested article group
scripts/plain-api.sh helpcenter group create hc_01ABC... --name "Advanced Topics" --parent hcag_01PARENT...

# Update article group
scripts/plain-api.sh helpcenter group update hcag_01ABC... --name "New Group Name"

# Delete article group
scripts/plain-api.sh helpcenter group delete hcag_01ABC...
```

**Article upsert options:**
| Option | Required | Description |
|--------|----------|-------------|
| `--title` | Yes | Article title |
| `--description` | Yes | Short description (shown in article lists) |
| `--content` | Yes* | HTML content (inline) |
| `--content-file` | Yes* | Path to file containing HTML content |
| `--id` | No | Article ID (for updates) |
| `--group` | No | Article group ID |
| `--status` | No | DRAFT (default) or PUBLISHED |

*Either `--content` or `--content-file` is required. Use `--content-file` for large content.

**Note:** The response includes a `link` field with the URL to edit the article in the Plain UI:

```json
{
  "data": { ... },
  "link": "https://app.plain.com/workspace/w_01.../help-center/hc_01.../articles/hca_01.../"
}
```

### Broadcasts (Read + Write)

A broadcast is one message posted to many Slack channels at once. This skill drafts and inspects
them. **It never schedules or sends** — including test sends, which post real messages to real
channels. A human does that in the Plain app.

```bash
# List broadcasts (newest first)
scripts/plain-api.sh broadcast list --first 10
scripts/plain-api.sh broadcast list --status DRAFT
scripts/plain-api.sh broadcast list --status SENT --status PARTIALLY_SENT

# Get one broadcast, including content, sender and send target
scripts/plain-api.sh broadcast get bc_01ABC...

# Search by name (2+ characters)
scripts/plain-api.sh broadcast search "launch"

# Send history. Unfiltered this includes test sends — check isTest
scripts/plain-api.sh broadcast sends bc_01ABC... --real-only

# Per-recipient results for the latest real send
scripts/plain-api.sh broadcast deliveries bc_01ABC... --status FAILED
scripts/plain-api.sh broadcast deliveries bc_01ABC... --send bcs_01ABC...

# Preview who a target reaches right now, before drafting anything
scripts/plain-api.sh broadcast recipients --tier tier_01ABC...
scripts/plain-api.sh broadcast recipients --audience ba_01ABC... --search eng
scripts/plain-api.sh broadcast recipients --all-tenants

# Draft a broadcast (stays in DRAFT — nothing is sent)
scripts/plain-api.sh broadcast create \
  --name "March launch" \
  --notification-title "We shipped bulk actions" \
  --text "Bulk actions are live today." \
  --tier tier_01ABC...

# Edit a draft. Omitted flags are left alone, not cleared
scripts/plain-api.sh broadcast update bc_01ABC... --name "March launch (EU)"
scripts/plain-api.sh broadcast update bc_01ABC... --content-file /tmp/broadcast.json

# Soft-delete
scripts/plain-api.sh broadcast delete bc_01ABC...
```

**Broadcast create/update options:**
| Option | Required | Description |
|--------|----------|-------------|
| `--name` | Yes (create) | Internal name. Never shown to recipients |
| `--text` | Yes* | Plain text body, wrapped into a Tiptap document for you |
| `--content-file` | Yes* | Path to a Tiptap document (JSON with `"type": "doc"`) |
| `--notification-title` | No | What recipients see in the notification. Required before a human can send |
| `--sender-type` | No | `PLAIN_WORKSPACE` or `PLAIN_USER` (implied by `--sender-user`) |
| `--sender-user` | No | User ID to post as |
| `--link-unfurling` | No | `true` or `false` |
| `--all-tenants` | No | Target every tenant with a connected channel |
| `--tier` / `--tenant` / `--audience` / `--channel-name-contains` | No | Target dimensions. Repeatable, and they combine |
| `--filters-file` | No | A filter tree with `and`/`or`/`not`, for anything the flags cannot express |

*On create, either `--text` or `--content-file` is required. There is no markdown or HTML form of a
broadcast body — see [references/ENTITIES.md](references/ENTITIES.md).

### Broadcast Audiences (Read + Write)

A saved, reusable set of recipients. Resolved to channels at send time, so it stays current as
tenants and channels change.

```bash
# List audiences
scripts/plain-api.sh audience list --first 20
scripts/plain-api.sh audience list --search enterprise

# Get one
scripts/plain-api.sh audience get ba_01ABC...

# Create
scripts/plain-api.sh audience create --name "Enterprise" --tier tier_01ABC...
scripts/plain-api.sh audience create --name "Support channels" --channel-name-contains "-support"
scripts/plain-api.sh audience create --name "Everyone" --all-tenants

# Rename, or replace the filters
scripts/plain-api.sh audience update ba_01ABC... --name "Enterprise (EU)"
scripts/plain-api.sh audience update ba_01ABC... --filters-file /tmp/filters.json

# Soft-delete (rejected while a broadcast targeting it is scheduled or sending)
scripts/plain-api.sh audience delete ba_01ABC...
```

**Warning:** `audience update` with any filter flag **replaces** the stored filters wholesale — there
is no merge. Run `audience get` first and pass the whole tree back if you only mean to add a row.
Editing an audience also changes who every broadcast using it will reach on its next send.

### Tiers & SLAs (Read Only)

```bash
# List tiers with SLA configurations
scripts/plain-api.sh tier list

# Get tier details
scripts/plain-api.sh tier get tier_01ABC...
```

### Workspace

```bash
# Get current workspace info
scripts/plain-api.sh workspace
```

## Common Workflows

### Research customer history

1. Get customer: `customer get c_...` or `customer get-by-email user@example.com`
2. List their threads: `thread list --customer c_... --status all`
3. Get thread details: `thread get th_...`
4. Read full conversation: `thread timeline th_... --first 100`

### Read thread conversation

1. Get thread: `thread get th_...`
2. Fetch timeline entries: `thread timeline th_... --first 50`
3. Extract messages: Look for `EmailEntry`, `ChatEntry`, `SlackMessageEntry`, etc. in the response
4. Paginate if needed: Use `--after` with cursor from `pageInfo.endCursor`

### Add internal note to thread

1. Get thread ID from URL or search: `thread search "issue keyword"`
2. Add note: `thread note th_... --text "Investigation notes here"`
3. Verify in timeline: `thread timeline th_... --first 5`

### Create or update help article

1. List help centers: `helpcenter list`
2. Write HTML content to a file (for large articles): `/tmp/article.html`
3. Create/update article:
   ```bash
   helpcenter article upsert hc_... \
     --title "Article Title" \
     --description "Short description" \
     --content-file /tmp/article.html \
     --status PUBLISHED
   ```
4. Use the returned link to view/edit in Plain UI

### Draft a broadcast for a tier

1. Find the tier: `tier list`
2. Save the audience (optional, but reusable): `audience create --name "Enterprise" --tier tier_...`
3. Check who it reaches before writing anything: `broadcast recipients --audience ba_...` — read
   `count`, and `emptyReason` if it is zero
4. Draft it: `broadcast create --name "..." --notification-title "..." --text "..." --audience ba_...`
5. Confirm the draft: `broadcast get bc_...` (status stays `DRAFT`)
6. Hand the broadcast ID to a human — scheduling and sending happen in the Plain app

## Entity Reference

See [references/ENTITIES.md](references/ENTITIES.md) for detailed documentation on all entities including:

- Customer fields and statuses
- Thread status, priority, and channels
- Timeline entry types (24 types: emails, chats, notes, events, status changes, etc.)
- Company and Tenant structures
- Label and LabelType definitions
- Help Center, Article, and ArticleGroup schemas
- Tier and SLA configurations
- Broadcast fields, statuses, and the Tiptap content format
- BroadcastSend and delivery statuses, including failure reasons
- BroadcastAudience filter trees and send targets

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `PLAIN_API_KEY` | Yes | Your Plain API key |
| `PLAIN_API_URL` | No | API endpoint (default: `https://core-api.uk.plain.com/graphql/v1`) |

## Output Format

All commands return JSON. Use `jq` for parsing:

```bash
# Get just customer name
scripts/plain-api.sh customer get c_01ABC... | jq '.data.customer.fullName'

# Get thread IDs
scripts/plain-api.sh thread list | jq '.data.threads.edges[].node.id'

# Get timeline message content
scripts/plain-api.sh thread timeline th_01ABC... | jq '.data.thread.timelineEntries.edges[].node.entry'

# Get link from article creation
scripts/plain-api.sh helpcenter article upsert hc_... --title "Test" --content "<p>Test</p>" | jq -r '.link'
```
