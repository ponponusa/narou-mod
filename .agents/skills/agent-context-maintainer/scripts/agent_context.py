#!/usr/bin/env python3
"""Scaffold and validate repository-local AI agent context files."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from textwrap import dedent
from typing import Any, Dict, List, Optional, Tuple


BEGIN = "<!-- agent-context-maintainer:begin -->"
END = "<!-- agent-context-maintainer:end -->"

# Single source of truth for provider knowledge: profile wording, bridge files,
# registry sources, and runtime-detection environment variables. Key order is
# fixed (it defines PROFILES). Only variables confirmed in
# reports/provider-review-*.md may be listed in detect_env.
PROVIDERS: dict[str, dict[str, object]] = {
    "codex": {
        "title": "Codex",
        "profile_bullets": [
            "Read the repository before editing.",
            "Use scoped patches and preserve unrelated user changes.",
            "Run focused validation and report exact commands.",
            "Create durable repo-local artifacts for long-running work.",
            "Custom subagents may be defined in `.codex/agents/*.toml`; read them before changing delegation behavior. Do not treat `.codex/rules/` as instructions — it is an exec-policy allowlist.",
        ],
        "bridge_files": ["AGENTS.md"],
        "source_urls": [
            "https://agents.md/",
            "https://learn.chatgpt.com/docs/agent-configuration/subagents",
        ],
        # Only set while Codex sandboxing is active; unsandboxed Codex
        # sessions fall back to generic and should pass --agent codex.
        "detect_env": ["CODEX_SANDBOX", "CODEX_SANDBOX_NETWORK_DISABLED"],
    },
    "claude": {
        "title": "Claude",
        "profile_bullets": [
            "Use strengths in long-form design review and cross-document reconciliation.",
            "State assumptions and open questions explicitly.",
            "Convert analysis into concrete edits when implementation is requested.",
            "Custom subagents may be defined in `.claude/agents/*.md`; read them before changing delegation behavior.",
        ],
        "bridge_files": ["CLAUDE.md", "AGENTS.md"],
        "source_urls": [
            "https://code.claude.com/docs/en/memory",
            "https://code.claude.com/docs/en/sub-agents",
        ],
        "detect_env": ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"],
    },
    "gemini": {
        "title": "Gemini",
        "profile_bullets": [
            "Use broad-context synthesis across docs and manifests.",
            "Attribute repository facts to checked local files.",
            "Verify current local state before treating recalled context as fact.",
            "Custom subagents may be defined in `.gemini/agents/*.md`; read them before changing delegation behavior.",
        ],
        "bridge_files": ["GEMINI.md", ".gemini/settings.json", "AGENTS.md"],
        "source_urls": [
            "https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/configuration.md",
            "https://github.com/google-gemini/gemini-cli/blob/main/docs/core/subagents.md",
        ],
        "detect_env": ["GEMINI_CLI"],
    },
    "cursor": {
        "title": "Cursor",
        "profile_bullets": [
            "Prefer local symbol-aware edits and small reviewable diffs.",
            "Avoid unrelated formatting churn.",
            "Keep instructions practical for IDE-driven iteration.",
        ],
        "bridge_files": ["AGENTS.md"],
        "source_urls": ["https://docs.cursor.com/context/rules"],
        "detect_env": [],
    },
    "copilot": {
        "title": "Copilot",
        "profile_bullets": [
            "Prefer concise repository-wide guidance that reduces cloud-agent exploration.",
            "Keep task-specific instructions out of `.github/copilot-instructions.md`.",
            "Use `AGENTS.md` and the nearest applicable routed skill for deeper workflow details.",
            "Custom subagents may be defined in `.github/agents/*.agent.md`; read them before changing delegation behavior.",
        ],
        "bridge_files": [".github/copilot-instructions.md", "AGENTS.md"],
        "source_urls": [
            "https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/add-custom-instructions/add-repository-instructions",
            "https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/create-custom-agents",
        ],
        "detect_env": [],
    },
    "antigravity": {
        "title": "Antigravity",
        "profile_bullets": [
            "Prefer verifiable artifacts: plans, command results, screenshots, or review notes when useful.",
            "Be explicit about autonomous steps before broad edits or risky commands.",
            "Use shared `AGENTS.md` policy plus Gemini-compatible bridge files when available.",
        ],
        "bridge_files": ["AGENTS.md", "GEMINI.md"],
        "source_urls": ["https://antigravity.google/"],
        "detect_env": [],
    },
    "generic": {
        "title": "Generic",
        "profile_bullets": [
            "Follow `.agents/core.md` and `.agents/routing.md`.",
            "Identify available tools before choosing a workflow.",
            "Ask only when a missing decision would create meaningful risk.",
        ],
        "bridge_files": ["AGENTS.md"],
        "source_urls": ["https://agents.md/"],
        "detect_env": [],
    },
}
PROFILES = tuple(PROVIDERS)

# Detection precedence when multiple providers' variables are present. This is
# independent of the PROVIDERS key order and preserves the historical
# multi-hit behavior of detect_agent().
DETECT_PRIORITY = ("claude", "gemini", "cursor", "copilot", "antigravity", "codex")
EXCLUDED_DIRS = {
    ".git",
    ".hg",
    ".svn",
    "node_modules",
    ".venv",
    "venv",
    "vendor",
    "dist",
    "build",
    "target",
    ".next",
    ".cache",
    "DerivedData",
}
SENSITIVE_DIR_COMPONENTS = {
    ".aws",
    ".azure",
    ".docker",
    ".gnupg",
    ".kube",
    ".ssh",
    ".terraform",
    "credentials",
    "secrets",
}
SECRET_NAMES = {
    ".env",
    ".envrc",
    ".env.local",
    ".env.production",
    ".npmrc",
    ".pypirc",
    "id_dsa",
    "id_ecdsa",
    "id_ed25519",
    "id_rsa",
}
EXCLUDED_SUFFIXES = {
    ".bak",
    ".cer",
    ".crt",
    ".db",
    ".der",
    ".key",
    ".log",
    ".p12",
    ".pem",
    ".pfx",
    ".sqlite",
    ".sqlite3",
}
ARCHIVE_SUFFIXES = {
    ".7z",
    ".bz2",
    ".dmg",
    ".gz",
    ".ipa",
    ".jar",
    ".rar",
    ".tar",
    ".tgz",
    ".war",
    ".xz",
    ".zip",
}
BINARY_SUFFIXES = {
    ".a",
    ".bin",
    ".class",
    ".dll",
    ".dylib",
    ".exe",
    ".gif",
    ".heic",
    ".ico",
    ".jpeg",
    ".jpg",
    ".lockb",
    ".o",
    ".pdf",
    ".png",
    ".pyc",
    ".so",
    ".webp",
}
MAX_INVENTORY_FILE_BYTES = 1_000_000
MAX_REPORTED_SKIPS = 200
MANIFESTS = {
    "package.json": "Node/JavaScript",
    "Cargo.toml": "Rust",
    "pyproject.toml": "Python",
    "requirements.txt": "Python",
    "go.mod": "Go",
    "pom.xml": "Java/Maven",
    "build.gradle": "Java/Gradle",
    "Package.swift": "Swift",
    "Gemfile": "Ruby",
}
LANG_EXTS = {
    ".ts": "TypeScript",
    ".tsx": "TypeScript React",
    ".js": "JavaScript",
    ".jsx": "JavaScript React",
    ".py": "Python",
    ".rs": "Rust",
    ".go": "Go",
    ".swift": "Swift",
    ".kt": "Kotlin",
    ".java": "Java",
    ".rb": "Ruby",
    ".md": "Markdown",
}
AGENTS_REF_RE = re.compile(r"`(\.agents/[^`\s)]+)`")
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)
PROVIDER_REGISTRY_REVIEWED = "2026-08-04"  # update together with reports/provider-review-*.md
MAX_SKILL_NAME_CHARS = 64
SKILL_NAME_RE = re.compile(
    rf"^(?!.*--)[a-z0-9](?:[a-z0-9-]{{0,{MAX_SKILL_NAME_CHARS - 2}}}[a-z0-9])?$"
)
SKILL_FRONTMATTER_RE = re.compile(r"\A---\r?\n(.*?)\r?\n---\r?\n?", re.DOTALL)
MARKDOWN_LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
BACKTICK_LOCAL_PATH_RE = re.compile(r"`((?:scripts|references|assets|evals)/[^`]+)`")
NEGATION_RE = re.compile(r"\b(do not|don't|never|avoid|must not|should not)\b", re.I)
RISK_RE = re.compile(r"\b(\.env|secret|secrets|token|tokens|credential|credentials|raw\s+logs?)\b", re.I)
MAX_SKILL_DESCRIPTION_CHARS = 1024
# Claude Code truncates each listing entry's combined description +
# when_to_use at 1,536 characters (configurable host-side via
# skillListingMaxDescChars); see reports/provider-review-2026-08.md.
MAX_SKILL_LISTING_ENTRY_CHARS = 1536
# Codex truncates the whole skill listing (names, descriptions, paths) at 2%
# of the context window and falls back to 8,000 characters when the window is
# unknown; see reports/provider-review-2026-08.md. Static checks can only
# estimate against the fallback value.
CODEX_LISTING_FALLBACK_BUDGET_CHARS = 8000
MAX_SKILL_COMPATIBILITY_CHARS = 500
MAX_SKILL_MAIN_LINES = 500
MAX_SKILL_MD_BYTES = 1_000_000
SKILL_REGISTRY_REVIEWED = "2026-07-04"
SKILL_LIFECYCLES = {"draft", "experimental", "active", "watch", "deprecated", "archived"}


class AgentContextError(RuntimeError):
    """Raised when updating would be ambiguous or unsafe."""


@dataclass(frozen=True)
class MarkerStyle:
    begin: str
    end: str


@dataclass(frozen=True)
class MarkerSpan:
    begin_start: int
    end_end: int


MARKDOWN_MARKERS = MarkerStyle(BEGIN, END)
YAML_MARKERS = MarkerStyle(
    "# agent-context-maintainer:begin",
    "# agent-context-maintainer:end",
)
SKILL_ROUTE_MARKERS = MarkerStyle(
    "<!-- agent-context-maintainer:skills-begin -->",
    "<!-- agent-context-maintainer:skills-end -->",
)


@dataclass(frozen=True)
class ScaffoldOptions:
    dry_run: bool = False
    force_recreate: bool = False
    append_generated_block: bool = False


@dataclass
class PlannedWrite:
    path: Path
    content: str
    action: str
    snapshot: bool
    write: bool = True


@dataclass(frozen=True)
class SkippedPath:
    path: str
    reason: str


@dataclass(frozen=True)
class InventoryScan:
    files: list[Path]
    skipped: list[SkippedPath]


@dataclass(frozen=True)
class SkillDiagnostic:
    path: str
    code: str
    message: str


@dataclass(frozen=True)
class SkillFrontmatter:
    name: Optional[str]
    description: Optional[str]
    compatibility: Optional[str]
    license: Optional[str]
    allowed_tools: Optional[str]
    when_to_use: Optional[str]
    metadata: Dict[str, str]
    raw: Dict[str, Any]


@dataclass(frozen=True)
class SkillEvalManifest:
    path: Path
    exists: bool
    valid_json: bool
    eval_count: int
    errors: List[SkillDiagnostic]
    warnings: List[SkillDiagnostic]
    case_ids: List[str]


@dataclass(frozen=True)
class SkillQuality:
    eval_coverage: str
    has_trigger_evals: bool
    has_negative_trigger_evals: bool
    has_assertions: bool


@dataclass(frozen=True)
class SkillInfo:
    name: str
    directory: Path
    skill_md: Optional[Path]
    frontmatter: Optional[SkillFrontmatter]
    description: str
    compatibility: Optional[str]
    allowed_tools: Optional[str]
    validity: str
    lifecycle: str
    quality: SkillQuality
    scripts: List[Path]
    references: List[Path]
    assets: List[Path]
    codex_metadata: Optional[Path]
    eval_manifest: SkillEvalManifest
    line_count: int
    byte_count: int
    warnings: List[SkillDiagnostic]
    errors: List[SkillDiagnostic]


@dataclass(frozen=True)
class SkillInventory:
    root: Path
    skills: List[SkillInfo]
    skipped: List[SkippedPath]
    errors: List[SkillDiagnostic]


def is_secret(path: Path) -> bool:
    name = path.name.lower()
    suffix = path.suffix.lower()
    return (
        name in SECRET_NAMES
        or name.startswith(".env.")
        or suffix in EXCLUDED_SUFFIXES
        or "credential" in name
        or "password" in name
        or "secret" in name
        or "token" in name
    )


def has_sensitive_component(path: Path) -> bool:
    for part in path.parts:
        normalized = part.lower()
        if normalized in SENSITIVE_DIR_COMPONENTS:
            return True
        if normalized in {"secret", "credential"}:
            return True
        if normalized.endswith(("-secrets", "_secrets", ".secrets")):
            return True
        if normalized.endswith(("-credentials", "_credentials", ".credentials")):
            return True
    return False


def is_binary_file(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            chunk = handle.read(4096)
    except OSError:
        return True
    return b"\0" in chunk


def read_utf8_text(path: Path) -> Optional[str]:
    """Read a file as UTF-8, returning None instead of raising.

    is_binary_file() only detects NUL bytes in the first 4096 bytes, so
    invalid UTF-8 passes skip_file_reason(); callers that need decodable text
    must attempt the read explicitly.
    """
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def git_ignored_paths(root: Path, paths: list[Path]) -> set[str]:
    if not paths:
        return set()
    top = git_top(root)
    if top is None:
        return set()
    path_map: dict[str, str] = {}
    for path in paths:
        try:
            top_rel = str((root / path).resolve().relative_to(top))
        except ValueError:
            continue
        path_map[top_rel] = str(path)
    if not path_map:
        return set()
    result = subprocess.run(
        ["git", "-C", str(top), "check-ignore", "--stdin"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        input="\n".join(path_map) + "\n",
        text=True,
    )
    if result.returncode not in (0, 1):
        return set()
    ignored: set[str] = set()
    for line in result.stdout.splitlines():
        root_rel = path_map.get(line)
        if root_rel is not None:
            ignored.add(root_rel)
    return ignored


def skip_directory_reason(path: Path, rel: Path) -> Optional[str]:
    if path.name in EXCLUDED_DIRS:
        return "excluded-directory"
    if path.is_symlink():
        return "symlink-directory"
    if has_sensitive_component(rel):
        return "sensitive-directory"
    if rel.parts[:2] == (".agents", "snapshots"):
        # This tool's own pre-overwrite snapshots. Counting them would make
        # scaffold non-convergent: each update writes a snapshot, which would
        # change the inventory, which would change core.md again.
        return "tool-snapshot-directory"
    if rel.parts[:2] == (".agents", "skill-workspaces"):
        return "tool-workspace-directory"
    if rel.parts[:2] == (".agents", "telemetry"):
        return "tool-telemetry-directory"
    return None


def skip_file_reason(path: Path, rel: Path) -> Optional[str]:
    suffix = path.suffix.lower()
    if path.is_symlink():
        return "symlink-file"
    if has_sensitive_component(rel.parent) or is_secret(path):
        return "sensitive-file"
    if suffix in ARCHIVE_SUFFIXES:
        return "archive-file"
    if suffix in BINARY_SUFFIXES:
        return "binary-file"
    try:
        stat = path.stat()
    except OSError:
        return "unreadable-file"
    if not path.is_file():
        return "non-regular-file"
    if stat.st_size > MAX_INVENTORY_FILE_BYTES:
        return "large-file"
    if is_binary_file(path):
        return "binary-file"
    return None


def scan_inventory(root: Path) -> InventoryScan:
    candidate_files: list[Path] = []
    candidate_dirs: list[Path] = []
    skipped: list[SkippedPath] = []

    for current, dirs, file_names in os.walk(root):
        current_path = Path(current)
        kept_dirs: list[str] = []
        for dir_name in dirs:
            path = current_path / dir_name
            try:
                rel = path.relative_to(root)
            except ValueError:
                continue
            reason = skip_directory_reason(path, rel)
            if reason:
                if len(skipped) < MAX_REPORTED_SKIPS:
                    skipped.append(SkippedPath(str(rel) + "/", reason))
                continue
            kept_dirs.append(dir_name)
            candidate_dirs.append(rel)
        # os.walk yields entries in filesystem order, which differs across
        # platforms; sort so generated lists are deterministic everywhere.
        dirs[:] = sorted(kept_dirs)
        for file_name in sorted(file_names):
            path = current_path / file_name
            try:
                rel = path.relative_to(root)
            except ValueError:
                continue
            reason = skip_file_reason(path, rel)
            if reason:
                if len(skipped) < MAX_REPORTED_SKIPS:
                    skipped.append(SkippedPath(str(rel), reason))
                continue
            candidate_files.append(rel)

    ignored = git_ignored_paths(root, candidate_dirs + candidate_files)
    ignored_dirs = {path for path in candidate_dirs if str(path) in ignored}
    for rel in sorted(ignored_dirs, key=str):
        if len(skipped) < MAX_REPORTED_SKIPS:
            skipped.append(SkippedPath(str(rel) + "/", "ignored-directory"))
    included_files: list[Path] = []
    for rel in candidate_files:
        ignored_by_parent = any(rel.is_relative_to(parent) for parent in ignored_dirs)
        if str(rel) in ignored or ignored_by_parent:
            if len(skipped) < MAX_REPORTED_SKIPS:
                skipped.append(SkippedPath(str(rel), "ignored-file"))
            continue
        included_files.append(rel)
    return InventoryScan(included_files, skipped)


def iter_files(root: Path):
    yield from scan_inventory(root).files


def inventory(root: Path, explain_skips: bool = False) -> dict[str, object]:
    scan = scan_inventory(root)
    files = scan.files
    manifests = [str(p) for p in files if p.name in MANIFESTS]
    docs = [
        str(p)
        for p in files
        if p.name.lower().startswith(("readme", "design", "contributing", "security"))
        or str(p).startswith(("docs/", ".docs/"))
        or p.name in {"AGENTS.md", "CLAUDE.md", "GEMINI.md", "copilot-instructions.md"}
    ]
    tests = [
        str(p)
        for p in files
        if "test" in p.parts or "tests" in p.parts or p.name.startswith("test_") or p.name.endswith("_test.go")
    ]
    lang_counts: dict[str, int] = {}
    for p in files:
        lang = LANG_EXTS.get(p.suffix.lower())
        if lang:
            lang_counts[lang] = lang_counts.get(lang, 0) + 1
    languages = [name for name, _ in sorted(lang_counts.items(), key=lambda item: (-item[1], item[0]))[:6]]
    result: dict[str, object] = {
        "root_name": root.name,
        "file_count": len(files),
        "languages": languages,
        "manifests": manifests[:20],
        "docs": docs[:30],
        "tests": tests[:30],
    }
    if explain_skips:
        result["skipped"] = [{"path": item.path, "reason": item.reason} for item in scan.skipped]
    return result


def rel_posix(path: Path) -> str:
    return path.as_posix()


def diag(path: Path, code: str, message: str) -> SkillDiagnostic:
    return SkillDiagnostic(rel_posix(path), code, message)


def diag_dict(item: SkillDiagnostic) -> Dict[str, str]:
    return {"path": item.path, "code": item.code, "message": item.message}


def unquote_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1].replace("''", "'")
    if len(value) >= 2 and value[0] == value[-1] == '"':
        inner = value[1:-1]
        replacements = {
            r"\\": "\\",
            r"\"": '"',
            r"\n": "\n",
            r"\r": "\r",
            r"\t": "\t",
        }
        for old, new in replacements.items():
            inner = inner.replace(old, new)
        return inner
    return value


def malformed_quoted_scalar(value: str) -> bool:
    if not value:
        return False
    for quote in ("'", '"'):
        if value.startswith(quote) != value.endswith(quote):
            return True
    return False


def parse_block_scalar(lines: List[str], start: int, folded: bool) -> Tuple[str, int]:
    block: List[str] = []
    index = start
    while index < len(lines):
        line = lines[index]
        if line and not line.startswith((" ", "\t")):
            break
        block.append(line[2:] if line.startswith("  ") else line.lstrip())
        index += 1
    if folded:
        paragraphs: List[str] = []
        current: List[str] = []
        for line in block:
            if line.strip() == "":
                if current:
                    paragraphs.append(" ".join(current).strip())
                    current = []
                paragraphs.append("")
            else:
                current.append(line.strip())
        if current:
            paragraphs.append(" ".join(current).strip())
        return "\n".join(paragraphs).strip(), index
    return "\n".join(block).strip("\n"), index


def parse_metadata_block(lines: List[str], start: int) -> Tuple[Dict[str, str], int, List[str]]:
    metadata: Dict[str, str] = {}
    warnings: List[str] = []
    index = start
    while index < len(lines):
        line = lines[index]
        if line and not line.startswith((" ", "\t")):
            break
        stripped = line.strip()
        index += 1
        if not stripped:
            continue
        if ":" not in stripped:
            warnings.append(f"unsupported metadata line ignored: {stripped}")
            continue
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip()
        if not key or value in {"|", ">"} or value.startswith(("[", "{")):
            warnings.append(f"unsupported metadata value ignored: {key}")
            continue
        metadata[key] = unquote_scalar(value)
    return metadata, index, warnings


def parse_skill_frontmatter(text: str) -> Tuple[Optional[SkillFrontmatter], str, List[str], List[str]]:
    match = SKILL_FRONTMATTER_RE.match(text)
    if not match:
        return None, text, ["SKILL.md must start with closed YAML frontmatter"], []
    frontmatter_text = match.group(1)
    body = text[match.end() :]
    raw: Dict[str, Any] = {}
    metadata: Dict[str, str] = {}
    errors: List[str] = []
    warnings: List[str] = []
    lines = frontmatter_text.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        index += 1
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith((" ", "\t")):
            warnings.append(f"unsupported indented top-level line ignored: {line.strip()}")
            continue
        if ":" not in line:
            errors.append(f"unsupported frontmatter line: {line.strip()}")
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            errors.append("frontmatter contains an empty key")
            continue
        if value in {"|", ">"}:
            scalar, index = parse_block_scalar(lines, index, folded=value == ">")
            raw[key] = scalar
            continue
        if key == "metadata" and value == "":
            metadata, index, metadata_warnings = parse_metadata_block(lines, index)
            warnings.extend(metadata_warnings)
            raw[key] = metadata
            continue
        if value == "" or value.startswith(("[", "{", "&", "*", "!")):
            warnings.append(f"unsupported value for {key} ignored")
            continue
        if malformed_quoted_scalar(value):
            errors.append(f"unterminated quoted scalar for {key}")
            continue
        raw[key] = unquote_scalar(value)
    frontmatter = SkillFrontmatter(
        name=raw.get("name") if isinstance(raw.get("name"), str) else None,
        description=raw.get("description") if isinstance(raw.get("description"), str) else None,
        compatibility=raw.get("compatibility") if isinstance(raw.get("compatibility"), str) else None,
        license=raw.get("license") if isinstance(raw.get("license"), str) else None,
        allowed_tools=raw.get("allowed-tools") if isinstance(raw.get("allowed-tools"), str) else None,
        when_to_use=raw.get("when_to_use") if isinstance(raw.get("when_to_use"), str) else None,
        metadata=metadata,
        raw=raw,
    )
    return frontmatter, body, errors, warnings


def discover_skill_entries(root: Path) -> Tuple[List[Path], List[SkippedPath]]:
    skills_root = root / ".agents" / "skills"
    if has_symlink_component(root, Path(".agents/skills")):
        return [], [SkippedPath(".agents/skills/", "unmanaged-symlink-skill")]
    if not skills_root.is_dir():
        return [], []
    entries: List[Path] = []
    skipped: List[SkippedPath] = []
    for child in sorted(skills_root.iterdir(), key=lambda item: item.name.lower()):
        rel = child.relative_to(root)
        if child.is_symlink():
            skipped.append(SkippedPath(rel_posix(rel) + "/", "unmanaged-symlink-skill"))
            continue
        if child.is_dir():
            entries.append(child)
    return entries, skipped


def safe_skill_file_reason(path: Path, rel: Path) -> Optional[str]:
    reason = skip_file_reason(path, rel)
    if reason:
        return reason
    return None


def has_symlink_component(base: Path, rel: Path) -> bool:
    current = base
    for part in rel.parts:
        current = current / part
        if current.is_symlink():
            return True
    return False


def local_reference_target(value: str) -> Optional[str]:
    value = value.strip()
    if not value or value.startswith(("#", "http://", "https://", "mailto:")):
        return None
    if value.startswith("file://"):
        return value
    value = value.split("#", 1)[0].split("?", 1)[0]
    if value.startswith(("scripts/", "references/", "assets/", "evals/")):
        return value
    if value.startswith("/") or ".." in Path(value).parts:
        return value
    return None


def validate_local_reference(skill_root: Path, root_rel: Path, value: str) -> List[SkillDiagnostic]:
    target_text = local_reference_target(value)
    if target_text is None:
        return []
    diagnostic_path = root_rel / "SKILL.md"
    if target_text.startswith("file://"):
        return [diag(diagnostic_path, "unsafe-local-reference", f"unsafe local reference: {value}")]
    target = Path(target_text)
    rel_path = root_rel / target
    if target.is_absolute() or ".." in target.parts:
        return [diag(diagnostic_path, "unsafe-local-reference", f"unsafe local reference: {value}")]
    full = skill_root / target
    if has_symlink_component(skill_root, target):
        return [diag(rel_path, "unsafe-local-reference", f"reference crosses a symlink: {value}")]
    try:
        full.resolve().relative_to(skill_root.resolve())
    except ValueError:
        return [diag(rel_path, "unsafe-local-reference", f"reference escapes skill directory: {value}")]
    if not full.exists():
        return [diag(rel_path, "broken-local-reference", f"referenced path is missing: {value}")]
    if full.is_symlink():
        return [diag(rel_path, "unsafe-local-reference", f"referenced path is a symlink: {value}")]
    if full.is_file():
        reason = safe_skill_file_reason(full, rel_path)
        if reason:
            return [diag(rel_path, "unsafe-local-reference", f"referenced path is not safe to read: {reason}")]
    return []


def validate_local_references(skill_root: Path, root_rel: Path, text: str) -> List[SkillDiagnostic]:
    errors: List[SkillDiagnostic] = []
    for match in MARKDOWN_LINK_RE.findall(text):
        errors.extend(validate_local_reference(skill_root, root_rel, match))
    for match in BACKTICK_LOCAL_PATH_RE.findall(text):
        errors.extend(validate_local_reference(skill_root, root_rel, match))
    return errors


def validate_eval_input_file(skill_root: Path, root_rel: Path, value: object) -> Optional[SkillDiagnostic]:
    manifest_path = root_rel / "evals/evals.json"
    if not isinstance(value, str) or not value.strip():
        return diag(manifest_path, "unsafe-eval-input-file", "input_files entries must be non-empty strings")
    path = Path(value)
    rel_path = root_rel / path
    if path.is_absolute() or ".." in path.parts:
        return diag(manifest_path, "unsafe-eval-input-file", f"unsafe eval input file: {value}")
    full = skill_root / path
    if has_symlink_component(skill_root, path):
        return diag(rel_path, "unsafe-eval-input-file", f"eval input crosses a symlink: {value}")
    try:
        full.resolve().relative_to(skill_root.resolve())
    except ValueError:
        return diag(rel_path, "unsafe-eval-input-file", f"eval input escapes skill directory: {value}")
    if not full.exists():
        return diag(rel_path, "unsafe-eval-input-file", f"eval input file is missing: {value}")
    if full.is_symlink():
        return diag(rel_path, "unsafe-eval-input-file", f"eval input file is a symlink: {value}")
    reason = safe_skill_file_reason(full, rel_path)
    if reason:
        return diag(rel_path, "unsafe-eval-input-file", f"eval input file is not safe: {reason}")
    return None


def validate_eval_manifest(skill_root: Path, root_rel: Path, skill_name: str) -> SkillEvalManifest:
    rel = root_rel / "evals/evals.json"
    path = skill_root / "evals" / "evals.json"
    errors: List[SkillDiagnostic] = []
    warnings: List[SkillDiagnostic] = []
    case_ids: List[str] = []
    if not path.exists():
        warnings.append(diag(rel, "missing-evals", "evals/evals.json is absent"))
        return SkillEvalManifest(rel, False, False, 0, errors, warnings, case_ids)
    if path.is_symlink() or has_symlink_component(skill_root, Path("evals/evals.json")):
        errors.append(diag(rel, "invalid-evals-json", "evals/evals.json is a symlink and was not read"))
        return SkillEvalManifest(rel, True, False, 0, errors, warnings, case_ids)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        errors.append(diag(rel, "invalid-evals-json", f"evals/evals.json is not valid JSON: {error}"))
        return SkillEvalManifest(rel, True, False, 0, errors, warnings, case_ids)
    if not isinstance(data, dict):
        errors.append(diag(rel, "invalid-evals-json", "evals/evals.json must contain a JSON object"))
        return SkillEvalManifest(rel, True, True, 0, errors, warnings, case_ids)
    if not isinstance(data.get("schema_version"), int) or isinstance(data.get("schema_version"), bool) or data.get("schema_version") != 1:
        errors.append(diag(rel, "invalid-eval-case", "schema_version must be 1"))
    if data.get("skill_name") != skill_name:
        errors.append(diag(rel, "invalid-eval-case", "skill_name must match the skill name"))
    cases = data.get("evals")
    if not isinstance(cases, list):
        errors.append(diag(rel, "invalid-eval-case", "evals must be a list"))
        return SkillEvalManifest(rel, True, True, 0, errors, warnings, case_ids)
    seen: set[str] = set()
    has_trigger = False
    has_negative_trigger = False
    has_assertions = False
    allowed_kinds = {"trigger", "outcome", "process", "style", "efficiency"}
    for index, case in enumerate(cases):
        case_path = root_rel / "evals/evals.json"
        if not isinstance(case, dict):
            errors.append(diag(case_path, "invalid-eval-case", f"eval case {index} must be an object"))
            continue
        case_id = case.get("id")
        if not isinstance(case_id, str) or not case_id.strip():
            errors.append(diag(case_path, "invalid-eval-case", f"eval case {index} has no non-empty id"))
        elif case_id in seen:
            errors.append(diag(case_path, "invalid-eval-case", f"duplicate eval id: {case_id}"))
        else:
            seen.add(case_id)
            case_ids.append(case_id)
        prompt = case.get("prompt")
        if not isinstance(prompt, str) or not prompt.strip():
            errors.append(diag(case_path, "invalid-eval-case", f"eval case {case_id or index} has no prompt"))
        kind = case.get("kind", "outcome")
        kind_name = kind if isinstance(kind, str) else ""
        if kind_name not in allowed_kinds:
            errors.append(diag(case_path, "invalid-eval-case", f"eval case {case_id or index} has invalid kind"))
        should_trigger = case.get("should_trigger")
        if should_trigger is not None and not isinstance(should_trigger, bool):
            errors.append(diag(case_path, "invalid-eval-case", f"eval case {case_id or index} has non-bool should_trigger"))
        if kind_name == "trigger":
            has_trigger = True
            if should_trigger is False:
                has_negative_trigger = True
            if should_trigger is None:
                errors.append(diag(case_path, "invalid-eval-case", f"trigger eval {case_id or index} must set should_trigger"))
        assertions = case.get("assertions")
        negative_assertions = case.get("negative_assertions")
        deterministic_checks = case.get("deterministic_checks")
        for field_name, field_value in (
            ("assertions", assertions),
            ("negative_assertions", negative_assertions),
            ("deterministic_checks", deterministic_checks),
        ):
            if field_value is not None and not isinstance(field_value, list):
                errors.append(diag(case_path, "invalid-eval-case", f"eval case {case_id or index} {field_name} must be a list"))
        if any(isinstance(item, list) and item for item in (assertions, negative_assertions, deterministic_checks)):
            has_assertions = True
        expected_output = case.get("expected_output")
        if expected_output is not None and not isinstance(expected_output, str):
            errors.append(diag(case_path, "invalid-eval-case", f"eval case {case_id or index} expected_output must be a string"))
        if kind_name == "outcome" and not (isinstance(assertions, list) and assertions) and not (
            isinstance(expected_output, str) and expected_output.strip()
        ):
            errors.append(diag(case_path, "invalid-eval-case", f"outcome eval {case_id or index} needs expected_output or assertions"))
        if kind_name in {"process", "style"} and not (
            (isinstance(assertions, list) and assertions)
            or (isinstance(deterministic_checks, list) and deterministic_checks)
            or case.get("rubric")
        ):
            errors.append(diag(case_path, "invalid-eval-case", f"{kind} eval {case_id or index} needs assertions, checks, or rubric"))
        input_files = case.get("input_files", [])
        if input_files is None:
            input_files = []
        if not isinstance(input_files, list):
            errors.append(diag(case_path, "invalid-eval-case", f"eval case {case_id or index} input_files must be a list"))
        else:
            for item in input_files:
                input_error = validate_eval_input_file(skill_root, root_rel, item)
                if input_error is not None:
                    errors.append(input_error)
    if cases and not has_trigger:
        warnings.append(diag(rel, "missing-trigger-evals", "evals exist but no trigger eval was found"))
    if cases and not has_negative_trigger:
        warnings.append(diag(rel, "missing-negative-trigger-evals", "evals exist but no negative trigger eval was found"))
    if cases and not has_assertions:
        warnings.append(diag(rel, "missing-assertions", "evals exist but no assertions were found"))
    return SkillEvalManifest(rel, True, True, len(cases), errors, warnings, case_ids)


def collect_skill_paths(skill_root: Path, folder: str) -> List[Path]:
    path = skill_root / folder
    if not path.is_dir() or path.is_symlink():
        return []
    found: List[Path] = []
    for current, dirs, files in os.walk(path):
        current_path = Path(current)
        dirs[:] = sorted(dirname for dirname in dirs if not (current_path / dirname).is_symlink())
        for file_name in sorted(files):
            item = current_path / file_name
            if item.is_file() and not item.is_symlink():
                found.append(item.relative_to(skill_root))
    return found


def explicit_lifecycle(frontmatter: Optional[SkillFrontmatter]) -> Optional[str]:
    if frontmatter is None:
        return None
    value = frontmatter.metadata.get("agent-context-maintainer.status")
    if not value:
        return None
    return value.strip()


def vague_description(description: str) -> bool:
    normalized = re.sub(r"\s+", " ", description).strip().lower()
    return len(normalized) < 40 or normalized in {"helps.", "helps", "helper", "useful skill"}


def validate_skill_directory(root: Path, skill_dir: Path) -> SkillInfo:
    root_rel = skill_dir.relative_to(root)
    skill_md = skill_dir / "SKILL.md"
    rel_skill_md = root_rel / "SKILL.md"
    warnings: List[SkillDiagnostic] = []
    errors: List[SkillDiagnostic] = []
    description = ""
    compatibility: Optional[str] = None
    allowed_tools: Optional[str] = None
    frontmatter: Optional[SkillFrontmatter] = None
    line_count = 0
    byte_count = 0
    name = skill_dir.name
    if not SKILL_NAME_RE.match(skill_dir.name):
        errors.append(diag(root_rel, "invalid-directory-name", "skill directory name must be lowercase ASCII, digits, or hyphen"))
    if not skill_md.exists():
        errors.append(diag(rel_skill_md, "missing-skill-md", "SKILL.md is missing"))
        empty_eval = SkillEvalManifest(root_rel / "evals/evals.json", False, False, 0, [], [], [])
        quality = SkillQuality("missing", False, False, False)
        return SkillInfo(
            name,
            root_rel,
            None,
            None,
            description,
            compatibility,
            allowed_tools,
            "invalid",
            "active",
            quality,
            [],
            [],
            [],
            None,
            empty_eval,
            line_count,
            byte_count,
            warnings,
            errors,
        )
    if skill_md.is_symlink():
        errors.append(diag(rel_skill_md, "unsafe-local-reference", "SKILL.md is a symlink and was not read"))
        empty_eval = SkillEvalManifest(root_rel / "evals/evals.json", False, False, 0, [], [], [])
        quality = SkillQuality("missing", False, False, False)
        return SkillInfo(
            name,
            root_rel,
            rel_skill_md,
            None,
            description,
            compatibility,
            allowed_tools,
            "invalid",
            "active",
            quality,
            [],
            [],
            [],
            None,
            empty_eval,
            line_count,
            byte_count,
            warnings,
            errors,
        )
    stat_ok = False
    read_ok = False
    try:
        byte_count = skill_md.stat().st_size
        stat_ok = True
    except OSError:
        errors.append(diag(rel_skill_md, "missing-skill-md", "SKILL.md cannot be read"))
        byte_count = 0
    text = ""
    if stat_ok:
        if byte_count > MAX_SKILL_MD_BYTES:
            errors.append(diag(rel_skill_md, "skill-md-too-large", "SKILL.md exceeds maximum size"))
        else:
            try:
                text = skill_md.read_text(encoding="utf-8")
                read_ok = True
            except UnicodeDecodeError as error:
                errors.append(diag(rel_skill_md, "invalid-frontmatter", f"SKILL.md is not valid UTF-8: {error}"))
            except OSError as error:
                errors.append(diag(rel_skill_md, "missing-skill-md", f"SKILL.md cannot be read: {error}"))
        line_count = len(text.splitlines())
    if text:
        frontmatter, _body, parse_errors, parse_warnings = parse_skill_frontmatter(text)
        errors.extend(diag(rel_skill_md, "invalid-frontmatter", item) for item in parse_errors)
        warnings.extend(diag(rel_skill_md, "invalid-frontmatter", item) for item in parse_warnings)
        if frontmatter is not None:
            fm_name = (frontmatter.name or "").strip()
            if not fm_name:
                errors.append(diag(rel_skill_md, "missing-name", "frontmatter name is required"))
            elif not SKILL_NAME_RE.match(fm_name):
                errors.append(diag(rel_skill_md, "invalid-name", "frontmatter name has an invalid format"))
            elif fm_name != skill_dir.name:
                errors.append(diag(rel_skill_md, "name-directory-mismatch", "frontmatter name must match parent directory"))
            else:
                name = fm_name
            description = (frontmatter.description or "").strip()
            compatibility = frontmatter.compatibility
            allowed_tools = frontmatter.allowed_tools
            if not description:
                errors.append(diag(rel_skill_md, "missing-description", "frontmatter description is required"))
            elif len(description) > MAX_SKILL_DESCRIPTION_CHARS:
                errors.append(diag(rel_skill_md, "long-description", "description exceeds 1024 characters"))
            elif vague_description(description):
                warnings.append(diag(rel_skill_md, "vague-description", "description is too short or vague"))
            if description and not re.search(r"\b(Use when|Use for|Do not use when)\b", description, re.I):
                warnings.append(diag(rel_skill_md, "missing-trigger-boundary", "description should describe when to use the skill"))
            if compatibility is not None and len(compatibility) > MAX_SKILL_COMPATIBILITY_CHARS:
                errors.append(diag(rel_skill_md, "long-compatibility", "compatibility exceeds 500 characters"))
            if len(description) + len(frontmatter.when_to_use or "") > MAX_SKILL_LISTING_ENTRY_CHARS:
                warnings.append(
                    diag(
                        rel_skill_md,
                        "long-listing-entry",
                        f"combined description and when_to_use exceed {MAX_SKILL_LISTING_ENTRY_CHARS} characters "
                        "(Claude Code truncates the listing entry)",
                    )
                )
            lifecycle_value = explicit_lifecycle(frontmatter)
            if lifecycle_value and lifecycle_value not in SKILL_LIFECYCLES:
                warnings.append(diag(rel_skill_md, "invalid-lifecycle", "unknown lifecycle metadata; defaulting to active"))
            if allowed_tools:
                warnings.append(diag(rel_skill_md, "allowed-tools-experimental", "allowed-tools is metadata only, not a safety boundary"))
        else:
            errors.append(diag(rel_skill_md, "invalid-frontmatter", "frontmatter could not be parsed"))
        if line_count > MAX_SKILL_MAIN_LINES:
            warnings.append(diag(rel_skill_md, "long-skill-md", "SKILL.md is longer than 500 lines"))
        for line_no, line in enumerate(text.splitlines(), start=1):
            if RISK_RE.search(line) and not NEGATION_RE.search(line):
                warnings.append(diag(rel_skill_md, "risk-text", f"possible secret/log handling risk near line {line_no}"))
                break
        errors.extend(validate_local_references(skill_dir, root_rel, text))
    elif stat_ok and read_ok and byte_count == 0:
        errors.append(diag(rel_skill_md, "invalid-frontmatter", "SKILL.md is empty"))
        errors.append(diag(rel_skill_md, "missing-name", "frontmatter name is required"))
        errors.append(diag(rel_skill_md, "missing-description", "frontmatter description is required"))
    eval_manifest = validate_eval_manifest(skill_dir, root_rel, name)
    warnings.extend(eval_manifest.warnings)
    errors.extend(eval_manifest.errors)
    scripts = sorted((root_rel / item for item in collect_skill_paths(skill_dir, "scripts")), key=str)
    references = sorted((root_rel / item for item in collect_skill_paths(skill_dir, "references")), key=str)
    assets = sorted((root_rel / item for item in collect_skill_paths(skill_dir, "assets")), key=str)
    if scripts and not compatibility:
        warnings.append(diag(rel_skill_md, "script-without-compatibility", "scripts exist but compatibility does not describe runtime requirements"))
    codex_metadata_path = skill_dir / "agents" / "openai.yaml"
    # exists() follows symlinks — including a symlinked agents/ parent directory —
    # so the component-wise symlink check must come first to catch dangling links
    # and parent links before any read attempt.
    adapter_symlinked = has_symlink_component(skill_dir, Path("agents/openai.yaml"))
    codex_metadata = root_rel / "agents/openai.yaml" if adapter_symlinked or codex_metadata_path.exists() else None
    if codex_metadata is not None:
        # The inventory records that the adapter exists (the path stays in
        # codex_metadata) even when it cannot be read; the warnings below make
        # the unreadable cases explicit instead of hiding them.
        if adapter_symlinked:
            warnings.append(diag(codex_metadata, "codex-metadata-symlink", "agents/openai.yaml is a symlink or behind a symlinked directory and was not read"))
        else:
            skip = skip_file_reason(codex_metadata_path, codex_metadata)
            if skip:
                warnings.append(diag(codex_metadata, "codex-metadata-unreadable", f"agents/openai.yaml is not safe to read: {skip}"))
            elif read_utf8_text(codex_metadata_path) is None:
                warnings.append(diag(codex_metadata, "codex-metadata-unreadable", "agents/openai.yaml is not valid UTF-8 or could not be read"))
            else:
                warnings.append(diag(codex_metadata, "codex-metadata-unparsed", "agents/openai.yaml exists but is not parsed"))
    quality = skill_manifest_quality(eval_manifest)
    lifecycle = "active"
    lifecycle_value = explicit_lifecycle(frontmatter)
    if lifecycle_value in SKILL_LIFECYCLES:
        lifecycle = lifecycle_value
    validity = "invalid" if errors else "valid"
    return SkillInfo(
        name,
        root_rel,
        rel_skill_md,
        frontmatter,
        description,
        compatibility,
        allowed_tools,
        validity,
        lifecycle,
        quality,
        scripts,
        references,
        assets,
        codex_metadata,
        eval_manifest,
        line_count,
        byte_count,
        warnings,
        errors,
    )


def build_skill_inventory(root: Path) -> SkillInventory:
    entries, skipped = discover_skill_entries(root)
    skills = [validate_skill_directory(root, entry) for entry in entries]
    seen: Dict[str, Path] = {}
    description_owner: Dict[str, Path] = {}
    updated_skills: List[SkillInfo] = []
    for skill in skills:
        warnings = list(skill.warnings)
        lower = skill.directory.name.lower()
        if lower in seen and lower != skill.directory.name:
            warning = diag(skill.directory, "case-insensitive-duplicate-name", "skill directory differs only by case")
            warnings.append(warning)
        seen[lower] = skill.directory
        normalized_desc = re.sub(r"\s+", " ", skill.description).strip().lower()
        if normalized_desc:
            if normalized_desc in description_owner:
                warnings.append(diag(skill.skill_md or skill.directory, "duplicate-description", "description duplicates another skill"))
            description_owner[normalized_desc] = skill.directory
        updated_skills.append(replace(skill, warnings=warnings))
    return SkillInventory(root, updated_skills, skipped, [])


def load_skill_overrides(root: Path) -> Tuple[Dict[str, Dict[str, Any]], List[SkillDiagnostic]]:
    path = root / ".agents" / "skill-overrides.json"
    if not path.exists():
        return {}, []
    rel = Path(".agents/skill-overrides.json")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        return {}, [diag(rel, "invalid-skill-overrides", f"skill overrides are not valid JSON: {error}")]
    if not isinstance(data, dict):
        return {}, [diag(rel, "invalid-skill-overrides", "skill overrides must contain a JSON object")]
    overrides: Dict[str, Dict[str, Any]] = {}
    errors: List[SkillDiagnostic] = []
    for name, value in data.items():
        if not isinstance(name, str) or not SKILL_NAME_RE.match(name):
            errors.append(diag(rel, "invalid-skill-overrides", f"invalid override skill name: {name}"))
            continue
        if not isinstance(value, dict):
            errors.append(diag(rel, "invalid-skill-overrides", f"override for {name} must be an object"))
            continue
        if "lifecycle" in value:
            lifecycle = value.get("lifecycle")
            if not isinstance(lifecycle, str) or lifecycle not in SKILL_LIFECYCLES:
                errors.append(diag(rel, "invalid-skill-overrides", f"invalid lifecycle for {name}: {lifecycle}"))
                continue
        else:
            lifecycle = None
        overrides[name] = value
    return overrides, errors


def apply_skill_overrides(inv: SkillInventory) -> SkillInventory:
    overrides, override_errors = load_skill_overrides(inv.root)
    if not overrides:
        return SkillInventory(inv.root, inv.skills, inv.skipped, inv.errors + override_errors)
    updated: List[SkillInfo] = []
    known = {skill.name for skill in inv.skills}
    extra_errors = list(override_errors)
    for name in sorted(set(overrides) - known):
        extra_errors.append(diag(Path(".agents/skill-overrides.json"), "invalid-skill-overrides", f"override references missing skill: {name}"))
    for skill in inv.skills:
        override = overrides.get(skill.name, {})
        lifecycle = override["lifecycle"] if "lifecycle" in override else skill.lifecycle
        updated.append(replace(skill, lifecycle=lifecycle))
    return SkillInventory(inv.root, updated, inv.skipped, inv.errors + extra_errors)


def skill_inventory(root: Path, include_overrides: bool = True) -> SkillInventory:
    inv = build_skill_inventory(root)
    return apply_skill_overrides(inv) if include_overrides else inv


def skill_manifest_quality(inv: SkillEvalManifest) -> SkillQuality:
    has_trigger = inv.exists and inv.eval_count > 0 and not any(w.code == "missing-trigger-evals" for w in inv.warnings)
    has_negative = inv.exists and inv.eval_count > 0 and not any(w.code == "missing-negative-trigger-evals" for w in inv.warnings)
    has_assertions = inv.exists and inv.eval_count > 0 and not any(w.code == "missing-assertions" for w in inv.warnings)
    if inv.errors:
        coverage = "invalid"
    elif inv.exists:
        coverage = "present" if inv.eval_count else "partial"
    else:
        coverage = "missing"
    return SkillQuality(coverage, has_trigger, has_negative, has_assertions)


def skill_to_json(skill: SkillInfo) -> Dict[str, object]:
    return {
        "name": skill.name,
        "directory": rel_posix(skill.directory),
        "path": rel_posix(skill.skill_md) if skill.skill_md else None,
        "validity": skill.validity,
        "lifecycle": skill.lifecycle,
        "description": skill.description,
        "compatibility": skill.compatibility,
        "allowed_tools": skill.allowed_tools,
        "codex_metadata": rel_posix(skill.codex_metadata) if skill.codex_metadata else None,
        "quality": {
            "eval_coverage": skill.quality.eval_coverage,
            "has_trigger_evals": skill.quality.has_trigger_evals,
            "has_negative_trigger_evals": skill.quality.has_negative_trigger_evals,
            "has_assertions": skill.quality.has_assertions,
        },
        "counts": {
            "lines": skill.line_count,
            "bytes": skill.byte_count,
            "scripts": len(skill.scripts),
            "references": len(skill.references),
            "assets": len(skill.assets),
            "evals": skill.eval_manifest.eval_count,
        },
        "evals": {
            "path": rel_posix(skill.eval_manifest.path),
            "exists": skill.eval_manifest.exists,
            "valid_json": skill.eval_manifest.valid_json,
            "eval_count": skill.eval_manifest.eval_count,
            "case_ids": skill.eval_manifest.case_ids,
            "errors": [diag_dict(item) for item in skill.eval_manifest.errors],
            "warnings": [diag_dict(item) for item in skill.eval_manifest.warnings],
        },
        "warnings": [diag_dict(item) for item in skill.warnings],
        "errors": [diag_dict(item) for item in skill.errors],
    }


def skill_inventory_json(inv: SkillInventory) -> Dict[str, object]:
    return {
        "root_name": inv.root.name,
        "skills_root": ".agents/skills",
        "skill_count": len(inv.skills),
        "skills": [skill_to_json(skill) for skill in inv.skills],
        "skipped": [{"path": item.path, "reason": item.reason} for item in inv.skipped],
        "errors": [diag_dict(item) for item in inv.errors],
    }


def skill_inventory_diagnostics(inv: SkillInventory) -> Tuple[List[SkillDiagnostic], List[SkillDiagnostic]]:
    warnings: List[SkillDiagnostic] = []
    errors: List[SkillDiagnostic] = list(inv.errors)
    for skipped in inv.skipped:
        if skipped.reason == "unmanaged-symlink-skill":
            warnings.append(SkillDiagnostic(skipped.path, skipped.reason, "symlinked skill directory was not followed"))
    for skill in inv.skills:
        warnings.extend(skill.warnings)
        errors.extend(skill.errors)
    listing_estimate = sum(
        len(skill.name) + len(skill.description) + len(rel_posix(skill.skill_md))
        for skill in inv.skills
        if skill.validity == "valid" and skill.skill_md is not None
    )
    if listing_estimate > CODEX_LISTING_FALLBACK_BUDGET_CHARS:
        warnings.append(
            SkillDiagnostic(
                ".agents/skills",
                "listing-budget-estimate",
                f"estimated Codex skill listing is {listing_estimate} chars and exceeds "
                f"{CODEX_LISTING_FALLBACK_BUDGET_CHARS} chars (fallback estimate; the real budget is 2% of the context window)",
            )
        )
    return warnings, errors


def check_skill_errors_only(root: Path) -> List[str]:
    _warnings, errors = skill_inventory_diagnostics(skill_inventory(root))
    return [f"{item.path}: {item.code}: {item.message}" for item in errors]


def sanitize_inline(value: str) -> str:
    value = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", value)
    value = re.sub(r"\s+", " ", value).strip()
    return value.replace("`", "\\`").replace("|", "\\|")


def yaml_scalar(value: Optional[str]) -> str:
    if value is None:
        return "null"
    escaped = []
    for char in value:
        code = ord(char)
        if char == "\\":
            escaped.append("\\\\")
        elif char == '"':
            escaped.append('\\"')
        elif char == "\n":
            escaped.append("\\n")
        elif char == "\r":
            escaped.append("\\r")
        elif code < 32:
            escaped.append(f"\\x{code:02x}")
        else:
            escaped.append(char)
    return '"' + "".join(escaped) + '"'


def skill_registry_body(inv: SkillInventory, reviewed_date: str = SKILL_REGISTRY_REVIEWED) -> str:
    lines = [
        "schema_version: 1",
        f"source_reviewed: {yaml_scalar(reviewed_date)}",
        'generated_by: "agent-context-maintainer"',
        "skills:",
    ]
    for skill in inv.skills:
        lines.append(f"  - name: {yaml_scalar(skill.name)}")
        lines.append(f"    path: {yaml_scalar(rel_posix(skill.skill_md) if skill.skill_md else None)}")
        lines.append(f"    directory: {yaml_scalar(rel_posix(skill.directory))}")
        lines.append(f"    validity: {yaml_scalar(skill.validity)}")
        lines.append(f"    lifecycle: {yaml_scalar(skill.lifecycle)}")
        lines.append(f"    description: {yaml_scalar(sanitize_inline(skill.description))}")
        lines.append(f"    compatibility: {yaml_scalar(skill.compatibility)}")
        lines.append(f"    allowed_tools: {yaml_scalar(skill.allowed_tools)}")
        lines.append(f"    codex_metadata: {yaml_scalar(rel_posix(skill.codex_metadata) if skill.codex_metadata else None)}")
        lines.append("    quality:")
        lines.append(f"      eval_coverage: {yaml_scalar(skill.quality.eval_coverage)}")
        lines.append(f"      has_trigger_evals: {str(skill.quality.has_trigger_evals).lower()}")
        lines.append(f"      has_negative_trigger_evals: {str(skill.quality.has_negative_trigger_evals).lower()}")
        lines.append(f"      has_assertions: {str(skill.quality.has_assertions).lower()}")
        lines.append("    counts:")
        lines.append(f"      lines: {skill.line_count}")
        lines.append(f"      bytes: {skill.byte_count}")
        lines.append(f"      scripts: {len(skill.scripts)}")
        lines.append(f"      references: {len(skill.references)}")
        lines.append(f"      assets: {len(skill.assets)}")
        lines.append(f"      evals: {skill.eval_manifest.eval_count}")
        lines.append("    warnings:")
        if skill.warnings:
            for warning in skill.warnings:
                lines.append(f"      - {yaml_scalar(warning.code)}")
        else:
            lines.append("      []")
        lines.append("    errors:")
        if skill.errors:
            for error in skill.errors:
                lines.append(f"      - {yaml_scalar(error.code)}")
        else:
            lines.append("      []")
    if not inv.skills:
        lines.append("  []")
    return "\n".join(lines)


def skill_report_body(inv: SkillInventory, reviewed_date: str = SKILL_REGISTRY_REVIEWED) -> str:
    warnings, errors = skill_inventory_diagnostics(inv)
    valid = sum(1 for skill in inv.skills if skill.validity == "valid")
    invalid = sum(1 for skill in inv.skills if skill.validity == "invalid")
    lifecycle_counts = {item: sum(1 for skill in inv.skills if skill.lifecycle == item) for item in SKILL_LIFECYCLES}
    eval_present = sum(1 for skill in inv.skills if skill.eval_manifest.exists)
    symlink_count = sum(1 for item in inv.skipped if item.reason == "unmanaged-symlink-skill")
    lines = [
        "## Summary",
        "",
        f"- Source reviewed: {reviewed_date}",
        f"- Skills scanned: {len(inv.skills)}",
        f"- Valid: {valid}",
        f"- Invalid: {invalid}",
        f"- Active: {lifecycle_counts.get('active', 0)}",
        f"- Explicit draft: {lifecycle_counts.get('draft', 0)}",
        f"- Deprecated: {lifecycle_counts.get('deprecated', 0)}",
        f"- Eval manifests present: {eval_present}",
        f"- Eval manifests missing: {len(inv.skills) - eval_present}",
        f"- Unmanaged symlink skill directories: {symlink_count}",
        "",
        "## Action Required",
        "",
    ]
    if errors:
        for index, error in enumerate(errors, start=1):
            lines.append(f"{index}. `{sanitize_inline(error.path)}`: {sanitize_inline(error.code)} - {sanitize_inline(error.message)}")
    else:
        lines.append("None.")
    lines.extend(["", "## Warnings", ""])
    if warnings:
        for warning in warnings:
            lines.append(f"- `{sanitize_inline(warning.path)}`: {sanitize_inline(warning.code)} - {sanitize_inline(warning.message)}")
    else:
        lines.append("None.")
    lines.extend(["", "## Skills", ""])
    for skill in inv.skills:
        lines.append(f"### {sanitize_inline(skill.name)}")
        lines.append("")
        lines.append(f"- Validity: {skill.validity}")
        lines.append(f"- Lifecycle: {skill.lifecycle}")
        lines.append(f"- Path: `{sanitize_inline(rel_posix(skill.skill_md) if skill.skill_md else rel_posix(skill.directory))}`")
        lines.append(f"- Eval coverage: {skill.quality.eval_coverage}")
        lines.append(f"- Warnings: {', '.join(sorted({item.code for item in skill.warnings})) or 'none'}")
        lines.append(f"- Errors: {', '.join(sorted({item.code for item in skill.errors})) or 'none'}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def render_skill_report(root: Path, reviewed_date: str = SKILL_REGISTRY_REVIEWED) -> str:
    return generated_file_content(
        skill_report_body(skill_inventory(root), reviewed_date),
        "Skill Health Report",
        MARKDOWN_MARKERS,
    )


def planned_skill_sync(root: Path, options: ScaffoldOptions, reviewed_date: str = SKILL_REGISTRY_REVIEWED) -> List[PlannedWrite]:
    inv = skill_inventory(root)
    registry_content = generated_file_content(skill_registry_body(inv, reviewed_date), None, YAML_MARKERS)
    report_content = generated_file_content(skill_report_body(inv, reviewed_date), "Skill Health Report", MARKDOWN_MARKERS)
    return [
        classify_recreate(root, root / ".agents" / "skill-registry.yaml", registry_content, None, options, YAML_MARKERS),
        classify_recreate(root, root / ".agents" / "skill-reports" / "skill-health.md", report_content, "Skill Health Report", options, MARKDOWN_MARKERS),
    ]


def skills_sync(root: Path, options: ScaffoldOptions, reviewed_date: str = SKILL_REGISTRY_REVIEWED) -> List[Tuple[str, Path]]:
    planned = planned_skill_sync(root, options, reviewed_date)
    if options.dry_run:
        return [(f"would-{item.action}", item.path) for item in planned if item.write]
    return apply_planned_writes(root, planned)


def route_label_for_skill(
    root: Path,
    skill: SkillInfo,
    overrides: Optional[Dict[str, Dict[str, Any]]] = None,
) -> Optional[str]:
    if overrides is None:
        overrides, _errors = load_skill_overrides(root)
    override = overrides.get(skill.name, {})
    label = override.get("route_label")
    if isinstance(label, str) and label.strip():
        return sanitize_inline(label.strip())
    if skill.lifecycle == "experimental" and not label:
        return None
    return sanitize_inline(skill.description.split(".")[0] or skill.name)


def skill_routes_body(root: Path) -> str:
    inv = skill_inventory(root)
    if inv.errors:
        first = inv.errors[0]
        raise AgentContextError(f"cannot sync skill routes with inventory errors: {first.path}: {first.code}")
    overrides, override_errors = load_skill_overrides(root)
    if override_errors:
        first = override_errors[0]
        raise AgentContextError(f"cannot sync skill routes with override errors: {first.path}: {first.code}")
    lines: List[str] = []
    for skill in inv.skills:
        if skill.validity != "valid" or skill.lifecycle in {"draft", "deprecated", "archived"}:
            continue
        if skill.lifecycle not in {"active", "watch", "experimental"}:
            continue
        label = route_label_for_skill(root, skill, overrides)
        if not label:
            continue
        lines.append(f"- {label}: read `{rel_posix(skill.skill_md)}`.")
    return "\n".join(lines) if lines else "- No active skill routes detected."


def sync_skill_routes(root: Path, options: ScaffoldOptions) -> List[Tuple[str, Path]]:
    path = root / ".agents" / "routing.md"
    block = "## Skill Routes\n\n" + generated_block(skill_routes_body(root), SKILL_ROUTE_MARKERS)
    if not path.exists():
        planned = PlannedWrite(path, "# Agent Routing\n\n" + block, "created", False)
    elif path.is_symlink() or not path.is_file():
        raise AgentContextError(f"{path} is not a regular file; refusing to update routing")
    else:
        current = path.read_text(encoding="utf-8")
        error = marker_error(path, current, SKILL_ROUTE_MARKERS)
        if error:
            raise AgentContextError(error)
        if generated_block_span(current, SKILL_ROUTE_MARKERS) is not None:
            updated = replace_generated_block(current, generated_block(skill_routes_body(root), SKILL_ROUTE_MARKERS), SKILL_ROUTE_MARKERS)
            if updated == current:
                planned = PlannedWrite(path, updated, "unchanged", False, False)
            else:
                planned = PlannedWrite(path, updated, "updated-generated-block", should_snapshot_generated_update(root, path, current, SKILL_ROUTE_MARKERS))
        else:
            separator = "\n\n" if current.endswith("\n") else "\n\n"
            planned = PlannedWrite(path, current + separator + block, "appended-generated-block", False)
    if options.dry_run:
        return [(f"would-{planned.action}", planned.path)] if planned.write else []
    return apply_planned_writes(root, [planned])


def check_skill_routes(root: Path) -> List[str]:
    path = root / ".agents" / "routing.md"
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8")
    span = generated_block_span(text, SKILL_ROUTE_MARKERS)
    if span is None:
        return []
    block = text[span.begin_start : span.end_end]
    inv = skill_inventory(root)
    errors = [f"{item.path}: {item.code}: {item.message}" for item in inv.errors]
    overrides, override_errors = load_skill_overrides(root)
    errors.extend(f"{item.path}: {item.code}: {item.message}" for item in override_errors)
    by_path = {rel_posix(skill.skill_md): skill for skill in inv.skills if skill.skill_md is not None}
    for ref in re.findall(r"`(\.agents/skills/[^`]+/SKILL\.md)`", block):
        skill = by_path.get(ref)
        if skill is None:
            errors.append(f".agents/routing.md routes missing skill: {ref}")
            continue
        if skill.validity != "valid" or skill.lifecycle in {"draft", "deprecated", "archived"}:
            errors.append(f".agents/routing.md routes inactive or invalid skill: {ref}")
        if skill.lifecycle == "experimental" and route_label_for_skill(root, skill, overrides) is None:
            errors.append(f".agents/routing.md routes experimental skill without explicit route_label: {ref}")
    return errors


def eval_plan_for_skill(skill: SkillInfo) -> Dict[str, object]:
    return {
        "skill": skill.name,
        "workspace": rel_posix(Path(".agents/skill-workspaces") / skill.name / "iteration-1"),
        "eval_count": skill.eval_manifest.eval_count,
        "eval_ids": skill.eval_manifest.case_ids,
        "will_run_agent": False,
    }


def skills_eval_plan(root: Path, skill_name: Optional[str] = None) -> Dict[str, object]:
    inv = skill_inventory(root)
    selected = [skill for skill in inv.skills if skill_name is None or skill.name == skill_name]
    if skill_name is not None and not selected:
        raise AgentContextError(f"skill not found: {skill_name}")
    return {"root_name": root.name, "skills": [eval_plan_for_skill(skill) for skill in selected]}


def next_workspace_iteration(root: Path, skill_name: str) -> Path:
    base = root / ".agents" / "skill-workspaces" / skill_name
    index = 1
    while (base / f"iteration-{index}").exists():
        index += 1
    return base / f"iteration-{index}"


def init_skill_workspace(root: Path, skill_name: str) -> List[Tuple[str, Path]]:
    inv = skill_inventory(root)
    matches = [skill for skill in inv.skills if skill.name == skill_name]
    if not matches:
        raise AgentContextError(f"skill not found: {skill_name}")
    skill = matches[0]
    # SKILL.md is the evaluation target; skipping unreadable files is only
    # acceptable for the optional references below.
    if skill.skill_md is None:
        raise AgentContextError(f"skill has no SKILL.md to snapshot: {skill_name}")
    source = root / skill.skill_md
    if source.is_symlink():
        raise AgentContextError(f"SKILL.md is a symlink and was not read: {rel_posix(skill.skill_md)}")
    skill_md_text = read_utf8_text(source)
    if skill_md_text is None:
        raise AgentContextError(f"SKILL.md cannot be read as UTF-8: {rel_posix(skill.skill_md)}")
    workspace = next_workspace_iteration(root, skill_name)
    changes: List[Tuple[str, Path]] = []
    snapshot = workspace / "skill-snapshot"
    snapshot.mkdir(parents=True, exist_ok=True)
    target = snapshot / "SKILL.md"
    target.write_text(skill_md_text, encoding="utf-8")
    changes.append(("created", target))
    for folder in ("references",):
        source_dir = root / skill.directory / folder
        if source_dir.is_dir() and not source_dir.is_symlink():
            for current, dirs, files in os.walk(source_dir):
                current_path = Path(current)
                dirs[:] = sorted(dirname for dirname in dirs if not (current_path / dirname).is_symlink())
                for file_name in sorted(files):
                    source = current_path / file_name
                    if source.is_symlink() or not source.is_file():
                        continue
                    source_rel = source.relative_to(root)
                    if skip_file_reason(source, source_rel):
                        continue
                    text = read_utf8_text(source)
                    if text is None:
                        continue
                    rel = source.relative_to(source_dir)
                    target = snapshot / folder / rel
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text(text, encoding="utf-8")
                    changes.append(("created", target))
    for case_id in skill.eval_manifest.case_ids or ["manual"]:
        safe_id = re.sub(r"[^a-zA-Z0-9_.-]+", "-", case_id).strip("-") or "manual"
        for mode in ("with_skill", "without_skill"):
            case_dir = workspace / f"eval-{safe_id}" / mode
            (case_dir / "outputs").mkdir(parents=True, exist_ok=True)
            prompt = (
                f"# Eval {case_id}\n\n"
                f"Skill: {skill.name}\n"
                f"Mode: {mode}\n\n"
                "Fill in a task prompt from evals/evals.json manually. Raw prompts are not copied by SkillOps.\n"
            )
            (case_dir / "prompt.md").write_text(prompt, encoding="utf-8")
            (case_dir / "grading-template.json").write_text(
                json.dumps({"eval_id": case_id, "mode": mode, "assertions": []}, indent=2) + "\n",
                encoding="utf-8",
            )
            changes.append(("created", case_dir / "prompt.md"))
            changes.append(("created", case_dir / "grading-template.json"))
    (workspace / "benchmark-template.json").write_text(
        json.dumps({"schema_version": 1, "skill": skill.name, "runs": []}, indent=2) + "\n",
        encoding="utf-8",
    )
    (workspace / "feedback.json").write_text(
        json.dumps({"schema_version": 1, "skill": skill.name, "findings": []}, indent=2) + "\n",
        encoding="utf-8",
    )
    changes.append(("created", workspace / "benchmark-template.json"))
    changes.append(("created", workspace / "feedback.json"))
    return changes


def codex_eval_command(prompt: str, sandbox: str, full_auto: bool = False) -> List[str]:
    if full_auto:
        return ["codex", "exec", "--json", "--full-auto", prompt]
    return ["codex", "exec", "--json", "--sandbox", sandbox, prompt]


def under_skill_workspace(path: Path, root: Optional[Path] = None) -> bool:
    resolved = path.resolve()
    if root is not None:
        workspace_root = (root / ".agents" / "skill-workspaces").resolve()
        try:
            resolved.relative_to(workspace_root)
            return True
        except ValueError:
            return False
    parts = resolved.parts
    marker = (".agents", "skill-workspaces")
    return any(parts[index : index + 2] == marker for index in range(max(0, len(parts) - 1)))


def run_codex_eval(
    prompt_path: Path,
    output_path: Path,
    sandbox: str,
    understand_danger: bool,
    full_auto: bool = False,
    root: Optional[Path] = None,
) -> List[str]:
    if not under_skill_workspace(output_path, root):
        raise AgentContextError("codex eval trace output must be under .agents/skill-workspaces")
    if root is not None and not under_skill_workspace(prompt_path, root):
        raise AgentContextError("codex eval prompt must be under .agents/skill-workspaces")
    if sandbox == "danger-full-access":
        if not understand_danger:
            raise AgentContextError("danger-full-access requires --i-understand-danger")
        if not under_skill_workspace(prompt_path, root):
            raise AgentContextError("danger-full-access evals must run inside .agents/skill-workspaces")
        print("warning: danger-full-access is suitable only for isolated CI/container environments")
    prompt = prompt_path.read_text(encoding="utf-8")
    cmd = codex_eval_command(prompt, sandbox, full_auto)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(cmd, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    output_path.write_text(result.stdout, encoding="utf-8")
    if result.returncode != 0:
        raise AgentContextError(f"codex eval failed with exit {result.returncode}: {result.stderr.strip()}")
    return cmd


def detect_agent() -> Tuple[str, Optional[str]]:
    """Detect the active agent runtime from exact-match environment variables.

    Returns (agent, matched_variable). Falls back to ("generic", None) when no
    confirmed variable is present; substring matching is deliberately avoided
    because unrelated variables (for example COPILOT_OTEL_FILE_EXPORTER_PATH in
    non-Copilot sessions) make prefixes unreliable signals.
    """
    for key in DETECT_PRIORITY:
        for var in PROVIDERS[key]["detect_env"]:
            if var in os.environ:
                return key, var
    return "generic", None


def bullet_list(items: list[str], fallback: str) -> str:
    if not items:
        return f"- {fallback}"
    # Continuation lines carry the 4-space indent of the template f-strings so
    # that dedent() still finds a uniform prefix; otherwise the interpolated
    # lines would disable dedenting and leak indentation into the output,
    # which Markdown renders as code blocks.
    return "\n    ".join(f"- `{item}`" for item in items)


def generated_block(body: str, markers: MarkerStyle = MARKDOWN_MARKERS) -> str:
    return f"{markers.begin}\n{body.strip()}\n{markers.end}\n"


def generated_file_content(
    body: str,
    heading: Optional[str] = None,
    markers: MarkerStyle = MARKDOWN_MARKERS,
) -> str:
    prefix = f"# {heading}\n\n" if heading else ""
    return prefix + generated_block(body, markers)


def marker_events(text: str, markers: MarkerStyle = MARKDOWN_MARKERS) -> list[tuple[str, int, int]]:
    events: list[tuple[str, int, int]] = []
    in_fence = False
    fence_prefix = ""
    offset = 0
    ignore_fences = markers == MARKDOWN_MARKERS

    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        lstripped = line.lstrip()
        if ignore_fences and (lstripped.startswith("```") or lstripped.startswith("~~~")):
            prefix = lstripped[:3]
            if not in_fence:
                in_fence = True
                fence_prefix = prefix
            elif prefix == fence_prefix:
                in_fence = False
                fence_prefix = ""
            offset += len(line)
            continue
        if not in_fence:
            if stripped == markers.begin:
                events.append(("begin", offset, offset + len(line)))
            elif stripped == markers.end:
                events.append(("end", offset, offset + len(line)))
        offset += len(line)
    return events


def generated_block_span(text: str, markers: MarkerStyle = MARKDOWN_MARKERS) -> Optional[MarkerSpan]:
    events = marker_events(text, markers)
    if len(events) != 2 or events[0][0] != "begin" or events[1][0] != "end":
        return None
    return MarkerSpan(events[0][1], events[1][2])


def marker_error(path: Path, text: str, markers: MarkerStyle = MARKDOWN_MARKERS) -> Optional[str]:
    events = marker_events(text, markers)
    begin_count = sum(1 for kind, _, _ in events if kind == "begin")
    end_count = sum(1 for kind, _, _ in events if kind == "end")
    rel = str(path)
    if begin_count != end_count:
        return f"{rel} has mismatched generated block markers ({begin_count} begin, {end_count} end)"
    if begin_count > 1:
        return f"{rel} has multiple generated blocks; refusing ambiguous update"
    if begin_count == 1 and events[0][0] != "begin":
        return f"{rel} has generated block markers in the wrong order"
    return None


def markdown_without_code_fences(text: str) -> str:
    lines = []
    in_fence = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            lines.append(line)
    return "\n".join(lines)


def has_claude_agents_import(text: str) -> bool:
    visible = HTML_COMMENT_RE.sub("", markdown_without_code_fences(text))
    return any(line.strip() == "@AGENTS.md" for line in visible.splitlines())


def without_generated_block(text: str, markers: MarkerStyle = MARKDOWN_MARKERS) -> str:
    span = generated_block_span(text, markers)
    if span is None:
        return text
    return text[: span.begin_start] + text[span.end_end :]


def generated_block_from_content(text: str, markers: MarkerStyle = MARKDOWN_MARKERS) -> str:
    span = generated_block_span(text, markers)
    if span is None:
        raise AgentContextError("generated content has no valid generated block")
    block = text[span.begin_start : span.end_end]
    return block if block.endswith("\n") else block + "\n"


def replace_generated_block(
    current: str,
    generated_content: str,
    markers: MarkerStyle = MARKDOWN_MARKERS,
) -> str:
    span = generated_block_span(current, markers)
    if span is None:
        raise AgentContextError("current content has no valid generated block")
    replacement = generated_block_from_content(generated_content, markers).rstrip()
    suffix = current[span.end_end :]
    replacement += "\n"
    return current[: span.begin_start] + replacement + suffix


def append_generated_block(
    current: str,
    generated_content: str,
    markers: MarkerStyle = MARKDOWN_MARKERS,
) -> str:
    separator = "\n\n" if current.endswith("\n") else "\n\n"
    return current + separator + generated_block_from_content(generated_content, markers)


def generated_block_changed(
    root: Path,
    path: Path,
    current: str,
    markers: MarkerStyle = MARKDOWN_MARKERS,
) -> bool:
    head = git_head_text(root, path)
    if head is None:
        return False
    if marker_error(path, current, markers) or marker_error(path, head, markers):
        return False
    if generated_block_span(current, markers) is None or generated_block_span(head, markers) is None:
        return False
    return generated_block_from_content(current, markers) != generated_block_from_content(head, markers)


def is_generated_only(
    path: Path,
    text: str,
    heading: Optional[str],
    markers: MarkerStyle = MARKDOWN_MARKERS,
) -> bool:
    error = marker_error(path, text, markers)
    if error:
        return False
    if generated_block_span(text, markers) is None:
        return False
    outside = without_generated_block(text, markers).strip()
    return outside == (f"# {heading}" if heading else "")


def git_run(root: Path, args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(root), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def in_git_repo(root: Path) -> bool:
    return git_run(root, ["rev-parse", "--is-inside-work-tree"]).returncode == 0


def git_top(root: Path) -> Optional[Path]:
    result = git_run(root, ["rev-parse", "--show-toplevel"])
    if result.returncode != 0:
        return None
    return Path(result.stdout.strip()).resolve()


def git_rel(root: Path, path: Path) -> str:
    top = git_top(root)
    if top is None:
        return str(path.relative_to(root))
    return str(path.resolve().relative_to(top))


def git_tracked(root: Path, path: Path) -> bool:
    return git_run(root, ["ls-files", "--error-unmatch", "--", git_rel(root, path)]).returncode == 0


def git_clean(root: Path, path: Path) -> bool:
    result = git_run(root, ["status", "--porcelain", "--", git_rel(root, path)])
    return result.returncode == 0 and result.stdout.strip() == ""


def git_head_text(root: Path, path: Path) -> Optional[str]:
    result = git_run(root, ["show", f"HEAD:{git_rel(root, path)}"])
    if result.returncode != 0:
        return None
    return result.stdout


def only_generated_changed(
    root: Path,
    path: Path,
    current: str,
    markers: MarkerStyle = MARKDOWN_MARKERS,
) -> bool:
    head = git_head_text(root, path)
    if head is None:
        return False
    if marker_error(path, current, markers) or marker_error(path, head, markers):
        return False
    return without_generated_block(current, markers) == without_generated_block(head, markers)


def should_snapshot_generated_update(
    root: Path,
    path: Path,
    current: str,
    markers: MarkerStyle = MARKDOWN_MARKERS,
) -> bool:
    if not in_git_repo(root) or not git_tracked(root, path):
        return True
    return generated_block_changed(root, path, current, markers)


def merge_gemini_settings(current: Optional[str] = None) -> str:
    if current is None:
        data: dict[str, object] = {}
    else:
        loaded = json.loads(current)
        if not isinstance(loaded, dict):
            raise AgentContextError(".gemini/settings.json must contain a JSON object")
        data = dict(loaded)

    context_names = data.get("contextFileName")
    if isinstance(context_names, str):
        names = [context_names]
    elif isinstance(context_names, list):
        names = [item for item in context_names if isinstance(item, str)]
    else:
        names = []
    for expected in ("GEMINI.md", "AGENTS.md"):
        if expected not in names:
            names.append(expected)
    data["contextFileName"] = names

    file_filtering = data.get("fileFiltering")
    if not isinstance(file_filtering, dict):
        file_filtering = {}
    file_filtering.setdefault("respectGitIgnore", True)
    data["fileFiltering"] = file_filtering

    return json.dumps(data, indent=2) + "\n"


def classify_gemini_settings(root: Path, path: Path, options: ScaffoldOptions) -> PlannedWrite:
    if path.is_symlink():
        raise AgentContextError(f"{path} is a symlink; refusing to update scaffold target")
    if not path.exists():
        return PlannedWrite(path, merge_gemini_settings(), "created", False)
    if not path.is_file():
        raise AgentContextError(f"{path} is not a regular file; refusing to update scaffold target")
    current = path.read_text(encoding="utf-8")
    if options.force_recreate:
        content = merge_gemini_settings()
        return PlannedWrite(path, content, "force-recreated", True)
    try:
        content = merge_gemini_settings(current)
    except json.JSONDecodeError as error:
        raise AgentContextError(
            f".gemini/settings.json is not valid JSON ({error}); pass --force-recreate to replace it"
        ) from error
    if current == content:
        return PlannedWrite(path, content, "unchanged", False, False)
    return PlannedWrite(path, content, "updated-json-settings", True)


def classify_recreate(
    root: Path,
    path: Path,
    content: str,
    heading: Optional[str],
    options: ScaffoldOptions,
    markers: Optional[MarkerStyle] = MARKDOWN_MARKERS,
) -> PlannedWrite:
    if path.is_symlink():
        raise AgentContextError(f"{path} is a symlink; refusing to update scaffold target")
    if not path.exists():
        return PlannedWrite(path, content, "created", False)
    if not path.is_file():
        raise AgentContextError(f"{path} is not a regular file; refusing to update scaffold target")
    current = path.read_text(encoding="utf-8")
    if current == content:
        return PlannedWrite(path, content, "unchanged", False, False)
    if options.force_recreate:
        return PlannedWrite(path, content, "force-recreated", True)
    if markers is None:
        raise AgentContextError(
            f"{path} has no safe generated block marker; pass --force-recreate to replace it"
        )
    error = marker_error(path, current, markers)
    if error:
        raise AgentContextError(error)
    if generated_block_span(current, markers) is not None:
        updated = replace_generated_block(current, content, markers)
        if updated == current:
            return PlannedWrite(path, updated, "unchanged", False, False)
        snapshot = should_snapshot_generated_update(root, path, current, markers)
        return PlannedWrite(path, updated, "updated-generated-block", snapshot)
    if options.append_generated_block:
        if markers != MARKDOWN_MARKERS or path.suffix.lower() != ".md":
            raise AgentContextError(f"{path} cannot safely append a generated block; use --force-recreate")
        appended = append_generated_block(current, content, markers)
        return PlannedWrite(path, appended, "appended-generated-block", False)
    raise AgentContextError(
        f"{path} has no generated block marker; pass --append-generated-block to preserve it "
        "and add a managed block, or --force-recreate to replace it"
    )


def snapshot_before_recreate(root: Path, planned: list[PlannedWrite]) -> None:
    dirty = [item for item in planned if item.write and item.snapshot and item.path.exists()]
    if not dirty:
        return
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    snapshot_root = root / ".agents" / "snapshots" / "agent-context-maintainer" / stamp
    snapshot_root.mkdir(parents=True, exist_ok=True)
    manifest = []
    for item in dirty:
        rel = git_rel(root, item.path)
        safe_name = rel.replace("/", "__")
        manifest.append(f"{rel}: {item.action}")
        if in_git_repo(root) and git_tracked(root, item.path):
            diff = git_run(root, ["diff", "--", rel]).stdout
            staged = git_run(root, ["diff", "--cached", "--", rel]).stdout
            (snapshot_root / f"{safe_name}.diff").write_text(diff + staged, encoding="utf-8")
        else:
            (snapshot_root / f"{safe_name}.before").write_text(item.path.read_text(encoding="utf-8"), encoding="utf-8")
    (snapshot_root / "manifest.txt").write_text("\n".join(manifest) + "\n", encoding="utf-8")


def apply_planned_writes(root: Path, planned: list[PlannedWrite]) -> list[tuple[str, Path]]:
    snapshot_before_recreate(root, planned)
    changes: list[tuple[str, Path]] = []
    for item in planned:
        if not item.write:
            continue
        item.path.parent.mkdir(parents=True, exist_ok=True)
        item.path.write_text(item.content, encoding="utf-8")
        changes.append((item.action, item.path))
    return changes


def agents_body(inv: dict[str, object]) -> str:
    return """
    ## Agent Context Entry

    Always read these files before making repository changes:

    1. `.agents/core.md`
    2. `.agents/routing.md`
    3. The matching provider profile in `.agents/profiles/`; if unsure, read `.agents/profiles/generic.md`

    If `.agents/routing.md` routes the task to a skill, read that `SKILL.md` before editing.
    """


def claude_body(inv: dict[str, object]) -> str:
    return """
    @AGENTS.md

    ## Claude Code

    Use `AGENTS.md` as the shared source of truth for repository instructions. For Claude-specific behavior, also follow `.agents/profiles/claude.md` when present.
    """


def gemini_body(inv: dict[str, object]) -> str:
    return """
    ## Gemini CLI Bridge

    Use `AGENTS.md` as the shared source of truth for repository instructions. If Gemini CLI has not already loaded it, read it before editing.

    Also follow `.agents/profiles/gemini.md` for Gemini-specific behavior. Project settings in `.gemini/settings.json` may list both `GEMINI.md` and `AGENTS.md` as accepted context files.
    """


def copilot_instructions_body(inv: dict[str, object]) -> str:
    return """
    ## GitHub Copilot Bridge

    Use `AGENTS.md` as the shared source of truth for repository instructions. For GitHub Copilot-specific behavior, also follow `.agents/profiles/copilot.md` when present.

    Keep repository-wide Copilot guidance concise, durable, and not task-specific. Put path-specific or workflow-specific details in routed `.agents/skills/*/SKILL.md` files instead of duplicating them here.
    """


def gemini_settings_content() -> str:
    return merge_gemini_settings()


def provider_registry_body() -> str:
    lines = [
        "schema_version: 1",
        f'reviewed: "{PROVIDER_REGISTRY_REVIEWED}"',
        "providers:",
    ]
    for key, spec in PROVIDERS.items():
        bridge_files = ", ".join(f'"{item}"' for item in spec["bridge_files"])
        lines.append(f"  {key}:")
        lines.append(f'    profile: ".agents/profiles/{key}.md"')
        lines.append(f"    bridge_files: [{bridge_files}]")
        lines.append("    source_urls:")
        for url in spec["source_urls"]:
            lines.append(f'      - "{url}"')
    lines.extend(
        [
            "notes:",
            '  - "Provider bridge files should point back to AGENTS.md instead of duplicating shared policy."',
            '  - "When a provider changes its loading contract, update this registry, the bridge file, and the matching profile together."',
        ]
    )
    return "\n".join(lines)


def core_body(inv: dict[str, object]) -> str:
    languages = ", ".join(inv["languages"]) if inv["languages"] else "needs confirmation"
    return f"""
    ## Repository Snapshot

    - Detected languages: {languages}
    - Approximate tracked context files scanned: {inv["file_count"]}

    ## Detected Manifests

    {bullet_list(inv["manifests"], "No common manifest detected. Confirm project type manually.")}

    ## Detected Documentation

    {bullet_list(inv["docs"], "No root documentation detected. Create or identify the source of truth before broad edits.")}

    ## Context Boundaries

    - Keep shared rules in this file.
    - Keep provider-specific behavior in `.agents/profiles/`.
    - Keep task-specific procedures in `.agents/skills/*/SKILL.md`.
    - Do not copy secrets, credentials, raw logs, private keys, or `.env*` values into context files.

    ## Editing Rules

    - Preserve unrelated user changes.
    - Prefer small patches that follow existing repository style.
    - Update public-facing docs when private planning changes affect public behavior.

    ## Validation

    - Prefer focused validation for the changed slice.
    - Record exact commands run and any failures that appear unrelated.

    ## Handoff Notes

    - Leave durable restart notes when work spans multiple sessions.
    - Point future agents to the most current implementation or planning checkpoint.
    """


def routing_body(inv: dict[str, object]) -> str:
    return f"""
    ## Universal First Reads

    - `AGENTS.md`
    - `.agents/core.md`
    - Matching provider profile in `.agents/profiles/`

    ## Task Routes

    - Code review: inspect changed files first, then relevant tests and docs.
    - Implementation: inspect manifests, existing patterns, and nearest tests before editing.
    - Documentation: reconcile private planning docs with public docs when both exist.
    - Security or privacy: read security guidance before changing storage, logging, sync, or agent-context behavior.
    - Changing or adding custom subagent definitions: read the provider's native agents directory listed in your profile.
    - New repeated workflow: create or update `.agents/skills/<task>/SKILL.md`.

    ## Detected Tests

    {bullet_list(inv["tests"], "No obvious tests detected. Identify the narrowest available validation manually.")}

    ## Missing Context Rule

    If required context is absent, state the gap clearly, make the safest local assumption, and avoid broad rewrites.
    """


def profile_body(profile: str, active_agent: str) -> str:
    active = "yes" if profile == active_agent else "no"
    spec = PROVIDERS[profile]
    # See bullet_list() for why continuation lines carry the template indent.
    bullets = "\n    ".join(f"- {item}" for item in spec["profile_bullets"])
    title = spec["title"]
    return f"""
    ## {title} Profile

    - Active detected profile: {active}

    ## Behavior

    {bullets}
    """


def scaffold(root: Path, agent: str, options: Optional[ScaffoldOptions] = None) -> list[tuple[str, Path]]:
    options = options or ScaffoldOptions()
    inv = inventory(root)
    active = detect_agent()[0] if agent == "auto" else agent
    if active not in PROFILES:
        active = "generic"
    targets = [
        (
            root / "AGENTS.md",
            generated_file_content(dedent(agents_body(inv)), "Agent Instructions"),
            "Agent Instructions",
            MARKDOWN_MARKERS,
        ),
        (
            root / "CLAUDE.md",
            generated_file_content(dedent(claude_body(inv)), "Claude Code Instructions"),
            "Claude Code Instructions",
            MARKDOWN_MARKERS,
        ),
        (
            root / "GEMINI.md",
            generated_file_content(dedent(gemini_body(inv)), "Gemini CLI Instructions"),
            "Gemini CLI Instructions",
            MARKDOWN_MARKERS,
        ),
        (
            root / ".github" / "copilot-instructions.md",
            generated_file_content(dedent(copilot_instructions_body(inv)), "GitHub Copilot Instructions"),
            "GitHub Copilot Instructions",
            MARKDOWN_MARKERS,
        ),
        (
            root / ".agents" / "core.md",
            generated_file_content(dedent(core_body(inv)), "Core Agent Context"),
            "Core Agent Context",
            MARKDOWN_MARKERS,
        ),
        (
            root / ".agents" / "routing.md",
            generated_file_content(dedent(routing_body(inv)), "Agent Routing"),
            "Agent Routing",
            MARKDOWN_MARKERS,
        ),
        (
            root / ".agents" / "provider-registry.yaml",
            generated_file_content(dedent(provider_registry_body()), None, YAML_MARKERS),
            None,
            YAML_MARKERS,
        ),
    ]
    planned: list[PlannedWrite] = []
    for path, content, heading, markers in targets:
        planned.append(classify_recreate(root, path, content, heading, options, markers))
    planned.append(classify_gemini_settings(root, root / ".gemini" / "settings.json", options))
    for profile in PROFILES:
        path = root / ".agents" / "profiles" / f"{profile}.md"
        heading = f"{PROVIDERS[profile]['title']} Agent Profile"
        content = generated_file_content(dedent(profile_body(profile, active)), heading)
        planned.append(classify_recreate(root, path, content, heading, options, MARKDOWN_MARKERS))
    if options.dry_run:
        return [(f"would-{item.action}", item.path) for item in planned if item.write]
    changes = apply_planned_writes(root, planned)
    skills_dir = root / ".agents" / "skills"
    skills_dir.mkdir(parents=True, exist_ok=True)
    return changes


def check(root: Path) -> list[str]:
    errors: list[str] = []
    required = [
        root / "AGENTS.md",
        root / "CLAUDE.md",
        root / "GEMINI.md",
        root / ".github" / "copilot-instructions.md",
        root / ".agents" / "core.md",
        root / ".agents" / "routing.md",
        root / ".agents" / "provider-registry.yaml",
        root / ".gemini" / "settings.json",
    ]
    required.extend(root / ".agents" / "profiles" / f"{profile}.md" for profile in PROFILES)
    for path in required:
        if not path.exists():
            errors.append(f"missing: {path.relative_to(root)}")
    if (root / "AGENTS.md").exists():
        text = (root / "AGENTS.md").read_text(encoding="utf-8")
        for ref in (".agents/core.md", ".agents/routing.md", ".agents/profiles/"):
            if ref not in text:
                errors.append(f"AGENTS.md does not reference {ref}")
    if (root / "CLAUDE.md").exists():
        text = (root / "CLAUDE.md").read_text(encoding="utf-8")
        if not has_claude_agents_import(text):
            errors.append("CLAUDE.md does not import @AGENTS.md")
    if (root / "GEMINI.md").exists():
        text = (root / "GEMINI.md").read_text(encoding="utf-8")
        for ref in ("AGENTS.md", ".agents/profiles/gemini.md"):
            if ref not in text:
                errors.append(f"GEMINI.md does not reference {ref}")
    if (root / ".github" / "copilot-instructions.md").exists():
        text = (root / ".github" / "copilot-instructions.md").read_text(encoding="utf-8")
        for ref in ("AGENTS.md", ".agents/profiles/copilot.md"):
            if ref not in text:
                errors.append(f".github/copilot-instructions.md does not reference {ref}")
    settings_path = root / ".gemini" / "settings.json"
    if settings_path.exists():
        try:
            settings = json.loads(settings_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            errors.append(f".gemini/settings.json is not valid JSON: {error}")
        else:
            context_names = settings.get("contextFileName")
            if isinstance(context_names, str):
                context_names = [context_names]
            if not isinstance(context_names, list):
                errors.append(".gemini/settings.json must set contextFileName")
            else:
                for expected in ("GEMINI.md", "AGENTS.md"):
                    if expected not in context_names:
                        errors.append(f".gemini/settings.json contextFileName does not include {expected}")
    context_files = [
        (root / "AGENTS.md", MARKDOWN_MARKERS),
        (root / "CLAUDE.md", MARKDOWN_MARKERS),
        (root / "GEMINI.md", MARKDOWN_MARKERS),
        (root / ".github" / "copilot-instructions.md", MARKDOWN_MARKERS),
        (root / ".agents" / "core.md", MARKDOWN_MARKERS),
        (root / ".agents" / "routing.md", MARKDOWN_MARKERS),
        (root / ".agents" / "provider-registry.yaml", YAML_MARKERS),
        *((root / ".agents" / "profiles" / f"{profile}.md", MARKDOWN_MARKERS) for profile in PROFILES),
    ]
    for path, markers in context_files:
        if not path.exists() or not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        error = marker_error(path.relative_to(root), text, markers)
        if error:
            errors.append(error)
        for ref in sorted(set(AGENTS_REF_RE.findall(text))):
            if "*" in ref or "<" in ref or ">" in ref:
                continue
            target = root / ref
            if ref.endswith("/"):
                if not target.is_dir():
                    errors.append(f"{path.relative_to(root)} references missing directory: {ref}")
            elif not target.exists():
                errors.append(f"{path.relative_to(root)} references missing path: {ref}")
    errors.extend(check_skill_errors_only(root))
    errors.extend(check_skill_routes(root))
    return errors


def print_providers(json_output: bool = False) -> None:
    if json_output:
        payload = {
            key: {
                "profile": f".agents/profiles/{key}.md",
                "bridge_files": spec["bridge_files"],
                "detect_env": spec["detect_env"],
                "source_urls": spec["source_urls"],
            }
            for key, spec in PROVIDERS.items()
        }
        print(json.dumps(payload, indent=2))
        return
    for key, spec in PROVIDERS.items():
        detect = ", ".join(f"${var}" for var in spec["detect_env"]) or "manual only (--agent)"
        print(f"{key}:")
        print(f"  profile: .agents/profiles/{key}.md")
        print(f"  bridges: {', '.join(spec['bridge_files'])}")
        print(f"  auto-detect: {detect}")


def print_inventory(root: Path, json_output: bool = False, explain_skips: bool = False) -> None:
    inv = inventory(root, explain_skips=explain_skips)
    if json_output:
        print(json.dumps(inv, indent=2, sort_keys=True))
        return
    print(f"root: {inv['root_name']}")
    print(f"file_count: {inv['file_count']}")
    print("languages:")
    for item in inv["languages"]:
        print(f"  - {item}")
    print("manifests:")
    for item in inv["manifests"]:
        print(f"  - {item}")
    print("docs:")
    for item in inv["docs"]:
        print(f"  - {item}")
    print("tests:")
    for item in inv["tests"]:
        print(f"  - {item}")
    if explain_skips:
        print("skipped:")
        for item in inv.get("skipped", []):
            print(f"  - {item['path']}: {item['reason']}")


def print_skills_inventory(root: Path, json_output: bool = False) -> None:
    inv = skill_inventory(root)
    if json_output:
        print(json.dumps(skill_inventory_json(inv), indent=2, sort_keys=True))
        return
    print(f"{len(inv.skills)} skills found under .agents/skills")
    for skill in inv.skills:
        print(f"- {skill.name}: {skill.validity}, lifecycle={skill.lifecycle}, evals={skill.quality.eval_coverage}")
    warnings, errors = skill_inventory_diagnostics(inv)
    for warning in warnings:
        print(f"warning: {warning.path}: {warning.code}: {warning.message}")
    for error in errors:
        print(f"error: {error.path}: {error.code}: {error.message}")


def print_skills_check(root: Path) -> int:
    inv = skill_inventory(root)
    warnings, errors = skill_inventory_diagnostics(inv)
    for warning in warnings:
        print(f"warning: {warning.path}: {warning.code}: {warning.message}")
    for error in errors:
        print(f"error: {error.path}: {error.code}: {error.message}")
    if errors:
        return 1
    print("skills check passed")
    return 0


def print_skills_report(root: Path, reviewed_date: str = SKILL_REGISTRY_REVIEWED) -> None:
    print(render_skill_report(root, reviewed_date).rstrip())


def print_changes(root: Path, changes: List[Tuple[str, Path]]) -> None:
    if not changes:
        print("no changes")
        return
    for action, path in changes:
        print(f"{action}: {path.relative_to(root)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    providers_parser = subparsers.add_parser("providers", help="list supported providers and bridges")
    providers_parser.add_argument("--json", action="store_true", help="print providers as JSON")

    skills_parser = subparsers.add_parser("skills", help="inspect and maintain repository-local skills")
    skills_subparsers = skills_parser.add_subparsers(dest="skills_command", required=True)

    skills_inventory_parser = skills_subparsers.add_parser("inventory", help="list .agents/skills entries")
    skills_inventory_parser.add_argument("root", nargs="?", default=".")
    skills_inventory_parser.add_argument("--json", action="store_true", help="print skill inventory as JSON")

    skills_check_parser = skills_subparsers.add_parser("check", help="validate .agents/skills entries")
    skills_check_parser.add_argument("root", nargs="?", default=".")

    skills_report_parser = skills_subparsers.add_parser("report", help="print the deterministic skill health report")
    skills_report_parser.add_argument("root", nargs="?", default=".")
    skills_report_parser.add_argument("--reviewed-date", default=SKILL_REGISTRY_REVIEWED)

    skills_sync_parser = skills_subparsers.add_parser("sync", help="write the skill registry and health report")
    skills_sync_parser.add_argument("root", nargs="?", default=".")
    skills_sync_parser.add_argument("--dry-run", action="store_true", help="show planned writes without changing files")
    skills_sync_parser.add_argument("--force-recreate", action="store_true", help="replace unmarked registry/report files")
    skills_sync_parser.add_argument(
        "--append-generated-block",
        action="store_true",
        help="append a generated block to an existing unmarked Markdown report",
    )
    skills_sync_parser.add_argument("--reviewed-date", default=SKILL_REGISTRY_REVIEWED)

    skills_routes_parser = skills_subparsers.add_parser("routes", help="sync compact skill routes into .agents/routing.md")
    skills_routes_parser.add_argument("root", nargs="?", default=".")
    skills_routes_parser.add_argument("--dry-run", action="store_true", help="show planned writes without changing files")

    skills_eval_parser = skills_subparsers.add_parser("eval", help="plan skill eval workspaces or run explicit Codex evals")
    skills_eval_parser.add_argument("root", nargs="?", default=".")
    skills_eval_parser.add_argument("--skill")
    skills_eval_parser.add_argument("--plan", action="store_true", help="print eval workspace plan without creating files")
    skills_eval_parser.add_argument("--init-workspace", action="store_true", help="create an eval workspace skeleton")
    skills_eval_parser.add_argument("--runner", choices=("codex",), help="run an eval prompt with the named runner")
    skills_eval_parser.add_argument("--prompt-file", help="prompt file inside a skill workspace")
    skills_eval_parser.add_argument("--output-file", help="JSONL output path inside a skill workspace")
    skills_eval_parser.add_argument(
        "--sandbox",
        default="read-only",
        choices=("read-only", "workspace-write", "danger-full-access"),
        help="sandbox passed to codex exec",
    )
    skills_eval_parser.add_argument("--i-understand-danger", action="store_true")
    skills_eval_parser.add_argument("--full-auto", action="store_true", help="legacy alias for codex --full-auto")

    for name in ("inventory", "check", "scaffold"):
        sub = subparsers.add_parser(name)
        sub.add_argument("root", nargs="?", default=".")
        if name == "inventory":
            sub.add_argument("--json", action="store_true", help="print inventory as JSON")
            sub.add_argument("--explain-skips", action="store_true", help="include skipped paths and reasons")
        if name == "scaffold":
            sub.add_argument("--agent", default="auto", choices=("auto",) + PROFILES)
            sub.add_argument("--dry-run", action="store_true", help="show planned writes without changing files")
            sub.add_argument(
                "--force-recreate",
                action="store_true",
                help="replace existing scaffold targets even when they have no generated marker",
            )
            sub.add_argument(
                "--append-generated-block",
                action="store_true",
                help="append a generated block to existing unmarked Markdown targets",
            )

    args = parser.parse_args()
    if args.command == "providers":
        print_providers(json_output=args.json)
        return 0
    if args.command == "skills":
        root = Path(args.root).resolve()
        if not root.exists() or not root.is_dir():
            parser.error(f"root is not a directory: {root}")
        try:
            if args.skills_command == "inventory":
                print_skills_inventory(root, json_output=args.json)
                return 0
            if args.skills_command == "check":
                return print_skills_check(root)
            if args.skills_command == "report":
                print_skills_report(root, args.reviewed_date)
                return 0
            if args.skills_command == "sync":
                options = ScaffoldOptions(
                    dry_run=args.dry_run,
                    force_recreate=args.force_recreate,
                    append_generated_block=args.append_generated_block,
                )
                print_changes(root, skills_sync(root, options, args.reviewed_date))
                return 0
            if args.skills_command == "routes":
                options = ScaffoldOptions(dry_run=args.dry_run)
                print_changes(root, sync_skill_routes(root, options))
                return 0
            if args.skills_command == "eval":
                if args.plan or not (args.init_workspace or args.runner):
                    print(json.dumps(skills_eval_plan(root, args.skill), indent=2, sort_keys=True))
                    return 0
                if args.init_workspace:
                    if not args.skill:
                        raise AgentContextError("--init-workspace requires --skill")
                    print_changes(root, init_skill_workspace(root, args.skill))
                    return 0
                if args.runner == "codex":
                    if not args.prompt_file or not args.output_file:
                        raise AgentContextError("--runner codex requires --prompt-file and --output-file")
                    if args.full_auto:
                        print("warning: --full-auto is a legacy alias; prefer --sandbox workspace-write")
                    command = run_codex_eval(
                        Path(args.prompt_file).resolve(),
                        Path(args.output_file).resolve(),
                        args.sandbox,
                        args.i_understand_danger,
                        args.full_auto,
                        root,
                    )
                    print("ran: " + " ".join(command[:4]))
                    return 0
        except AgentContextError as error:
            print(f"refusing skills {args.skills_command}: {error}")
            return 1
    root = Path(args.root).resolve()
    if not root.exists() or not root.is_dir():
        parser.error(f"root is not a directory: {root}")

    if args.command == "inventory":
        print_inventory(root, json_output=args.json, explain_skips=args.explain_skips)
        return 0
    if args.command == "check":
        errors = check(root)
        if errors:
            for error in errors:
                print(error)
            return 1
        print("agent context check passed")
        return 0
    if args.command == "scaffold":
        agent = args.agent
        if agent == "auto":
            agent, source = detect_agent()
            if source is not None:
                print(f"detected: {agent} (from ${source})")
            else:
                print("detected: generic (no known agent environment variables; pass --agent to override)")
        try:
            options = ScaffoldOptions(
                dry_run=args.dry_run,
                force_recreate=args.force_recreate,
                append_generated_block=args.append_generated_block,
            )
            changes = scaffold(root, agent, options)
        except AgentContextError as error:
            print(f"refusing scaffold: {error}")
            return 1
        if not changes:
            print("no changes")
        for action, path in changes:
            print(f"{action}: {path.relative_to(root)}")
        if args.dry_run:
            return 0
        errors = check(root)
        if errors:
            for error in errors:
                print(error)
            return 1
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
