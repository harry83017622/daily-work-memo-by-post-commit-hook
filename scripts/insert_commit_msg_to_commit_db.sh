#!/bin/bash

source .notion.env

repo_name=$(basename $(git rev-parse --show-toplevel))

function fetch_page_id {
    project_name=$1
    response=$(curl -s -X POST https://api.notion.com/v1/databases/$PROJECT_DB_ID/query \
         -H "Authorization: Bearer $NOTION_INTEGRATION_TOKEN" \
         -H "Notion-Version: 2021-08-16" \
         --data '{}')
    page_id=$(echo $response | jq -r --arg project_name "$project_name" '.results[] | select(.properties."Project name".title[].text.content == $project_name) | .id')
    if [ -z "$page_id" ]; then
        page_id=$(./scripts/insert_repo_to_project_db.sh)
    fi
    echo $page_id
}
page_id=$(fetch_page_id "$repo_name")

# get ids by user
function fetch_user_ids {
    response=$(curl -s -X GET https://api.notion.com/v1/users \
        -H "Authorization: Bearer $NOTION_INTEGRATION_TOKEN" \
        -H "Notion-Version: 2021-08-16")

    if echo $response | grep -q "error"; then
        echo "Error: $(echo $response | jq -r '.message')"
        exit -1
    else
        echo $response | jq -c 'reduce .results[] as $item ({}; . + {($item.name): $item.id})'
    fi
}
user_ids=$(fetch_user_ids)
user_id=$(echo $user_ids | jq -r '."Cheng-Hao Lee"')

# parse commit msg
commit_msg_topic_sentence=$(git log -1 --pretty=format:"%s")
commit_msg_body=$(echo $commit_msg_topic_sentence | cut -d':' -f2- | sed 's/^ *//;s/ *$//')
pre_colon=$(echo $commit_msg_topic_sentence | cut -d':' -f1)
format_tags=$(echo $pre_colon | sed 's/ //g' | sed 's/(/,/g' | sed 's/)//g')
json_tags=$(echo $format_tags | jq -R 'split(",") | map({name: .})')

last_commit_msg=$(git log -1 --pretty=%B)
escaped_msg=$(echo "$(git log -1 --pretty=format:"%B")" | jq -Rs .)

# post commit msg to notion db
data=$(cat << EOF
{
    "parent": { "database_id": "$COMMIT_DB_ID"},
    "properties": {
        "Task name": {"title": [{"text": {"content": "$commit_msg_body"}}]},
        "Status": {"status": {"name": "Done"}},
        "Assignee": {"people": [{"id": "$user_id"}]},
        "Due": {"date": {"start": "$(date "+%Y-%m-%d")"}},
        "Priority": {"select": {"name": "Medium"}},
        "Tags": {"multi_select": $json_tags},
        "Project": {"relation": [{"id": "$page_id"}]}
    },
    "children": [{
        "object": "block",
        "type": "paragraph",
        "paragraph": {
            "text": [{
                "type": "text",
                "text": {
                    "content": $escaped_msg
                }
            }]
        }
    }]
}
EOF
)

# post commit to notion db
curl -s -X POST https://api.notion.com/v1/pages \
     -H "Authorization: Bearer $NOTION_INTEGRATION_TOKEN" \
     -H "Content-Type: application/json" \
     -H "Notion-Version: 2021-08-16" \
     --data "$data"

exit 0