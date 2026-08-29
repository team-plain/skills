#!/bin/bash
# Plain API CLI - Interact with Plain customer support platform
# Requires: PLAIN_API_KEY environment variable, curl, jq

set -euo pipefail

API_URL="${PLAIN_API_URL:-https://core-api.uk.plain.com/graphql/v1}"

# Check required dependencies
check_deps() {
    command -v curl >/dev/null 2>&1 || { echo "Error: curl is required" >&2; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "Error: jq is required" >&2; exit 1; }
    [ -n "${PLAIN_API_KEY:-}" ] || { echo "Error: PLAIN_API_KEY environment variable is required" >&2; exit 1; }
}

# Execute GraphQL query
gql() {
    local query="$1"
    local empty_json='{}'
    local variables="${2:-$empty_json}"

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

# ============================================================================
# CUSTOMERS (READ ONLY)
# ============================================================================

customer_get() {
    local id="$1"
    gql 'query($id: ID!) { customer(customerId: $id) { id fullName shortName email { email isVerified } externalId status company { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

customer_get_by_email() {
    local email="$1"
    gql 'query($email: String!) { customerByEmail(email: $email) { id fullName shortName email { email isVerified } externalId status company { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"email\": \"$email\"}"
}

customer_get_by_external_id() {
    local external_id="$1"
    gql 'query($externalId: ID!) { customerByExternalId(externalId: $externalId) { id fullName shortName email { email isVerified } externalId status company { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"externalId\": \"$external_id\"}"
}

customer_list() {
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { customers(first: \$first) { edges { node { id fullName email { email } externalId status company { id name } } } pageInfo { hasNextPage endCursor } totalCount } }" \
        "{\"first\": $first}"
}

customer_search() {
    local query="$1"
    shift || true
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql 'query($term: String!, $first: Int!) { searchCustomers(searchQuery: {or: [{fullName: {caseInsensitiveContains: $term}}, {email: {caseInsensitiveContains: $term}}]}, first: $first) { edges { node { id fullName email { email } externalId status company { id name } } } } }' \
        "{\"term\": \"$query\", \"first\": $first}"
}

# Convert priority label to number for API filters
priority_to_number() {
    case "$1" in
        urgent) echo 0 ;;
        high) echo 1 ;;
        normal) echo 2 ;;
        low) echo 3 ;;
        0|1|2|3) echo "$1" ;;
        *) echo "Error: Invalid priority '$1'. Use: urgent, high, normal, low" >&2; exit 1 ;;
    esac
}

# Map numeric priority values (0-3) to labels in JSON output
map_priorities() {
    jq '
def priority_label:
  if . == 0 then "urgent"
  elif . == 1 then "high"
  elif . == 2 then "normal"
  elif . == 3 then "low"
  else .
  end;
walk(if type == "object" then
  (if has("priority") and (.priority | type) == "number" then .priority |= priority_label else . end) |
  (if has("previousPriority") and (.previousPriority | type) == "number" then .previousPriority |= priority_label else . end) |
  (if has("nextPriority") and (.nextPriority | type) == "number" then .nextPriority |= priority_label else . end)
else . end)'
}

# ============================================================================
# THREADS (READ + WRITE)
# ============================================================================

thread_note() {
    local thread_id=""
    local text=""
    local markdown=""
    local text_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --text) text="$2"; shift 2 ;;
            --markdown) markdown="$2"; shift 2 ;;
            --text-file) text_file="$2"; shift 2 ;;
            '') shift ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    # Read text from file if specified
    if [[ -n "$text_file" ]]; then
        if [[ ! -f "$text_file" ]]; then
            echo "Error: Text file not found: $text_file" >&2
            exit 1
        fi
        text=$(cat "$text_file")
    fi

    if [[ -z "$thread_id" ]] || [[ -z "$text" ]]; then
        echo "Error: thread_id and --text (or --text-file) are required" >&2
        echo "Usage: plain-api.sh thread note <thread_id> --text \"Note text\"" >&2
        exit 1
    fi

    # First, get the thread to find the customer ID
    local thread_result
    thread_result=$(gql 'query($id: ID!) { thread(threadId: $id) { id customer { id } } }' "{\"id\": \"$thread_id\"}")

    local customer_id
    customer_id=$(echo "$thread_result" | jq -r '.data.thread.customer.id // empty')

    if [[ -z "$customer_id" ]]; then
        echo "Error: Could not find thread or customer for thread $thread_id" >&2
        echo "$thread_result" | jq . >&2
        exit 1
    fi

    # Build input JSON using jq for proper escaping
    local input
    input=$(jq -n \
        --arg customerId "$customer_id" \
        --arg threadId "$thread_id" \
        --arg text "$text" \
        '{customerId: $customerId, threadId: $threadId, text: $text}')

    # Add optional markdown field
    if [[ -n "$markdown" ]]; then
        input=$(echo "$input" | jq --arg md "$markdown" '. + {markdown: $md}')
    fi

    local query='mutation CreateNote($input: CreateNoteInput!) { createNote(input: $input) { note { id text } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

thread_get() {
    local id="$1"
    gql 'query($id: ID!) { thread(threadId: $id) { id title description previewText status priority externalId channel customer { id fullName email { email } } assignedTo { ... on User { id fullName } ... on MachineUser { id fullName } } labels { id labelType { id name } } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}" | map_priorities
}

