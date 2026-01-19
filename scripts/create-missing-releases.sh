#!/bin/bash
# scripts/create-missing-releases.sh
# Create GitHub releases for all tags that don't have releases yet

set -e

# Get list of tags without releases
MISSING_TAGS=$(comm -23 \
    <(git tag | sort -V) \
    <(gh release list --limit 100 --json tagName --jq '.[].tagName' | sort -V))

if [ -z "$MISSING_TAGS" ]; then
    echo "✅ All tags have releases!"
    exit 0
fi

echo "Found $(echo "$MISSING_TAGS" | wc -l) tags without releases"
echo ""

# Function to generate release notes from git log
generate_release_notes() {
    local tag="$1"
    local prev_tag="$2"

    # Get tag date
    local tag_date=$(git log -1 --format=%ai "$tag" | cut -d' ' -f1)

    # Generate release notes
    local notes="## Release $tag ($tag_date)

"

    if [ -n "$prev_tag" ]; then
        # Get commits between previous tag and this tag
        local commits=$(git log --pretty=format:"- %s" "$prev_tag..$tag" 2>/dev/null || git log --pretty=format:"- %s" "$tag" -1)

        if [ -n "$commits" ]; then
            notes+="### Changes

$commits

"
        fi
    else
        # First release or can't find previous tag
        notes+="Initial release

"
    fi

    # Add footer
    notes+="---

See [CHANGELOG.md](https://github.com/nyldn/claude-octopus/blob/main/CHANGELOG.md) for more details.

**Installation:**
\`\`\`
/plugin marketplace add https://github.com/nyldn/claude-octopus
/plugin install claude-octopus@nyldn-plugins
\`\`\`"

    echo "$notes"
}

# Create releases for each missing tag
echo "$MISSING_TAGS" | while read -r tag; do
    if [ -z "$tag" ]; then
        continue
    fi

    echo "Creating release for $tag..."

    # Find previous tag using git describe
    prev_tag=$(git describe --tags --abbrev=0 "$tag^" 2>/dev/null || echo "")

    # Generate release notes
    notes=$(generate_release_notes "$tag" "$prev_tag")

    # Create release
    if gh release create "$tag" \
        --title "Release $tag" \
        --notes "$notes" \
        --verify-tag; then
        echo "  ✅ Created release for $tag"
    else
        echo "  ❌ Failed to create release for $tag"
    fi

    echo ""

    # Small delay to avoid rate limiting
    sleep 1
done

echo ""
echo "✅ Finished creating releases!"
echo ""
echo "View releases at: https://github.com/nyldn/claude-octopus/releases"
