# Plain API Entities Reference

This document describes the main entities in the Plain customer support platform API.

## Customer

A customer is a person who contacts support. Customers can be identified by ID, email, or external ID.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique customer identifier (e.g., `c_01ABC...`) |
| `fullName` | String | Customer's full name |
| `shortName` | String | Customer's short/display name |
| `email.email` | String | Customer's email address |
| `email.isVerified` | Boolean | Whether email is verified |
| `externalId` | String | Your system's identifier for this customer |
| `status` | Enum | `ACTIVE`, `INACTIVE`, `SPAM`, `DELETED`, `UNVERIFIED` |
| `company` | Company | Associated company (if any) |
| `createdAt` | DateTime | When customer was created |
| `updatedAt` | DateTime | When customer was last updated |

### Customer Identifiers

You can look up customers by:
- **ID**: `customer get c_01ABC...`
- **Email**: `customer get-by-email user@example.com`
- **External ID**: `customer get-by-external-id your-system-id`

---

## Thread

A thread represents a support conversation with a customer. Threads have a status, priority, and can be assigned to users.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique thread identifier (e.g., `th_01ABC...`) |
| `title` | String | Thread title/subject |
| `description` | String | Thread description |
| `previewText` | String | Preview of thread content |
| `status` | Enum | `TODO`, `SNOOZED`, `DONE` |
| `priority` | Int | 0 (urgent) to 3 (low) |
| `externalId` | String | Your system's identifier for this thread |
| `channel` | Enum | Source channel (see below) |
| `customer` | Customer | Associated customer |
| `assignedTo` | User/MachineUser | Assigned agent (if any) |
| `labels` | [Label] | Applied labels |
| `createdAt` | DateTime | When thread was created |
| `updatedAt` | DateTime | When thread was last updated |

### Thread Status

| Status | Description |
|--------|-------------|
| `TODO` | Active thread requiring attention |
| `SNOOZED` | Temporarily hidden until a specified time |
| `DONE` | Completed/resolved thread |

### Thread Priority

| Priority | Level | Description |
|----------|-------|-------------|
| 0 | Urgent | Requires immediate attention |
| 1 | High | Important, handle soon |
| 2 | Normal | Standard priority (default) |
| 3 | Low | Can wait |

### Thread Channel

The channel indicates how the thread was created:

| Channel | Description |
|---------|-------------|
| `EMAIL` | Created from email |
| `SLACK` | Created from Slack message |
| `CHAT` | Created from live chat |
| `API` | Created via API |
| `MS_TEAMS` | Created from Microsoft Teams |
| `DISCORD` | Created from Discord |
| `IMPORT` | Imported from another system |

---

## Timeline Entry

A timeline entry represents a single item in a thread's conversation history. Use `thread timeline <threadId>` to fetch entries.

### TimelineEntry Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique timeline entry identifier |
| `customerId` | ID | Associated customer ID |
| `threadId` | ID | Associated thread ID |
| `timestamp` | DateTime | When the entry occurred |
| `actor` | Actor | Who performed the action |
| `entry` | Entry | The entry content (see types below) |

### Entry Types (24 total)

The `entry` field contains one of the following types, identified by `__typename`:

#### Message Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `EmailEntry` | Email message | `subject`, `textContent`, `markdownContent`, `from`, `to`, `sentAt`, `attachments` |
| `ChatEntry` | Live chat message | `chatText`, `customerReadAt`, `attachments` |
| `SlackMessageEntry` | Slack message | `text`, `slackMessageLink`, `reactions`, `attachments` |
| `SlackReplyEntry` | Slack reply | `text`, `slackMessageLink`, `reactions`, `attachments` |
| `MSTeamsMessageEntry` | MS Teams message | `text`, `markdownContent`, `msTeamsMessageLink`, `attachments` |
| `DiscordMessageEntry` | Discord message | `markdownContent`, `discordMessageLink`, `attachments` |
| `NoteEntry` | Internal note | `text`, `markdown`, `attachments` |

#### Event Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `CustomEntry` | Custom timeline entry | `title`, `type`, `components`, `externalId` |
| `ThreadEventEntry` | Thread event (API-created) | `title`, `components`, `timelineEventId` |
| `CustomerEventEntry` | Customer event (API-created) | `title`, `components`, `timelineEventId` |