thread_list() {
    local first=10
    local status_filter=""
    local priority_filter=""
    local customer_filter=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            --status)
                if [[ "$2" != "all" ]]; then
                    status_filter="$2"
                fi
                shift 2 ;;
            --priority) priority_filter="$(priority_to_number "$2")"; shift 2 ;;
            --customer) customer_filter="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local filter_parts=()
    if [[ -n "$status_filter" ]]; then
        filter_parts+=("\"statuses\": [\"$status_filter\"]")
    fi
    if [[ -n "$priority_filter" ]]; then
        filter_parts+=("\"priorities\": [$priority_filter]")
    fi
    if [[ -n "$customer_filter" ]]; then
        filter_parts+=("\"customerIds\": [\"$customer_filter\"]")
    fi

    local filter="{}"
    if [[ ${#filter_parts[@]} -gt 0 ]]; then
        filter="{$(IFS=,; echo "${filter_parts[*]}")}"
    fi

    gql "query(\$first: Int!, \$filters: ThreadsFilter) { threads(first: \$first, filters: \$filters) { edges { node { id title status priority customer { id fullName } assignedTo { ... on User { id fullName } ... on MachineUser { id fullName } } createdAt { iso8601 } } } pageInfo { hasNextPage endCursor } totalCount } }" \
        "{\"first\": $first, \"filters\": $filter}" | map_priorities
}

thread_search() {
    local query="$1"
    shift || true
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql 'query($term: String!, $first: Int!) { searchThreads(searchQuery: {term: $term}, first: $first) { edges { node { thread { id title status priority customer { id fullName } assignedTo { ... on User { id fullName } } createdAt { iso8601 } } } } } }' \
        "{\"term\": \"$query\", \"first\": $first}" | map_priorities
}

thread_timeline() {
    local thread_id=""
    local first=20
    local after=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            --after) after="$2"; shift 2 ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    if [[ -z "$thread_id" ]]; then
        echo "Error: thread_id is required" >&2
        exit 1
    fi

    local after_param=""
    if [[ -n "$after" ]]; then
        after_param=", \"after\": \"$after\""
    fi

    # Build comprehensive timeline query with all 24 entry types
    local query='query($threadId: ID!, $first: Int!, $after: String) {
      thread(threadId: $threadId) {
        timelineEntries(first: $first, after: $after) {
          edges {
            cursor
            node {
              id
              customerId
              threadId
              timestamp { iso8601 }
              actor {
                __typename
                ... on UserActor { userId }
                ... on SystemActor { systemId }
                ... on MachineUserActor { machineUserId machineUser { id fullName } }
                ... on CustomerActor { customerId customer { id fullName email { email } } }
                ... on DeletedCustomerActor { customerId }
              }
              entry {
                __typename
                ... on NoteEntry {
                  noteId
                  text
                  markdown
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                }
                ... on ChatEntry {
                  chatId
                  chatText: text
                  customerReadAt { iso8601 }
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                }
                ... on EmailEntry {
                  emailId
                  subject
                  textContent
                  hasMoreTextContent
                  markdownContent
                  hasMoreMarkdownContent
                  from { name email }
                  to { name email }
                  additionalRecipients { name email }
                  hiddenRecipients { name email }
                  authenticity
                  isStartOfThread
                  sentAt { iso8601 }
                  receivedAt { iso8601 }
                  sendStatus
                  category
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                }
                ... on CustomEntry {
                  externalId
                  title
                  type
                  components {
                    __typename
                    ... on ComponentText { text textColor textSize }
                    ... on ComponentPlainText { plainText plainTextColor plainTextSize }
                    ... on ComponentLinkButton { linkButtonLabel linkButtonUrl }
                    ... on ComponentBadge { badgeLabel badgeColor }
                    ... on ComponentDivider { dividerSpacingSize }
                    ... on ComponentSpacer { spacerSize }
                    ... on ComponentCopyButton { copyButtonValue copyButtonTooltipLabel }
                  }
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                }
                ... on ThreadAssignmentTransitionedEntry {
                  previousAssignee {
                    __typename
                    ... on User { id fullName }
                    ... on MachineUser { id fullName }
                    ... on System { id }
                  }
                  nextAssignee {
                    __typename
                    ... on User { id fullName }
                    ... on MachineUser { id fullName }
                    ... on System { id }
                  }
                }
                ... on ThreadAdditionalAssigneesTransitionedEntry {
                  previousAssignees {
                    __typename
                    ... on User { id fullName }
                    ... on MachineUser { id fullName }
                    ... on System { id }
                  }
                  nextAssignees {
                    __typename
                    ... on User { id fullName }
                    ... on MachineUser { id fullName }
                    ... on System { id }
                  }
                }
                ... on ThreadStatusTransitionedEntry {
                  nextStatus
                  nextStatusDetail {
                    __typename
                    ... on ThreadStatusDetailCreated { createdAt { iso8601 } }
                    ... on ThreadStatusDetailSnoozed { snoozedAt { iso8601 } snoozedUntil { iso8601 } }
                    ... on ThreadStatusDetailUnsnoozed { snoozedAt { iso8601 } }
                    ... on ThreadStatusDetailNewReply { newReplyAt { iso8601 } }
                    ... on ThreadStatusDetailReplied { repliedAt { iso8601 } }
                    ... on ThreadStatusDetailWaitingForCustomer { statusChangedAt { iso8601 } }
                    ... on ThreadStatusDetailWaitingForDuration { statusChangedAt { iso8601 } waitingUntil { iso8601 } }
                    ... on ThreadStatusDetailInProgress { statusChangedAt { iso8601 } }
                    ... on ThreadStatusDetailThreadDiscussionResolved { threadDiscussionId statusChangedAt { iso8601 } }
                    ... on ThreadStatusDetailThreadLinkUpdated { updatedAt { iso8601 } threadLinkLinearIssueId: linearIssueId }
                    ... on ThreadStatusDetailLinearUpdated { updatedAt { iso8601 } deprecatedLinearIssueId: linearIssueId }
                  }
                }
                ... on ThreadPriorityChangedEntry {
                  previousPriority
                  nextPriority
                }
                ... on ThreadLabelsChangedEntry {
                  previousLabels { id labelType { id name } }
                  nextLabels { id labelType { id name } }
                }
                ... on ThreadEventEntry {
                  timelineEventId
                  title
                  customerId
                  externalId
                  components {
                    __typename
                    ... on ComponentText { text textColor textSize }
                    ... on ComponentPlainText { plainText plainTextColor plainTextSize }
                    ... on ComponentLinkButton { linkButtonLabel linkButtonUrl }
                    ... on ComponentBadge { badgeLabel badgeColor }
                    ... on ComponentDivider { dividerSpacingSize }
                    ... on ComponentSpacer { spacerSize }
                    ... on ComponentCopyButton { copyButtonValue copyButtonTooltipLabel }
                  }
                }
                ... on CustomerEventEntry {
                  timelineEventId
                  title
                  customerId
                  externalId
                  components {
                    __typename
                    ... on ComponentText { text textColor textSize }
                    ... on ComponentPlainText { plainText plainTextColor plainTextSize }
                    ... on ComponentLinkButton { linkButtonLabel linkButtonUrl }
                    ... on ComponentBadge { badgeLabel badgeColor }
                    ... on ComponentDivider { dividerSpacingSize }
                    ... on ComponentSpacer { spacerSize }
                    ... on ComponentCopyButton { copyButtonValue copyButtonTooltipLabel }
                  }
                }
                ... on SlackMessageEntry {
                  slackMessageLink
                  slackWebMessageLink
                  text
                  lastEditedOnSlackAt { iso8601 }
                  deletedOnSlackAt { iso8601 }
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                  reactions { name imageUrl }
                }
                ... on SlackReplyEntry {
                  slackMessageLink
                  slackWebMessageLink
                  text
                  lastEditedOnSlackAt { iso8601 }
                  deletedOnSlackAt { iso8601 }
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                  reactions { name imageUrl }
                }
                ... on ServiceLevelAgreementStatusTransitionedEntry {
                  previousSlaStatus: previousStatus
                  nextSlaStatus: nextStatus
                  serviceLevelAgreement {
                    __typename
                    id
                    useBusinessHoursOnly
                    threadPriorityFilter
                    ... on FirstResponseTimeServiceLevelAgreement { firstResponseTimeMinutes }
                    ... on NextResponseTimeServiceLevelAgreement { nextResponseTimeMinutes }
                  }
                }
                ... on ThreadDiscussionEntry {
                  threadDiscussionId
                  discussionType
                  slackChannelName
                  slackMessageLink
                  emailRecipients
                  customerId
                }
                ... on ThreadDiscussionResolvedEntry {
                  threadDiscussionId
                  discussionType
                  slackChannelName
                  slackMessageLink
                  emailRecipients
                  customerId
                  resolvedAt { iso8601 }
                }
                ... on MSTeamsMessageEntry {
                  msTeamsMessageId
                  msTeamsMessageLink
                  text
                  markdownContent
                  customerId
                  lastEditedOnMsTeamsAt { iso8601 }
                  deletedOnMsTeamsAt { iso8601 }
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                }
                ... on DiscordMessageEntry {
                  discordMessageId
                  discordMessageLink
                  markdownContent
                  customerId
                  lastEditedOnDiscordAt { iso8601 }
                  deletedOnDiscordAt { iso8601 }
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                }
                ... on LinearIssueThreadLinkStateTransitionedEntry {
                  linearIssueId
                  previousLinearStateId
                  nextLinearStateId
                }
                ... on ThreadLinkCreatedEntry {
                  threadLink {
                    id
                    title
                    url
                    description
                    status
                    createdAt { iso8601 }
                    ... on LinearIssueThreadLink { linearIssueId linearIssueIdentifier }
                    ... on JiraIssueThreadLink { jiraIssueId jiraIssueKey }
                    ... on PlainThreadThreadLink { plainThreadId }
                    ... on PlainTaskThreadLink { plainTaskId }
                    ... on GenericThreadLink { sourceType sourceId }
                  }
                }
                ... on ThreadLinkUpdatedEntry {
                  threadLink {
                    id
                    title
                    url
                    description
                    status
                    ... on LinearIssueThreadLink { linearIssueId linearIssueIdentifier }
                    ... on JiraIssueThreadLink { jiraIssueId jiraIssueKey }
                    ... on PlainThreadThreadLink { plainThreadId }
                    ... on PlainTaskThreadLink { plainTaskId }
                    ... on GenericThreadLink { sourceType sourceId }
                  }
                  previousThreadLink {
                    id
                    title
                    url
                    status
                  }
                }
                ... on ThreadLinkDeletedEntry {
                  threadLink {
                    id
                    title
                    url
                    status
                    ... on LinearIssueThreadLink { linearIssueId linearIssueIdentifier }
                    ... on JiraIssueThreadLink { jiraIssueId jiraIssueKey }
                    ... on PlainThreadThreadLink { plainThreadId }
                    ... on PlainTaskThreadLink { plainTaskId }
                    ... on GenericThreadLink { sourceType sourceId }
                  }
                }
                ... on HelpCenterAiConversationMessageEntry {
                  messageId
                  helpCenterId
                  messageMarkdown: markdown
                }
                ... on CustomerSurveyRequestedEntry {
                  customerId
                  customerSurveyId
                  surveyResponseId
                  surveyResponsePublicId
                }
              }
            }
          }
          pageInfo {
            hasNextPage
            hasPreviousPage
            startCursor
            endCursor
          }
        }
      }
    }'

    gql "$query" "{\"threadId\": \"$thread_id\", \"first\": $first$after_param}" | map_priorities
}

