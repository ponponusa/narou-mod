# Claude Code Instructions

<!-- agent-context-maintainer:begin -->
@AGENTS.md

## Claude Code

Use `AGENTS.md` as the shared source of truth for repository instructions. For Claude-specific behavior, also follow `.agents/profiles/claude.md` when present.
<!-- agent-context-maintainer:end -->

## Claude Code Imports

Claude Code does not read `.agents/` on its own, so the shared policy, task routes, and Claude profile are imported here:

@.agents/core.md
@.agents/routing.md
@.agents/profiles/claude.md