#### Status/Change Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `ThreadStatusTransitionedEntry` | Status change | `nextStatus`, `nextStatusDetail` |
| `ThreadPriorityChangedEntry` | Priority change | `previousPriority`, `nextPriority` |
| `ThreadAssignmentTransitionedEntry` | Assignment change | `previousAssignee`, `nextAssignee` |
| `ThreadAdditionalAssigneesTransitionedEntry` | Additional assignees change | `previousAssignees`, `nextAssignees` |
| `ThreadLabelsChangedEntry` | Labels change | `previousLabels`, `nextLabels` |
| `ServiceLevelAgreementStatusTransitionedEntry` | SLA status change | `previousSlaStatus`, `nextSlaStatus`, `serviceLevelAgreement` |

#### Thread Link Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `ThreadLinkCreatedEntry` | Link created | `threadLink` (with `title`, `url`, `status`) |
| `ThreadLinkUpdatedEntry` | Link updated | `threadLink`, `previousThreadLink` |
| `ThreadLinkDeletedEntry` | Link deleted | `threadLink` |
| `LinearIssueThreadLinkStateTransitionedEntry` | Linear issue state change | `linearIssueId`, `previousLinearStateId`, `nextLinearStateId` |

#### Discussion Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `ThreadDiscussionEntry` | Discussion started | `discussionType`, `slackChannelName`, `emailRecipients` |
| `ThreadDiscussionResolvedEntry` | Discussion resolved | `discussionType`, `resolvedAt` |

#### Specialized Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `HelpCenterAiConversationMessageEntry` | Help center AI message | `messageMarkdown`, `helpCenterId` |
| `CustomerSurveyRequestedEntry` | Survey requested | `customerSurveyId`, `surveyResponseId` |

### Actor Types

The `actor` field identifies who performed the action:

| Type | Description | Key Fields |
|------|-------------|------------|
| `UserActor` | Human user | `userId` |
| `MachineUserActor` | Machine/API user | `machineUserId`, `machineUser` |
| `CustomerActor` | Customer | `customerId`, `customer` |
| `SystemActor` | System | `systemId` |
| `DeletedCustomerActor` | Deleted customer | `customerId` |

### Example: Extracting Messages

```bash
# Get timeline
scripts/plain-api.sh thread timeline th_01ABC... --first 50 | jq '
  .data.thread.timelineEntries.edges[].node |
  select(.entry.__typename | test("Email|Chat|Slack|Teams|Discord|Note")) |
  {
    type: .entry.__typename,
    timestamp: .timestamp.iso8601,
    content: (.entry.textContent // .entry.text // .entry.chatText // .entry.markdownContent // .entry.markdown)
  }
'
```

---

## Company

A company represents an organization that customers belong to.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique company identifier (e.g., `co_01ABC...`) |
| `name` | String | Company name |
| `domainName` | String | Company domain (e.g., `example.com`) |
| `createdAt` | DateTime | When company was created |
| `updatedAt` | DateTime | When company was last updated |

---

## Tenant

A tenant represents a multi-tenant grouping for customers. Useful for B2B SaaS where customers belong to specific tenant organizations.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique tenant identifier (e.g., `ten_01ABC...`) |
| `name` | String | Tenant name |
| `externalId` | String | Your system's identifier for this tenant |
| `source` | Enum | `API`, `SALESFORCE`, `HUBSPOT` |
| `createdAt` | DateTime | When tenant was created |
| `updatedAt` | DateTime | When tenant was last updated |

---

## Label / LabelType

Labels are used to categorize and organize threads. LabelTypes define the available labels.

### LabelType Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique label type identifier (e.g., `lt_01ABC...`) |
| `name` | String | Label name |
| `isArchived` | Boolean | Whether the label is archived |

### Label Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique label identifier |
| `labelType` | LabelType | The label type definition |

---

## Help Center

Help centers contain knowledge base articles organized into groups.

### HelpCenter Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique help center identifier (e.g., `hc_01ABC...`) |
| `publicName` | String | Public-facing name |
| `internalName` | String | Internal name |
| `description` | String | Help center description |
| `type` | Enum | `SELF_SERVICE`, `PRIVATE`, `PORTAL` |
| `articles` | Connection | All articles in this help center |
| `articleGroups` | Connection | All article groups |

### HelpCenterArticle Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique article identifier (e.g., `hca_01ABC...`) |
| `title` | String | Article title |
| `description` | String | Article description/summary |
| `contentHtml` | String | Article content in HTML |
| `slug` | String | URL-friendly slug |
| `status` | Enum | `DRAFT`, `PUBLISHED` |
| `articleGroup` | Group | Parent group (if any) |
| `createdAt` | DateTime | When article was created |
| `updatedAt` | DateTime | When article was last updated |

### HelpCenterArticleGroup Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique group identifier (e.g., `hcag_01ABC...`) |
| `name` | String | Group name |
| `slug` | String | URL-friendly slug |
| `parentArticleGroup` | Group | Parent group for hierarchy |
| `articles` | Connection | Articles in this group |
| `childArticleGroups` | Connection | Child groups |