# Parse a GitHub issue/PR ref into Plain's canonical sourceId "owner/repo/N".
# Accepts: https://github.com/owner/repo/{issues,pull}/N, owner/repo#N, owner/repo/N
parse_github_ref() {
    local ref="$1"
    if [[ "$ref" =~ ^https?://github\.com/([^/]+)/([^/]+)/(issues|pull)/([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/${BASH_REMATCH[4]}"
        return 0
    fi
    if [[ "$ref" =~ ^([^/]+)/([^/]+)#([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/${BASH_REMATCH[3]}"
        return 0
    fi
    if [[ "$ref" =~ ^([^/]+)/([^/]+)/([0-9]+)$ ]]; then
        echo "$ref"
        return 0
    fi
    return 1
}

thread_link_add() {
    local thread_id=""
    local ref=""
    local source="github_issue"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --source) source="$2"; shift 2 ;;
            '') shift ;;
            *)
                if [[ -z "$thread_id" ]]; then thread_id="$1"
                else ref="$1"
                fi
                shift ;;
        esac
    done

    if [[ -z "$thread_id" ]] || [[ -z "$ref" ]]; then
        echo "Error: thread_id and ref are required" >&2
        echo "Usage: plain-api.sh thread link add <thread_id> <ref> [--source github_issue]" >&2
        echo "  ref formats (github_issue): https://github.com/owner/repo/issues/N, owner/repo#N, owner/repo/N" >&2
        exit 1
    fi

    local source_id
    if [[ "$source" == "github_issue" ]]; then
        if ! source_id=$(parse_github_ref "$ref"); then
            echo "Error: invalid GitHub ref '$ref'" >&2
            echo "  Expected: https://github.com/owner/repo/issues/N, owner/repo#N, or owner/repo/N" >&2
            exit 1
        fi
    else
        source_id="$ref"
    fi

    local input
    input=$(jq -n \
        --arg threadId "$thread_id" \
        --arg sourceId "$source_id" \
        --arg sourceType "$source" \
        '{threadId: $threadId, sourceId: $sourceId, sourceType: $sourceType}')

    local query='mutation($input: CreateThreadLinkInput!) { createThreadLink(input: $input) { threadLink { id sourceType sourceId title url description status linkType createdAt { iso8601 } } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

thread_link_list() {
    local thread_id="$1"
    if [[ -z "$thread_id" ]]; then
        echo "Error: thread_id is required" >&2
        echo "Usage: plain-api.sh thread link list <thread_id>" >&2
        exit 1
    fi
    gql 'query($id: ID!) { thread(threadId: $id) { links(first: 50) { edges { node { id sourceType sourceId title url description status linkType createdAt { iso8601 } } } } } }' \
        "{\"id\": \"$thread_id\"}"
}

# ============================================================================
# COMPANIES (READ ONLY)
# ============================================================================

company_get() {
    local id="$1"
    gql 'query($id: ID!) { company(companyId: $id) { id name domainName createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

company_list() {
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { companies(first: \$first) { edges { node { id name domainName } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}"
}

# ============================================================================
# TENANTS (READ ONLY)
# ============================================================================

tenant_get() {
    local id="$1"
    gql 'query($id: ID!) { tenant(tenantId: $id) { id name externalId createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

tenant_list() {
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { tenants(first: \$first) { edges { node { id name externalId } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}"
}

# ============================================================================
# LABELS (READ ONLY)
# ============================================================================

label_list() {
    local first=20
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { labelTypes(first: \$first) { edges { node { id name isArchived } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}"
}

# ============================================================================
# HELP CENTER (READ ONLY)
# ============================================================================

helpcenter_list() {
    gql '{ helpCenters(first: 50) { edges { node { id publicName internalName description type } } } }' '{}'
}

helpcenter_get() {
    local id="$1"
    gql 'query($id: ID!) { helpCenter(id: $id) { id publicName internalName description type articleGroups(first: 50) { edges { node { id name slug } } } articles(first: 50) { edges { node { id title slug status } } } } }' \
        "{\"id\": \"$id\"}"
}

helpcenter_articles() {
    local help_center_id="$1"
    shift || true
    local first=20
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql 'query($id: ID!, $first: Int!) { helpCenter(id: $id) { articles(first: $first) { edges { node { id title slug status description contentHtml articleGroup { id name } } } pageInfo { hasNextPage endCursor } } } }' \
        "{\"id\": \"$help_center_id\", \"first\": $first}"
}

helpcenter_article_get() {
    local id="$1"
    gql 'query($id: ID!) { helpCenterArticle(id: $id) { id title description contentHtml slug status articleGroup { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

helpcenter_article_get_by_slug() {
    local help_center_id="$1"
    local slug="$2"
    gql 'query($helpCenterId: ID!, $slug: String!) { helpCenterArticleBySlug(helpCenterId: $helpCenterId, slug: $slug) { id title description contentHtml slug status articleGroup { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"helpCenterId\": \"$help_center_id\", \"slug\": \"$slug\"}"
}

helpcenter_article_upsert() {
    local help_center_id=""
    local article_id=""
    local title=""
    local description=""
    local content=""
    local content_file=""
    local group_id=""
    local status="DRAFT"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --id) article_id="$2"; shift 2 ;;
            --title) title="$2"; shift 2 ;;
            --description) description="$2"; shift 2 ;;
            --content) content="$2"; shift 2 ;;
            --content-file) content_file="$2"; shift 2 ;;
            --group) group_id="$2"; shift 2 ;;
            --status) status="$2"; shift 2 ;;
            '') shift ;;  # Skip empty arguments
            *) help_center_id="$1"; shift ;;
        esac
    done

    # Read content from file if specified
    if [[ -n "$content_file" ]]; then
        if [[ ! -f "$content_file" ]]; then
            echo "Error: Content file not found: $content_file" >&2
            exit 1
        fi
        content=$(cat "$content_file")
    fi

    if [[ -z "$help_center_id" ]] || [[ -z "$title" ]] || [[ -z "$description" ]] || [[ -z "$content" ]]; then
        echo "Error: help_center_id, --title, --description, and --content (or --content-file) are required" >&2
        exit 1
    fi

    # Validate status
    if [[ "$status" != "DRAFT" ]] && [[ "$status" != "PUBLISHED" ]]; then
        echo "Error: --status must be DRAFT or PUBLISHED" >&2
        exit 1
    fi

    # Get workspace ID for constructing the link
    local workspace_result
    workspace_result=$(gql '{ myWorkspace { id } }' '{}')
    local workspace_id
    workspace_id=$(echo "$workspace_result" | jq -r '.data.myWorkspace.id')

    # Build input JSON using jq for proper escaping
    local input
    input=$(jq -n \
        --arg helpCenterId "$help_center_id" \
        --arg title "$title" \
        --arg description "$description" \
        --arg contentHtml "$content" \
        --arg status "$status" \
        '{helpCenterId: $helpCenterId, title: $title, description: $description, contentHtml: $contentHtml, status: $status}')

    # Add optional fields
    if [[ -n "$article_id" ]]; then
        input=$(echo "$input" | jq --arg id "$article_id" '. + {helpCenterArticleId: $id}')
    fi
    if [[ -n "$group_id" ]]; then
        input=$(echo "$input" | jq --arg id "$group_id" '. + {helpCenterArticleGroupId: $id}')
    fi

    local query='mutation($input: UpsertHelpCenterArticleInput!) { upsertHelpCenterArticle(input: $input) { helpCenterArticle { id title slug status } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    local result
    result=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')")

    # Extract article ID and construct link
    local new_article_id
    new_article_id=$(echo "$result" | jq -r '.data.upsertHelpCenterArticle.helpCenterArticle.id // empty')

    if [[ -n "$new_article_id" ]]; then
        local link="https://app.plain.com/workspace/${workspace_id}/help-center/${help_center_id}/articles/${new_article_id}/"
        echo "$result" | jq --arg link "$link" '.link = $link'
    else
        echo "$result"
    fi
}

helpcenter_group_get() {
    local id="$1"
    gql 'query($id: ID!) { helpCenterArticleGroup(id: $id) { id name slug parentArticleGroup { id name } articles(first: 50) { edges { node { id title slug status } } } childArticleGroups(first: 50) { edges { node { id name slug } } } } }' \
        "{\"id\": \"$id\"}"
}

helpcenter_group_create() {
    local help_center_id=""
    local name=""
    local parent_id=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            --parent) parent_id="$2"; shift 2 ;;
            *) help_center_id="$1"; shift ;;
        esac
    done

    if [[ -z "$help_center_id" ]] || [[ -z "$name" ]]; then
        echo "Error: help_center_id and --name are required" >&2
        exit 1
    fi

    local input="{\"helpCenterId\": \"$help_center_id\", \"name\": \"$name\""
    [[ -n "$parent_id" ]] && input="$input, \"parentHelpCenterArticleGroupId\": \"$parent_id\""
    input="$input}"

    gql 'mutation($input: CreateHelpCenterArticleGroupInput!) { createHelpCenterArticleGroup(input: $input) { helpCenterArticleGroup { id name slug } error { message code } } }' \
        "{\"input\": $input}"
}

