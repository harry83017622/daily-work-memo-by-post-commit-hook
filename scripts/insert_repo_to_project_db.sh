#!/bin/bash

source .notion.env

repo_name=$(basename $(git rev-parse --show-toplevel))

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

data=$(cat << EOF
{
    "parent": { "database_id": "$PROJECT_DB_ID"},
    "properties": {
        "Project name": {"title": [{"text": {"content": "$repo_name"}}]},
        "Status": {"status": {"name": "In progress"}},
        "Owner": {"people": [{"id": "$user_id"}]}
    }
}
EOF
)

# post commit to notion db
response=$(curl -s -X POST https://api.notion.com/v1/pages \
     -H "Authorization: Bearer $NOTION_INTEGRATION_TOKEN" \
     -H "Content-Type: application/json" \
     -H "Notion-Version: 2021-08-16" \
     --data "$data")

page_id=$(echo $response | jq -r '.id')
echo $page_id