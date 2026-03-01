#!/usr/bin/env bash
# github.sh - GitHub issue tracker provider
#
# Required: gh CLI (authenticated)

tracker_get_issue() {
  local issue_number="$1" repo="$2"
  gh issue view "$issue_number" --repo "$repo" \
    --json title,body \
    --jq '"# " + .title + "\n\n" + .body'
}

tracker_get_comments() {
  local issue_number="$1" repo="$2"
  gh api "repos/$repo/issues/$issue_number/comments?per_page=10&direction=desc" \
    --jq '[.[] | {author: .user.login, body: .body}] | reverse | .[] | "### " + .author + "\n" + .body + "\n---"'
}

tracker_post_comment() {
  local issue_number="$1" repo="$2" body_file="$3"
  gh issue comment "$issue_number" --repo "$repo" --body-file "$body_file"
}