helpcenter_group_update() {
    local group_id=""
    local name=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            *) group_id="$1"; shift ;;
        esac
    done

    if [[ -z "$group_id" ]] || [[ -z "$name" ]]; then
        echo "Error: group_id and --name are required" >&2
        exit 1
    fi

    gql 'mutation($input: UpdateHelpCenterArticleGroupInput!) { updateHelpCenterArticleGroup(input: $input) { helpCenterArticleGroup { id name slug } error { message code } } }' \
        "{\"input\": {\"helpCenterArticleGroupId\": \"$group_id\", \"name\": \"$name\"}}"
}

helpcenter_group_delete() {
    local id="$1"
    gql 'mutation($input: DeleteHelpCenterArticleGroupInput!) { deleteHelpCenterArticleGroup(input: $input) { error { message code } } }' \
        "{\"input\": {\"helpCenterArticleGroupId\": \"$id\"}}"
}

# ============================================================================
# TIERS & SLAs (READ ONLY)
# ============================================================================

tier_list() {
    local first=20
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { tiers(first: \$first) { edges { node { id name externalId color isDefault defaultThreadPriority serviceLevelAgreements { ... on FirstResponseTimeServiceLevelAgreement { id firstResponseTimeMinutes useBusinessHoursOnly } ... on NextResponseTimeServiceLevelAgreement { id nextResponseTimeMinutes useBusinessHoursOnly } } } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}"
}

tier_get() {
    local id="$1"
    gql 'query($id: ID!) { tier(tierId: $id) { id name externalId color isDefault defaultThreadPriority serviceLevelAgreements { ... on FirstResponseTimeServiceLevelAgreement { id firstResponseTimeMinutes useBusinessHoursOnly threadPriorityFilter } ... on NextResponseTimeServiceLevelAgreement { id nextResponseTimeMinutes useBusinessHoursOnly threadPriorityFilter } } memberships(first: 50) { edges { node { ... on TenantTierMembership { id tenantId } ... on CompanyTierMembership { id companyId } } } totalCount } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

# ============================================================================
# BROADCASTS (READ + WRITE)
# ============================================================================
#
# Scheduling and sending (including test sends) are deliberately not exposed -
# both post real messages to real Slack channels. A human does those in Plain.

# Append a value to a newline-separated accumulator, for repeatable flags.
append_line() {
    if [[ -z "$1" ]]; then printf '%s' "$2"; else printf '%s\n%s' "$1" "$2"; fi
}

# Turn a newline-separated accumulator into a compact JSON array.
json_array_from_lines() {
    printf '%s' "$1" | jq -Rn '[inputs | select(. != "")]'
}

upper() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

# Boolean flags are compared against "true", so an unrecognised value would
# quietly mean false. Reject it instead.
parse_bool() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        true) printf 'true' ;;
        false) printf 'false' ;;
        *) echo "Error: $2 must be true or false, got '$1'" >&2; exit 1 ;;
    esac
}

# A broadcast's content is a serialised Tiptap document. There is no markdown or
# HTML form of it, so plain text has to be wrapped before it can be sent. Blank
# lines separate paragraphs.
tiptap_doc_from_text() {
    jq -cn --arg text "$1" '{
        type: "doc",
        content: ($text | split("\n\n") | map(select(. != "") | {type: "paragraph", content: [{type: "text", text: .}]}))
    }'
}

read_json_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "Error: file not found: $path" >&2
        exit 1
    fi
    if ! jq -e '.' "$path" >/dev/null 2>&1; then
        echo "Error: $path is not valid JSON" >&2
        exit 1
    fi
    jq -c '.' "$path"
}

read_tiptap_content_file() {
    local path="$1"
    local doc
    doc=$(read_json_file "$path")
    if ! printf '%s' "$doc" | jq -e '.type == "doc"' >/dev/null 2>&1; then
        echo "Error: $path is not a Tiptap document (expected JSON with \"type\": \"doc\")" >&2
        exit 1
    fi
    printf '%s' "$doc"
}

# Build a BroadcastAudienceFilterInput from the simple flags. Flat only - and/or/not
# trees have to come from --filters-file.
audience_filters_from_flags() {
    jq -cn \
        --argjson tenantIds "$(json_array_from_lines "$1")" \
        --argjson tierIds "$(json_array_from_lines "$2")" \
        --argjson audienceIds "$(json_array_from_lines "$3")" \
        --argjson slackChannelNameContains "$(json_array_from_lines "$4")" \
        '{tenantIds: $tenantIds, tierIds: $tierIds, audienceIds: $audienceIds, slackChannelNameContains: $slackChannelNameContains}
         | with_entries(select(.value | length > 0))'
}

# Build a BroadcastSendTargetInput. MATCHING requires filters and ALL_TENANTS
# rejects them, so the two never combine.
broadcast_send_target() {
    local all_tenants="$1"
    local filters="$2"

    if [[ "$all_tenants" == "true" ]]; then
        if [[ "$filters" != "{}" ]]; then
            echo "Error: --all-tenants cannot be combined with --audience/--tier/--tenant/--channel-name-contains/--filters-file" >&2
            exit 1
        fi
        printf '%s' '{"scope":"ALL_TENANTS"}'
        return
    fi

    if [[ "$filters" == "{}" ]]; then
        printf '%s' 'null'
        return
    fi

    jq -cn --argjson filters "$filters" '{scope: "MATCHING", filters: $filters}'
}

BROADCAST_ACTOR_FIELDS='__typename ... on UserActor { userId } ... on MachineUserActor { machineUserId } ... on SystemActor { systemId }'
BROADCAST_SENDER_FIELDS='__typename ... on SlackBroadcastSender { user { userId } } ... on PlainWorkspaceBroadcastSender { workspace { id name } }'

