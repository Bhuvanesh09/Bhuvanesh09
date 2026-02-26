#!/usr/bin/env bash
set -e

# Load .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "Error: .env file not found. Copy .env.example and fill in your key."
  exit 1
fi

if [ -z "$GEMINI_API_KEY" ]; then
  echo "Error: GEMINI_API_KEY not set in .env"
  exit 1
fi

echo "--- Fetching RSS feed ---"
curl -sf "https://bhuvanesh09.github.io/posts/index.xml" > /tmp/feed.xml

echo "--- Parsing latest post ---"
python3 - <<'EOF'
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
import os

tree = ET.parse("/tmp/feed.xml")
items = tree.getroot().find("channel").findall("item")

latest = max(items, key=lambda i: parsedate_to_datetime(i.find("pubDate").text))

title = latest.find("title").text
link = latest.find("link").text
desc = (latest.find("description").text or "")[:1000]

with open("/tmp/post_title.txt", "w") as f:
    f.write(title)
with open("/tmp/post_link.txt", "w") as f:
    f.write(link)
with open("/tmp/post_description.txt", "w") as f:
    f.write(desc)

print(f"Title: {title}")
print(f"Link:  {link}")
EOF

TITLE=$(cat /tmp/post_title.txt)
LINK=$(cat /tmp/post_link.txt)
DESC=$(cat /tmp/post_description.txt)

echo ""
echo "--- Calling Gemini 3.0 Flash ---"
PROMPT="You are summarizing a blog post for a GitHub profile README. Write exactly one sentence (under 30 words) that captures what this post is about. Be direct and concise. Do not use quotes around your response.\n\nTitle: ${TITLE}\n\nExcerpt: ${DESC}"

RESPONSE=$(curl -sf "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H 'Content-Type: application/json' \
  -H "X-goog-api-key: $GEMINI_API_KEY" \
  -X POST \
  -d "$(jq -n --arg prompt "$PROMPT" '{
    contents: [{ parts: [{ text: $prompt }] }],
    generationConfig: { temperature: 0.3, maxOutputTokens: 200, thinkingConfig: { thinkingBudget: 0 } }
  }')")

SUMMARY=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text' | tr -d '\n')

echo "Summary: $SUMMARY"

echo ""
echo "--- Updating README.md ---"
awk -v title="$TITLE" -v link="$LINK" -v summary="$SUMMARY" '
  /<!-- LATEST_POST_START -->/ {
    print
    print ""
    print "> [**" title "**](" link ") — " summary
    skip = 1
    next
  }
  /<!-- LATEST_POST_END -->/ {
    print ""
    print
    skip = 0
    next
  }
  !skip { print }
' README.md > README.tmp && mv README.tmp README.md

echo "Done. README.md updated — check the Latest post section."
