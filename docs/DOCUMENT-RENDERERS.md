# Document renderers

`/octo:deck` and `/octo:docs` use skills advertised by the current host session.
A standalone `pptx` skill or another plugin's `pptx` skill works without the
`document-skills` plugin. An installed skill must also be enabled and exposed to
the session before Octopus can invoke it.

Name a renderer and optional template in your request, for example:

```text
/octo:deck quarterly review using house:slides and /path/to/Board template.pptx
/octo:deck product update using google-drive:google-slides
```

The selected skill must be available and support the requested deliverable.
Its own template, authentication, sharing and publication rules still apply.
Renderer selection grants no additional permission to publish or share a deck.

To save a choice, create `~/.claude-octopus/document-renderers.json`:

```json
{
  "pptx": {
    "skill": "house:slides",
    "template": "/absolute/path/Board template.pptx"
  },
  "docx": {"skill": "docx"}
}
```

Supported keys are `pptx`, `docx`, `xlsx` and `pdf`. Template paths must name
existing files. Relative paths resolve from the invocation's working directory.
An explicit renderer replaces the saved renderer and its template. An explicit
template overrides the saved template. Selection never rewrites this file.
An explicit renderer ignores saved configuration, including malformed settings.
The `--config` path accepts `~` and resolves to an absolute path before reading.

Without an explicit or saved choice, Octopus prefers `document-skills:<format>`
when advertised, then a single advertised `<format>` or `<namespace>:<format>`
skill. Multiple alternatives require a choice. An unavailable explicit or saved
renderer fails instead of silently using another renderer.

The skills call `scripts/helpers/document-renderer.py` with the actual advertised
skill names. For example, if only `anthropic-skills:pptx` is exposed:

```bash
python3 "$OCTO_ROOT/scripts/helpers/document-renderer.py" --format pptx \
  --available-skill anthropic-skills:pptx
```

Pass one `--available-skill` per advertised skill. The helper selects a skill and
validates the template path; it does not discover skills from disk, execute
renderers, install plugins or establish that a renderer can complete a task.

When approved slide materials exist, the rendering handoff contains the slide
skeleton, visual callouts, appendix list and selected template. Preserve those
inputs through conversion. Direct document exports pass the source markdown
without implying outline approval.
For a native Slides renderer, return the actual deck URL. For a file renderer,
return the actual artifact path. Report a renderer failure without claiming a
completed deck or switching renderers silently.

`/octo:deck` verifies the rendered output before reporting completion. It opens
every slide thumbnail, checks for visual defects, re-reads rendered titles
against the approved outline and checks each data slide's highlighted claim
against its source. The response includes a slide-by-slide verification table.
After a repair rerenders the deck, repeat every check for every final slide and
rebuild the verification table. Failed checks or missing inspection tools or
source evidence keep the artifact a draft, including after the two repair rounds
are exhausted. Renderer selection alone does not establish that these checks ran,
and verification grants no permission to publish or share a deck.