---

## Tier

Tiers define service levels for customers/tenants, including SLA configurations.

### Tier Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique tier identifier (e.g., `tier_01ABC...`) |
| `name` | String | Tier name |
| `externalId` | String | Your system's identifier for this tier |
| `color` | String | Hex color code (e.g., `#3B82F6`) |
| `isDefault` | Boolean | Whether this is the default tier |
| `defaultThreadPriority` | Int | Default priority for threads in this tier |
| `serviceLevelAgreements` | [SLA] | SLA configurations |
| `memberships` | Connection | Companies/tenants in this tier |

### ServiceLevelAgreement Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique SLA identifier |
| `firstResponseTimeMinutes` | Int | First response SLA (for FirstResponseTime SLA) |
| `nextResponseTimeMinutes` | Int | Next response SLA (for NextResponseTime SLA) |
| `useBusinessHoursOnly` | Boolean | Whether SLA tracks only during business hours |
| `threadPriorityFilter` | [Int] | Which thread priorities this SLA applies to |

---

## Broadcast

A broadcast is a message authored once and posted to many recipients at the same time. Today the
only channel is Slack, so a broadcast becomes one Slack message per recipient channel.

**Sending and scheduling are not available through this skill** — `broadcast create`/`update` draft
the message, and a human sends it from the Plain app.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique broadcast identifier (e.g., `bc_01ABC...`) |
| `name` | String | Internal name. Never shown to recipients. This is what `broadcast search` matches on |
| `notificationTitle` | String | What recipients see in the notification. Required before the broadcast can be sent |
| `content` | String | The body, as a serialised Tiptap document (see below) |
| `contentFormat` | Enum | `TIPTAP` (the only value) |
| `type` | Enum | `SLACK` (the only value). Fixed at creation |
| `isLinkUnfurlingEnabled` | Boolean | Whether Slack expands links and media |
| `sender` | Union | `SlackBroadcastSender` (a user) or `PlainWorkspaceBroadcastSender` (the workspace) |
| `sendTarget` | SendTarget | Who it reaches. Resolved to channels at send time, not when saved |
| `status` | Enum | Lifecycle state, **derived from the latest real send** |
| `sends` | Connection | Send history, newest first. Includes test sends unless filtered |
| `latestSend` | BroadcastSend | The latest non-test send, which `status` comes from |
| `reactions` | [ReactionCount] | Emoji reactions on the posted messages, totalled across channels |
| `threads` | Connection | Threads created by replies to this broadcast |
| `isDeleted` | Boolean | Soft-deleted. Excluded from lists and search, still fetchable by ID |
| `scheduledAt` / `startedAt` / `completedAt` | DateTime | All come from `latestSend`, so all are null on a draft |

### Content is a Tiptap document

There is no markdown or HTML form of a broadcast body. `content` is a JSON string:

```json
{
  "type": "doc",
  "content": [
    { "type": "paragraph", "content": [{ "type": "text", "text": "We shipped it." }] }
  ]
}
```

`broadcast create --text "..."` builds this for you, one paragraph per blank-line-separated block.
Use `--content-file` when you need richer structure. Node types the Slack converter understands:
`paragraph`, `heading`, `bulletList`, `orderedList`, `listItem`, `blockquote`, `codeBlock`,
`horizontalRule`, `image`, `hardBreak`, and `text` with marks. Anything else is **dropped silently**
when the broadcast is posted.

### Broadcast Status

Derived from the latest real send, never stored. Test sends never move it.

| Status | Description |
|--------|-------------|
| `DRAFT` | Never scheduled. Fully editable |
| `SCHEDULED` | A send is queued. Still editable until it starts |
| `RESOLVING` | The send is working out which recipients it applies to |
| `SENDING` | Delivering to recipients |
| `SENT` | Every recipient received it |
| `PARTIALLY_SENT` | Finished, but reached some recipients and not others |
| `FAILED` | Finished without reaching anybody |
| `CANCELLED` | Cancelled before it completed |

---

## BroadcastSend and BroadcastSendDelivery

One *send* is one run of a broadcast; one *delivery* is one recipient's copy of it.

### BroadcastSend Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique send identifier (e.g., `bcs_01ABC...`) |
| `status` | Enum | Same values as `BroadcastStatus` minus `DRAFT` |
| `isTest` | Boolean | **Check this.** A test send posts real messages to real channels and collects real deliveries — it is only distinguishable by this field, and it never affects the broadcast's `status` |
| `scheduledAt` / `startedAt` / `completedAt` | DateTime | When it was due, began, and finished |
| `deliveryCounts` | Counts | `pending`, `sending`, `sent`, `failed`, `total` — one query regardless of recipient count |
| `deliveries` | Connection | One edge per recipient |