# BroadcastAudienceFilter is a tree, and GraphQL needs every level spelled out.
# It nests at most two levels below the root, so three levels covers it.
BROADCAST_FILTER_DIMENSIONS='tenantIds tierIds audienceIds slackChannelNameContains slackChannels { slackTeamId slackChannelId } tenantFields { externalFieldId stringValue booleanValue numberValue stringArrayValue userReferenceValues }'
BROADCAST_FILTER_L2="$BROADCAST_FILTER_DIMENSIONS and { $BROADCAST_FILTER_DIMENSIONS } or { $BROADCAST_FILTER_DIMENSIONS } not { $BROADCAST_FILTER_DIMENSIONS }"
BROADCAST_FILTER_FIELDS="$BROADCAST_FILTER_DIMENSIONS and { $BROADCAST_FILTER_L2 } or { $BROADCAST_FILTER_L2 } not { $BROADCAST_FILTER_L2 }"

BROADCAST_SEND_FIELDS='id status isTest scheduledAt { iso8601 } startedAt { iso8601 } completedAt { iso8601 } deliveryCounts { pending sending sent failed total }'
BROADCAST_DELIVERY_FIELDS='id status failureReason attempts lastAttemptedAt { iso8601 } recipient { __typename ... on SlackBroadcastSendDeliveryRecipient { slackTeamId slackChannelId slackChannelName } ... on EmailBroadcastSendDeliveryRecipient { emailAddress } }'

# Deliberately no `content` - a Tiptap document is large and unreadable in a list.
BROADCAST_SUMMARY_FIELDS="id name notificationTitle type status contentFormat isLinkUnfurlingEnabled isDeleted createdAt { iso8601 } updatedAt { iso8601 } scheduledAt { iso8601 } startedAt { iso8601 } completedAt { iso8601 } latestSend { $BROADCAST_SEND_FIELDS }"
BROADCAST_DETAIL_FIELDS="$BROADCAST_SUMMARY_FIELDS content sender { $BROADCAST_SENDER_FIELDS } sendTarget { scope filters { $BROADCAST_FILTER_FIELDS } recipients { type slackTeamId slackChannelId } excludeRecipients { type slackTeamId slackChannelId } } reactions { emojiName count } deletedAt { iso8601 } createdBy { $BROADCAST_ACTOR_FIELDS } updatedBy { $BROADCAST_ACTOR_FIELDS }"

BROADCAST_AUDIENCE_FIELDS="id name type isDeleted filters { $BROADCAST_FILTER_FIELDS } createdAt { iso8601 } updatedAt { iso8601 } deletedAt { iso8601 } createdBy { $BROADCAST_ACTOR_FIELDS } updatedBy { $BROADCAST_ACTOR_FIELDS }"

BROADCAST_MUTATION_ERROR='error { message code fields { field message type } }'

broadcast_list() {
    local first=10
    local after=""
    local statuses=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --status) statuses=$(append_line "$statuses" "$(upper "$2")"); shift 2 ;;
            --first) first="$2"; shift 2 ;;
            --after) after="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local variables
    variables=$(jq -n \
        --argjson first "$first" \
        --arg after "$after" \
        --argjson statuses "$(json_array_from_lines "$statuses")" \
        '{
            first: $first,
            after: (if $after == "" then null else $after end),
            filters: (if ($statuses | length) > 0 then {statuses: $statuses} else null end)
        }')

    gql "query(\$first: Int!, \$after: String, \$filters: BroadcastsFilter) { broadcasts(filters: \$filters, first: \$first, after: \$after) { edges { cursor node { $BROADCAST_SUMMARY_FIELDS } } pageInfo { hasNextPage endCursor } } }" \
        "$variables"
}

broadcast_get() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Error: broadcast_id is required" >&2
        echo "Usage: plain-api.sh broadcast get bc_01..." >&2
        exit 1
    fi
    gql "query(\$id: ID!) { broadcast(broadcastId: \$id) { $BROADCAST_DETAIL_FIELDS } }" \
        "{\"id\": \"$id\"}"
}

broadcast_search() {
    local name="${1:-}"
    shift || true
    local first=10
    local statuses=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --status) statuses=$(append_line "$statuses" "$(upper "$2")"); shift 2 ;;
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ ${#name} -lt 2 ]]; then
        echo "Error: search term must be at least 2 characters" >&2
        echo "Usage: plain-api.sh broadcast search \"launch\" [--status DRAFT] [--first 10]" >&2
        exit 1
    fi

    local variables
    variables=$(jq -n \
        --arg name "$name" \
        --argjson first "$first" \
        --argjson statuses "$(json_array_from_lines "$statuses")" \
        '{
            name: $name,
            first: $first,
            filters: (if ($statuses | length) > 0 then {statuses: $statuses} else null end)
        }')

    gql "query(\$name: String!, \$first: Int!, \$filters: BroadcastsFilter) { searchBroadcasts(searchQuery: {name: \$name}, filters: \$filters, first: \$first) { edges { cursor node { $BROADCAST_SUMMARY_FIELDS } } pageInfo { hasNextPage endCursor } } }" \
        "$variables"
}

broadcast_sends() {
    local id=""
    local first=20
    local is_test="null"
    local statuses=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --real-only) is_test="false"; shift ;;
            --test-only) is_test="true"; shift ;;
            --status) statuses=$(append_line "$statuses" "$(upper "$2")"); shift 2 ;;
            --first) first="$2"; shift 2 ;;
            '') shift ;;
            --*) echo "Error: unknown option $1" >&2; exit 1 ;;
            *) id="$1"; shift ;;
        esac
    done

    if [[ -z "$id" ]]; then
        echo "Error: broadcast_id is required" >&2
        echo "Usage: plain-api.sh broadcast sends bc_01... [--real-only|--test-only] [--status SENT] [--first 20]" >&2
        exit 1
    fi

    local variables
    variables=$(jq -n \
        --arg id "$id" \
        --argjson first "$first" \
        --argjson isTest "$is_test" \
        --argjson statuses "$(json_array_from_lines "$statuses")" \
        '{
            id: $id,
            first: $first,
            filters: (
                {isTest: $isTest, statuses: (if ($statuses | length) > 0 then $statuses else null end)}
                | with_entries(select(.value != null))
                | if length > 0 then . else null end
            )
        }')

    gql "query(\$id: ID!, \$filters: BroadcastSendsFilter, \$first: Int!) { broadcast(broadcastId: \$id) { id name status sends(filters: \$filters, first: \$first) { edges { cursor node { $BROADCAST_SEND_FIELDS } } pageInfo { hasNextPage endCursor } totalCount } } }" \
        "$variables"
}

broadcast_deliveries() {
    local id=""
    local send_id=""
    local first=50
    local statuses=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --send) send_id="$2"; shift 2 ;;
            --status) statuses=$(append_line "$statuses" "$(upper "$2")"); shift 2 ;;
            --first) first="$2"; shift 2 ;;
            '') shift ;;
            --*) echo "Error: unknown option $1" >&2; exit 1 ;;
            *) id="$1"; shift ;;
        esac
    done

    if [[ -z "$id" ]]; then
        echo "Error: broadcast_id is required" >&2
        echo "Usage: plain-api.sh broadcast deliveries bc_01... [--send bcs_01...] [--status FAILED] [--first 50]" >&2
        exit 1
    fi

    local delivery_filters
    delivery_filters=$(jq -cn --argjson statuses "$(json_array_from_lines "$statuses")" \
        'if ($statuses | length) > 0 then {statuses: $statuses} else null end')

    if [[ -z "$send_id" ]]; then
        gql "query(\$id: ID!, \$filters: BroadcastSendDeliveriesFilter, \$first: Int!) { broadcast(broadcastId: \$id) { id name latestSend { $BROADCAST_SEND_FIELDS deliveries(filters: \$filters, first: \$first) { edges { cursor node { $BROADCAST_DELIVERY_FIELDS } } pageInfo { hasNextPage endCursor } totalCount } } } }" \
            "$(jq -n --arg id "$id" --argjson filters "$delivery_filters" --argjson first "$first" '{id: $id, filters: $filters, first: $first}')"
        return
    fi

    # Deliveries hang off a send, and no root query returns a send by ID. Page
    # `sends` to the one asked for instead: take the cursor of the edge before it
    # and ask for the single edge after that.
    local send_page
    send_page=$(gql 'query($id: ID!) { broadcast(broadcastId: $id) { sends(first: 100) { edges { cursor node { id } } } } }' \
        "{\"id\": \"$id\"}")

    local after
    after=$(printf '%s' "$send_page" | jq -r --arg sendId "$send_id" '
        (.data.broadcast.sends.edges // []) as $edges
        | ($edges | map(.node.id) | index($sendId)) as $i
        | if $i == null then "NOT_FOUND" elif $i == 0 then "" else $edges[$i - 1].cursor end')

    if [[ "$after" == "NOT_FOUND" ]]; then
        echo "Error: send $send_id is not among the 100 most recent sends of $id" >&2
        exit 1
    fi

    gql "query(\$id: ID!, \$after: String, \$filters: BroadcastSendDeliveriesFilter, \$first: Int!) { broadcast(broadcastId: \$id) { id name sends(first: 1, after: \$after) { edges { node { $BROADCAST_SEND_FIELDS deliveries(filters: \$filters, first: \$first) { edges { cursor node { $BROADCAST_DELIVERY_FIELDS } } pageInfo { hasNextPage endCursor } totalCount } } } } } }" \
        "$(jq -n --arg id "$id" --arg after "$after" --argjson filters "$delivery_filters" --argjson first "$first" \
            '{id: $id, after: (if $after == "" then null else $after end), filters: $filters, first: $first}')"
}

broadcast_recipients() {
    local all_tenants="false"
    local audiences=""
    local tiers=""
    local tenants=""
    local channel_names=""
    local filters_file=""
    local search=""
    local first=25

    while [[ $# -gt 0 ]]; do
        case $1 in
            --all-tenants) all_tenants="true"; shift ;;
            --audience) audiences=$(append_line "$audiences" "$2"); shift 2 ;;
            --tier) tiers=$(append_line "$tiers" "$2"); shift 2 ;;
            --tenant) tenants=$(append_line "$tenants" "$2"); shift 2 ;;
            --channel-name-contains) channel_names=$(append_line "$channel_names" "$2"); shift 2 ;;
            --filters-file) filters_file="$2"; shift 2 ;;
            --search) search="$2"; shift 2 ;;
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local filters
    if [[ -n "$filters_file" ]]; then
        filters=$(read_json_file "$filters_file")
    else
        filters=$(audience_filters_from_flags "$tenants" "$tiers" "$audiences" "$channel_names")
    fi

    local send_target
    send_target=$(broadcast_send_target "$all_tenants" "$filters")

    if [[ "$send_target" == "null" ]]; then
        echo "Error: pass --all-tenants, or at least one of --audience/--tier/--tenant/--channel-name-contains/--filters-file" >&2
        exit 1
    fi

    local variables
    variables=$(jq -n \
        --argjson sendTarget "$send_target" \
        --arg search "$search" \
        --argjson first "$first" \
        '{
            input: {type: "SLACK", sendTarget: $sendTarget},
            search: (if $search == "" then null else $search end),
            first: $first
        }')

    gql 'query($input: BroadcastSendTargetRecipientsInput!, $first: Int!, $search: String) { broadcastSendTargetRecipients(input: $input) { count emptyReason recipients(first: $first, searchQuery: $search) { edges { node { id slackTeamId slackChannelId name isEnabled isPrivate } } pageInfo { hasNextPage endCursor } } } }' \
        "$variables"
}

broadcast_create() {
    local name=""
    local notification_title=""
    local text=""
    local content_file=""
    local sender_type=""
    local sender_user=""
    local link_unfurling=""
    local all_tenants="false"
    local audiences=""
    local tiers=""
    local tenants=""
    local channel_names=""
    local filters_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            --notification-title) notification_title="$2"; shift 2 ;;
            --text) text="$2"; shift 2 ;;
            --content-file) content_file="$2"; shift 2 ;;
            --sender-type) sender_type="$(upper "$2")"; shift 2 ;;
            --sender-user) sender_user="$2"; shift 2 ;;
            --link-unfurling) link_unfurling="$(parse_bool "$2" --link-unfurling)"; shift 2 ;;
            --all-tenants) all_tenants="true"; shift ;;
            --audience) audiences=$(append_line "$audiences" "$2"); shift 2 ;;
            --tier) tiers=$(append_line "$tiers" "$2"); shift 2 ;;
            --tenant) tenants=$(append_line "$tenants" "$2"); shift 2 ;;
            --channel-name-contains) channel_names=$(append_line "$channel_names" "$2"); shift 2 ;;
            --filters-file) filters_file="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$name" ]]; then
        echo "Error: --name is required" >&2
        echo "Usage: plain-api.sh broadcast create --name \"Launch\" --text \"Body\" [--notification-title \"Title\"]" >&2
        exit 1
    fi
    if [[ -z "$text" ]] && [[ -z "$content_file" ]]; then
        echo "Error: --text or --content-file is required" >&2
        exit 1
    fi

    local content
    if [[ -n "$content_file" ]]; then
        content=$(read_tiptap_content_file "$content_file")
    else
        content=$(tiptap_doc_from_text "$text")
    fi

    if [[ -n "$sender_user" ]] && [[ -z "$sender_type" ]]; then
        sender_type="PLAIN_USER"
    fi

    local filters
    if [[ -n "$filters_file" ]]; then
        filters=$(read_json_file "$filters_file")
    else
        filters=$(audience_filters_from_flags "$tenants" "$tiers" "$audiences" "$channel_names")
    fi

    local send_target
    send_target=$(broadcast_send_target "$all_tenants" "$filters")

    local input
    input=$(jq -n \
        --arg name "$name" \
        --arg notificationTitle "$notification_title" \
        --arg content "$content" \
        --arg senderType "$sender_type" \
        --arg senderUserId "$sender_user" \
        --arg linkUnfurling "$link_unfurling" \
        --argjson sendTarget "$send_target" \
        '{
            name: $name,
            content: $content,
            contentFormat: "TIPTAP",
            type: "SLACK",
            notificationTitle: (if $notificationTitle == "" then null else $notificationTitle end),
            senderType: (if $senderType == "" then null else $senderType end),
            senderUserId: (if $senderUserId == "" then null else $senderUserId end),
            isLinkUnfurlingEnabled: (if $linkUnfurling == "" then null else ($linkUnfurling == "true") end),
            sendTarget: $sendTarget
        }
        | with_entries(select(.value != null))')

    gql "mutation(\$input: CreateBroadcastInput!) { createBroadcast(input: \$input) { broadcast { $BROADCAST_SUMMARY_FIELDS } $BROADCAST_MUTATION_ERROR } }" \
        "$(jq -n --argjson input "$input" '{input: $input}')"
}