`sends` is ordered by `scheduledAt` descending, so the first edge is **not** necessarily the send
`status` describes. Use `latestSend` for that, or `broadcast sends <id> --real-only`.

### BroadcastSendDelivery Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique delivery identifier (e.g., `bcsd_01ABC...`) |
| `recipient` | Union | `SlackBroadcastSendDeliveryRecipient` (`slackTeamId`, `slackChannelId`, `slackChannelName`) or `EmailBroadcastSendDeliveryRecipient` |
| `status` | Enum | `PENDING`, `SENDING`, `SENT`, `FAILED` |
| `failureReason` | Enum | Why it failed. Null unless `status` is `FAILED` |
| `attempts` | Int | How many times posting was attempted |
| `lastAttemptedAt` | DateTime | When the last attempt started |

Common `failureReason` values: `CHANNEL_NOT_CONNECTED`, `MISSING_SLACK_SCOPES`,
`NOTIFICATION_TITLE_NOT_SET`, `SENDER_NOT_SET`, `SENDER_UNAVAILABLE`, `EMPTY_CONTENT`,
`INVALID_CONTENT`, `INVALID_SLACK_BLOCKS`, `RATE_LIMITED`, `MAX_ATTEMPTS`, `MAX_RETRIES`,
`EMAIL_DELIVERY_NOT_SUPPORTED`, `UNKNOWN`. Every one is terminal — anything worth retrying was
already retried.

---

## BroadcastAudience

A named, reusable set of recipients, resolved to concrete channels at send time rather than when it
is saved. Editing an audience changes who every broadcast using it will reach on its next send.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique audience identifier (e.g., `ba_01ABC...`) |
| `name` | String | Internal name. Never shown to recipients |
| `type` | Enum | `SLACK`. Fixed at creation, and must match the type of any broadcast it is attached to |
| `filters` | Filter | What the audience selects (see below). **No rows at all means every tenant** |
| `isDeleted` | Boolean | Soft-deleted. Excluded from lists, still fetchable by ID |

### Filter tree

The same shape is used by an audience's `filters` and a broadcast's `sendTarget.filters`.

| Dimension | Meaning |
|-----------|---------|
| `tenantIds` | Specific tenants |
| `tierIds` | Every tenant in these tiers |
| `slackChannels` | Channels pinned by id. Nothing re-resolves these |
| `slackChannelNameContains` | Unanchored, case-insensitive channel-name substrings, resolved at send time — so channels created or renamed later are picked up |
| `audienceIds` | Saved audiences. Allowed on a broadcast's target, **rejected inside an audience's own filter** |
| `and` / `or` / `not` | Nested conditions |

Rules that are easy to get wrong:

- Dimensions on one node **AND** together; values within one dimension **OR**.
- An empty dimension does not constrain anything and cannot be written — omit it.
- `and` / `or` nest at most two levels below the root; a third level is rejected.
- `not` may name a single dimension only: no nested `and`/`or`/`not`, no second dimension.
- `audience update --filters-file` **replaces** the stored tree wholesale. Read the audience first
  if you only mean to add a row.

### Send target

| Field | Description |
|-------|-------------|
| `scope` | `ALL_TENANTS` (every tenant with a connected channel; rejects `filters`) or `MATCHING` (requires `filters`) |
| `filters` | The filter tree above |
| `recipients` | Recipients named outright, added to whatever `filters` resolved to |
| `excludeRecipients` | Subtracted last, so a broadcast can drop one recipient without editing the audience that pulled it in |

A recipient the workspace cannot reach is dropped, not errored.

`broadcast recipients` previews who a target resolves to **right now**: it returns `count`, an
`emptyReason` when the count is zero (`NO_TENANTS_MATCHED`, `NO_RECIPIENTS_RESOLVED`,
`EXCLUDED_BY_AUDIENCE`), and the channels themselves. The number moves as tenants, tiers, tenant
fields and connected channels change, so it is not a promise about a later send.

### Permissions

Broadcast commands need an API key with `broadcast:read` / `:create` / `:edit` / `:delete` and
`broadcastAudience:read` / `:create` / `:edit` / `:delete`. A key missing one gets a permission
error, not an empty list — do not read "no broadcasts" into it.

---

## DateTime Format

All datetime fields return an object with:

```json
{
  "iso8601": "2024-01-15T10:30:00.000Z"
}
```

When providing datetime values (e.g., for snooze), use ISO 8601 format.