broadcast_update() {
    local id=""
    local name=""
    local notification_title=""
    local set_notification_title="false"
    local text=""
    local content_file=""
    local sender_type=""
    local sender_user=""
    local link_unfurling=""
    local all_tenants="false"
    local audiences=""
    local tiers=""
    local tenants=""
    local channel_names=""
    local filters_file=""
    local set_target="false"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            --notification-title) notification_title="$2"; set_notification_title="true"; shift 2 ;;
            --text) text="$2"; shift 2 ;;
            --content-file) content_file="$2"; shift 2 ;;
            --sender-type) sender_type="$(upper "$2")"; shift 2 ;;
            --sender-user) sender_user="$2"; shift 2 ;;
            --link-unfurling) link_unfurling="$(parse_bool "$2" --link-unfurling)"; shift 2 ;;
            --all-tenants) all_tenants="true"; set_target="true"; shift ;;
            --audience) audiences=$(append_line "$audiences" "$2"); set_target="true"; shift 2 ;;
            --tier) tiers=$(append_line "$tiers" "$2"); set_target="true"; shift 2 ;;
            --tenant) tenants=$(append_line "$tenants" "$2"); set_target="true"; shift 2 ;;
            --channel-name-contains) channel_names=$(append_line "$channel_names" "$2"); set_target="true"; shift 2 ;;
            --filters-file) filters_file="$2"; set_target="true"; shift 2 ;;
            '') shift ;;
            --*) echo "Error: unknown option $1" >&2; exit 1 ;;
            *) id="$1"; shift ;;
        esac
    done

    if [[ -z "$id" ]]; then
        echo "Error: broadcast_id is required" >&2
        echo "Usage: plain-api.sh broadcast update bc_01... [--name ...] [--notification-title ...] [--text ...]" >&2
        exit 1
    fi

    local content=""
    if [[ -n "$content_file" ]]; then
        content=$(read_tiptap_content_file "$content_file")
    elif [[ -n "$text" ]]; then
        content=$(tiptap_doc_from_text "$text")
    fi

    if [[ -n "$sender_user" ]] && [[ -z "$sender_type" ]]; then
        sender_type="PLAIN_USER"
    fi

    local send_target="null"
    if [[ "$set_target" == "true" ]]; then
        local filters
        if [[ -n "$filters_file" ]]; then
            filters=$(read_json_file "$filters_file")
        else
            filters=$(audience_filters_from_flags "$tenants" "$tiers" "$audiences" "$channel_names")
        fi
        send_target=$(broadcast_send_target "$all_tenants" "$filters")
        # Empty filters would drop sendTarget from the input and leave the stored
        # target untouched, so the update would look like it worked and not have.
        if [[ "$send_target" == "null" ]]; then
            echo "Error: the target flags resolved to nothing - pass --all-tenants, or an --audience/--tier/--tenant/--channel-name-contains/--filters-file with at least one value" >&2
            exit 1
        fi
    fi

    # Every field is a wrapper input: only the ones actually passed are sent, so
    # an omitted flag leaves the stored value alone rather than clearing it.
    local input
    input=$(jq -n \
        --arg broadcastId "$id" \
        --arg name "$name" \
        --arg notificationTitle "$notification_title" \
        --argjson setNotificationTitle "$set_notification_title" \
        --arg content "$content" \
        --arg senderType "$sender_type" \
        --arg senderUserId "$sender_user" \
        --arg linkUnfurling "$link_unfurling" \
        --argjson sendTarget "$send_target" \
        '{
            broadcastId: $broadcastId,
            name: (if $name == "" then null else {value: $name} end),
            notificationTitle: (if $setNotificationTitle then {value: (if $notificationTitle == "" then null else $notificationTitle end)} else null end),
            content: (if $content == "" then null else {value: $content} end),
            contentFormat: (if $content == "" then null else {value: "TIPTAP"} end),
            senderType: (if $senderType == "" then null else {value: $senderType} end),
            senderUserId: (if $senderUserId == "" then null else {value: $senderUserId} end),
            isLinkUnfurlingEnabled: (if $linkUnfurling == "" then null else {value: ($linkUnfurling == "true")} end),
            sendTarget: $sendTarget
        }
        | with_entries(select(.value != null))')

    gql "mutation(\$input: UpdateBroadcastInput!) { updateBroadcast(input: \$input) { broadcast { $BROADCAST_SUMMARY_FIELDS } $BROADCAST_MUTATION_ERROR } }" \
        "$(jq -n --argjson input "$input" '{input: $input}')"
}

broadcast_delete() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Error: broadcast_id is required" >&2
        echo "Usage: plain-api.sh broadcast delete bc_01..." >&2
        exit 1
    fi
    gql "mutation(\$input: DeleteBroadcastInput!) { deleteBroadcast(input: \$input) { broadcast { id name isDeleted deletedAt { iso8601 } } $BROADCAST_MUTATION_ERROR } }" \
        "{\"input\": {\"broadcastId\": \"$id\"}}"
}

# ============================================================================
# BROADCAST AUDIENCES (READ + WRITE)
# ============================================================================

audience_list() {
    local first=20
    local search=""
    local after=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --search) search="$2"; shift 2 ;;
            --first) first="$2"; shift 2 ;;
            --after) after="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local variables
    variables=$(jq -n --argjson first "$first" --arg search "$search" --arg after "$after" \
        '{
            first: $first,
            searchQuery: (if $search == "" then null else $search end),
            after: (if $after == "" then null else $after end)
        }')

    gql "query(\$first: Int!, \$searchQuery: String, \$after: String) { broadcastAudiences(searchQuery: \$searchQuery, first: \$first, after: \$after) { edges { cursor node { $BROADCAST_AUDIENCE_FIELDS } } pageInfo { hasNextPage endCursor } } }" \
        "$variables"
}

audience_get() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Error: broadcast_audience_id is required" >&2
        echo "Usage: plain-api.sh audience get ba_01..." >&2
        exit 1
    fi
    gql "query(\$id: ID!) { broadcastAudience(broadcastAudienceId: \$id) { $BROADCAST_AUDIENCE_FIELDS } }" \
        "{\"id\": \"$id\"}"
}

audience_create() {
    local name=""
    local tiers=""
    local tenants=""
    local channel_names=""
    local filters_file=""
    local all_tenants="false"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            --tier) tiers=$(append_line "$tiers" "$2"); shift 2 ;;
            --tenant) tenants=$(append_line "$tenants" "$2"); shift 2 ;;
            --channel-name-contains) channel_names=$(append_line "$channel_names" "$2"); shift 2 ;;
            --filters-file) filters_file="$2"; shift 2 ;;
            --all-tenants) all_tenants="true"; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$name" ]]; then
        echo "Error: --name is required" >&2
        echo "Usage: plain-api.sh audience create --name \"Enterprise\" --tier tier_01... [--tenant ten_01...]" >&2
        exit 1
    fi

    local filters
    if [[ -n "$filters_file" ]]; then
        filters=$(read_json_file "$filters_file")
    else
        filters=$(audience_filters_from_flags "$tenants" "$tiers" "" "$channel_names")
    fi

    if [[ "$all_tenants" == "true" ]] && [[ "$filters" != "{}" ]]; then
        echo "Error: --all-tenants cannot be combined with --tier/--tenant/--channel-name-contains/--filters-file" >&2
        exit 1
    fi

    # An audience with no filters at all means every tenant, which is the only way
    # to say so. --all-tenants makes that explicit rather than accidental.
    if [[ "$filters" == "{}" ]] && [[ "$all_tenants" != "true" ]]; then
        echo "Error: pass --all-tenants to mean every tenant, or one of --tier/--tenant/--channel-name-contains/--filters-file" >&2
        exit 1
    fi

    local input
    input=$(jq -n --arg name "$name" --argjson filters "$filters" \
        '{name: $name, type: "SLACK", filters: $filters}')

    gql "mutation(\$input: CreateBroadcastAudienceInput!) { createBroadcastAudience(input: \$input) { broadcastAudience { $BROADCAST_AUDIENCE_FIELDS } $BROADCAST_MUTATION_ERROR } }" \
        "$(jq -n --argjson input "$input" '{input: $input}')"
}

audience_update() {
    local id=""
    local name=""
    local tiers=""
    local tenants=""
    local channel_names=""
    local filters_file=""
    local set_filters="false"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            --tier) tiers=$(append_line "$tiers" "$2"); set_filters="true"; shift 2 ;;
            --tenant) tenants=$(append_line "$tenants" "$2"); set_filters="true"; shift 2 ;;
            --channel-name-contains) channel_names=$(append_line "$channel_names" "$2"); set_filters="true"; shift 2 ;;
            --filters-file) filters_file="$2"; set_filters="true"; shift 2 ;;
            '') shift ;;
            --*) echo "Error: unknown option $1" >&2; exit 1 ;;
            *) id="$1"; shift ;;
        esac
    done

    if [[ -z "$id" ]]; then
        echo "Error: broadcast_audience_id is required" >&2
        echo "Usage: plain-api.sh audience update ba_01... [--name \"New name\"] [--tier tier_01...]" >&2
        exit 1
    fi

    # Filters replace the stored tree wholesale - there is no merge. Read the
    # audience first and pass the whole thing back if you only mean to add one row.
    local filters="null"
    if [[ "$set_filters" == "true" ]]; then
        if [[ -n "$filters_file" ]]; then
            filters=$(read_json_file "$filters_file")
        else
            filters=$(audience_filters_from_flags "$tenants" "$tiers" "" "$channel_names")
        fi
    fi

    local input
    input=$(jq -n --arg broadcastAudienceId "$id" --arg name "$name" --argjson filters "$filters" \
        '{
            broadcastAudienceId: $broadcastAudienceId,
            name: (if $name == "" then null else {value: $name} end),
            filters: $filters
        }
        | with_entries(select(.value != null))')

    gql "mutation(\$input: UpdateBroadcastAudienceInput!) { updateBroadcastAudience(input: \$input) { broadcastAudience { $BROADCAST_AUDIENCE_FIELDS } $BROADCAST_MUTATION_ERROR } }" \
        "$(jq -n --argjson input "$input" '{input: $input}')"
}

audience_delete() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Error: broadcast_audience_id is required" >&2
        echo "Usage: plain-api.sh audience delete ba_01..." >&2
        exit 1
    fi
    gql "mutation(\$input: DeleteBroadcastAudienceInput!) { deleteBroadcastAudience(input: \$input) { broadcastAudience { id name isDeleted deletedAt { iso8601 } } $BROADCAST_MUTATION_ERROR } }" \
        "{\"input\": {\"broadcastAudienceId\": \"$id\"}}"
}

# ============================================================================
# WORKSPACE (READ ONLY)
# ============================================================================

workspace_get() {
    gql '{ myWorkspace { id name publicName } }' '{}'
}

# ============================================================================
# MAIN
# ============================================================================

usage() {
    cat << 'EOF'
Plain API CLI - Interact with Plain customer support platform

USAGE: plain-api.sh <resource> <action> [options]

RESOURCES:
  customer      Read customers
  thread        Read threads, timeline, and add notes
  company       Read companies
  tenant        Read tenants
  label         Read labels
  helpcenter    Read + create draft articles and groups
  broadcast     Read + draft broadcasts (never schedules or sends)
  audience      Read + write broadcast audiences
  tier          Read tiers and SLAs
  workspace     Get workspace info

EXAMPLES:
  plain-api.sh customer list --first 10
  plain-api.sh customer get c_123
  plain-api.sh customer search "john"

  plain-api.sh thread list --status TODO --first 20
  plain-api.sh thread get th_123
  plain-api.sh thread timeline th_123 --first 50
  plain-api.sh thread note th_123 --text "Internal note content"

  plain-api.sh thread link add th_123 https://github.com/owner/repo/issues/45
  plain-api.sh thread link add th_123 owner/repo#45
  plain-api.sh thread link list th_123

  plain-api.sh helpcenter list
  plain-api.sh helpcenter articles hc_123 --first 10
  plain-api.sh helpcenter article upsert hc_123 --title "Title" --content "<p>HTML</p>"

  plain-api.sh broadcast list --status DRAFT
  plain-api.sh broadcast get bc_123
  plain-api.sh broadcast sends bc_123 --real-only
  plain-api.sh broadcast deliveries bc_123 --status FAILED
  plain-api.sh broadcast recipients --tier tier_123
  plain-api.sh broadcast create --name "Launch" --text "We shipped it." --notification-title "We shipped it"

  plain-api.sh audience list --search enterprise
  plain-api.sh audience create --name "Enterprise" --tier tier_123
  plain-api.sh audience update ba_123 --name "Enterprise (EU)"

  plain-api.sh tier list
  plain-api.sh workspace

NOTE:
  Scheduling and sending broadcasts (including test sends) are not exposed.
  Both post real messages to real Slack channels - do those in the Plain app.

ENVIRONMENT:
  PLAIN_API_KEY   Required. Your Plain API key.
  PLAIN_API_URL   Optional. API endpoint (default: https://core-api.uk.plain.com/graphql/v1)
EOF
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    local resource="$1"

    # Allow help without API key
    if [[ "$resource" == "help" ]] || [[ "$resource" == "--help" ]] || [[ "$resource" == "-h" ]]; then
        usage
        exit 0
    fi

    check_deps
    shift

    case "$resource" in
        customer)
            local action="${1:-list}"
            shift || true
            case "$action" in
                get) customer_get "$@" ;;
                get-by-email) customer_get_by_email "$@" ;;
                get-by-external-id) customer_get_by_external_id "$@" ;;
                list) customer_list "$@" ;;
                search) customer_search "$@" ;;
                *) echo "Unknown customer action: $action" >&2; exit 1 ;;
            esac
            ;;
        thread)
            local action="${1:-list}"
            shift || true
            case "$action" in
                get) thread_get "$@" ;;
                list) thread_list "$@" ;;
                search) thread_search "$@" ;;
                timeline) thread_timeline "$@" ;;
                note) thread_note "$@" ;;
                link)
                    local sub_action="${1:-list}"
                    shift || true
                    case "$sub_action" in
                        add) thread_link_add "$@" ;;
                        list) thread_link_list "$@" ;;
                        *) echo "Unknown link action: $sub_action" >&2; exit 1 ;;
                    esac
                    ;;
                *) echo "Unknown thread action: $action" >&2; exit 1 ;;
            esac
            ;;
        company)
            local action="${1:-list}"
            shift || true
            case "$action" in
                get) company_get "$@" ;;
                list) company_list "$@" ;;
                *) echo "Unknown company action: $action" >&2; exit 1 ;;
            esac
            ;;
        tenant)
            local action="${1:-list}"
            shift || true
            case "$action" in
                get) tenant_get "$@" ;;
                list) tenant_list "$@" ;;
                *) echo "Unknown tenant action: $action" >&2; exit 1 ;;
            esac
            ;;
        label)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list) label_list "$@" ;;
                *) echo "Unknown label action: $action" >&2; exit 1 ;;
            esac
            ;;
        helpcenter)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list) helpcenter_list ;;
                get) helpcenter_get "$@" ;;
                articles) helpcenter_articles "$@" ;;
                article)
                    local sub_action="${1:-get}"
                    shift || true
                    case "$sub_action" in
                        get) helpcenter_article_get "$@" ;;
                        get-by-slug) helpcenter_article_get_by_slug "$@" ;;
                        upsert) helpcenter_article_upsert "$@" ;;
                        *) echo "Unknown article action: $sub_action" >&2; exit 1 ;;
                    esac
                    ;;
                group)
                    local sub_action="${1:-get}"
                    shift || true
                    case "$sub_action" in
                        get) helpcenter_group_get "$@" ;;
                        create) helpcenter_group_create "$@" ;;
                        update) helpcenter_group_update "$@" ;;
                        delete) helpcenter_group_delete "$@" ;;
                        *) echo "Unknown group action: $sub_action" >&2; exit 1 ;;
                    esac
                    ;;
                *) echo "Unknown helpcenter action: $action" >&2; exit 1 ;;
            esac
            ;;
        broadcast)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list) broadcast_list "$@" ;;
                get) broadcast_get "$@" ;;
                search) broadcast_search "$@" ;;
                sends) broadcast_sends "$@" ;;
                deliveries) broadcast_deliveries "$@" ;;
                recipients) broadcast_recipients "$@" ;;
                create) broadcast_create "$@" ;;
                update) broadcast_update "$@" ;;
                delete) broadcast_delete "$@" ;;
                send|schedule|test)
                    echo "Error: broadcasts are not sent or scheduled from this skill - do it in the Plain app" >&2
                    exit 1 ;;
                *) echo "Unknown broadcast action: $action" >&2; exit 1 ;;
            esac
            ;;
        audience)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list) audience_list "$@" ;;
                get) audience_get "$@" ;;
                create) audience_create "$@" ;;
                update) audience_update "$@" ;;
                delete) audience_delete "$@" ;;
                *) echo "Unknown audience action: $action" >&2; exit 1 ;;
            esac
            ;;
        tier)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list) tier_list "$@" ;;
                get) tier_get "$@" ;;
                *) echo "Unknown tier action: $action" >&2; exit 1 ;;
            esac
            ;;
        workspace)
            workspace_get
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo "Unknown resource: $resource" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"
