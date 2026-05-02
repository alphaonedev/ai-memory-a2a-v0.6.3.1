"""mkdocs-macros entry point for the A2A-gate site.

Reads ``releases/<version>/summary.json`` files from the repo root and exposes
the highest-semver release as the "current" one for the landing page. The
landing page is converted from inline-edited Markdown numbers to a single
``{{ render_current_release() }}`` macro call so that bumping a version no
longer requires touching ``docs/index.md``.

A2A summaries use ``cells[]`` (one entry per agent_group x tls_mode cell)
rather than ``phases[]``, but the macro accepts either shape so the same
template module can be used by both gates if desired.

Per-release summaries are validated against ``releases/schema.json`` by
``.github/workflows/release-summary-gate.yml`` on every ``v*`` tag push.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

_SEMVER_RE = re.compile(
    r"^v(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?$"
)


def _parse_semver(name: str) -> tuple[int, int, int, int, tuple[Any, ...]] | None:
    m = _SEMVER_RE.match(name)
    if not m:
        return None
    major, minor, patch, hotfix, pre = m.groups()
    hotfix_n = int(hotfix) if hotfix is not None else 0
    if pre is None:
        pre_key: tuple[Any, ...] = (1,)
    else:
        ids: list[Any] = []
        for ident in pre.split("."):
            if ident.isdigit():
                ids.append((0, int(ident)))
            else:
                ids.append((1, ident))
        pre_key = (0, tuple(ids))
    return (int(major), int(minor), int(patch), hotfix_n, pre_key)


def _discover_releases(root: Path) -> list[tuple[Path, dict[str, Any]]]:
    releases_dir = root / "releases"
    if not releases_dir.is_dir():
        return []
    found: list[tuple[tuple[int, int, int, int, tuple[Any, ...]], Path, dict[str, Any]]] = []
    for child in releases_dir.iterdir():
        if not child.is_dir():
            continue
        key = _parse_semver(child.name)
        if key is None:
            continue
        summary = child / "summary.json"
        if not summary.is_file():
            continue
        try:
            data = json.loads(summary.read_text())
        except json.JSONDecodeError:
            continue
        found.append((key, summary, data))
    found.sort(key=lambda triple: triple[0])
    return [(p, d) for _, p, d in found]


def _human_seconds(s: int | None) -> str:
    if s is None:
        return "—"
    if s < 60:
        return f"{s}s"
    minutes, sec = divmod(s, 60)
    if minutes < 60 and sec == 0:
        return f"{minutes}m"
    if minutes < 60:
        return f"{minutes}m{sec}s"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h{minutes}m"


def _render_cell_row(cell: dict[str, Any]) -> str:
    badge = "✅" if cell.get("pass") else "❌"
    name = cell.get("cell", "?")
    passc = cell.get("pass_count", 0)
    failc = cell.get("fail_count", 0)
    total = cell.get("scenario_total") or (passc + failc)
    wall = cell.get("wall_human") or _human_seconds(cell.get("wall_seconds"))
    notes = cell.get("notes", "")
    return f"| `{name}` | {badge} | {passc} / {total} | {wall} | {notes} |"


def _render_current_release(summary: dict[str, Any]) -> str:
    version = summary.get("version", "?")
    date = summary.get("date", "?")
    pass_count = summary.get("pass_count", 0)
    fail_count = summary.get("fail_count", 0)
    wall = summary.get("wall_human") or _human_seconds(summary.get("wall_seconds"))
    verdict = summary.get("verdict", "?").upper()
    headline = summary.get("headline") or (
        f"{version} — {pass_count}/{pass_count + fail_count} green — {wall} — {date}"
    )
    evidence = summary.get("evidence", {}) or {}
    release = summary.get("release", {}) or {}
    cells = summary.get("cells", []) or []
    closed = summary.get("scenarios_closed", []) or []

    admonition_kind = "success" if verdict == "PASS" else "danger"
    lines: list[str] = []
    lines.append(f'!!! {admonition_kind} "{headline}"')
    lines.append("")
    lines.append(
        f"    **Campaign `{summary.get('campaign_run_id', '?')}` returned "
        f"`overall_pass: {str(verdict == 'PASS').lower()}` on {date}.**"
    )
    if summary.get("ai_memory_commit"):
        lines.append(
            f"    Validated against ai-memory commit "
            f"`{summary['ai_memory_commit']}` "
            f"({summary.get('ai_memory_git_ref', '?')})."
        )
    lines.append("")

    if cells:
        lines.append("    | Cell | Verdict | Scenarios | Wall | Notes |")
        lines.append("    |---|---|---|---|---|")
        for c in cells:
            lines.append("    " + _render_cell_row(c))
        lines.append("")

    if closed:
        lines.append("    **Scenarios closed in this release:**")
        lines.append("")
        for sc in closed:
            sid = sc.get("id", "?")
            name = sc.get("name", "")
            prev = sc.get("previously", "")
            now = sc.get("now", "")
            lines.append(f"    - **{sid} ({name})** — was {prev}; now {now}.")
        lines.append("")

    links: list[str] = []
    if evidence.get("campaign_dir"):
        links.append(
            f"[**→ {version} evidence directory**]"
            f"(https://github.com/alphaonedev/ai-memory-ai2ai-gate/tree/main/{evidence['campaign_dir']})"
        )
    if evidence.get("offline_html"):
        links.append(
            f"[**→ {version} offline HTML**]({evidence['offline_html']})"
        )
    if evidence.get("test_hub_url"):
        links.append(f"[**→ test-hub release page**]({evidence['test_hub_url']})")
    if evidence.get("release_notes_url"):
        links.append(f"[**→ release notes**]({evidence['release_notes_url']})")
    if links:
        lines.append("    " + " &middot; ".join(links))
        lines.append("")

    if release.get("channels"):
        lines.append(
            "    Distribution channels: "
            + ", ".join(f"`{c}`" for c in release["channels"])
            + "."
        )
        lines.append("")

    return "\n".join(lines)


def _render_release_history(releases: list[tuple[Path, dict[str, Any]]]) -> str:
    if not releases:
        return ""
    rows = ["| Version | Date | Verdict | Pass / Fail | Wall | Evidence |", "|---|---|---|---|---|---|"]
    for _, data in reversed(releases):
        version = data.get("version", "?")
        date = data.get("date", "?")
        verdict = data.get("verdict", "?").upper()
        passc = data.get("pass_count", 0)
        failc = data.get("fail_count", 0)
        wall = data.get("wall_human") or _human_seconds(data.get("wall_seconds"))
        evidence = data.get("evidence", {}) or {}
        link = (
            f"[evidence]({evidence['offline_html']})"
            if evidence.get("offline_html")
            else "—"
        )
        rows.append(f"| {version} | {date} | {verdict} | {passc} / {failc} | {wall} | {link} |")
    return "\n".join(rows)


_RUN_DIR_RE = re.compile(r"^a2a-[a-z0-9]+-v[0-9.]+(?:-r[0-9]+)?$")


def _discover_phase4_runs(root: Path) -> list[tuple[Path, dict[str, Any]]]:
    """Return [(run_dir, phase4_data), ...] sorted newest-first.

    Sort key is ``generated_at_utc`` from ``phase4-analysis.json`` when
    present; runs without that field fall back to directory mtime.
    """
    runs_dir = root / "runs"
    if not runs_dir.is_dir():
        return []
    found: list[tuple[str, Path, dict[str, Any]]] = []
    for child in runs_dir.iterdir():
        if not child.is_dir():
            continue
        analysis = child / "phase4-analysis.json"
        if not analysis.is_file():
            continue
        try:
            data = json.loads(analysis.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        ts = str(data.get("generated_at_utc") or "")
        if not ts:
            try:
                ts = str(int(child.stat().st_mtime))
            except OSError:
                ts = "0"
        found.append((ts, child, data))
    # Newest-first
    found.sort(key=lambda t: t[0], reverse=True)
    return [(p, d) for _, p, d in found]


def _read_substrate_verdict(run_dir: Path) -> str:
    summary = run_dir / "a2a-summary.json"
    if not summary.is_file():
        return "—"
    try:
        data = json.loads(summary.read_text())
    except (json.JSONDecodeError, OSError):
        return "—"
    overall = data.get("overall_pass")
    if overall is True:
        return "PASS"
    if overall is False:
        return "FAIL"
    return "—"


def _scenario_ids(per_cell: dict[str, Any]) -> list[str]:
    seen: list[str] = []
    for key in per_cell.keys():
        sid = key.split("/", 1)[0]
        if sid and sid not in seen:
            seen.append(sid)
    seen.sort()
    return seen


_ARMS = ("cold", "isolated", "stubbed", "treatment")
_ARM_LABEL = {
    "cold": "Cold",
    "isolated": "Isolated",
    "stubbed": "Stubbed",
    "treatment": "T",
}


def _fmt_rate(value: Any) -> str:
    try:
        f = float(value)
    except (TypeError, ValueError):
        return "—"
    return f"{f:.2f}"


def _derive_nhi_verdict(data: dict[str, Any]) -> str:
    """Coarse NHI verdict per governance §11.

    PASS = at least one scenario shows positive treatment delta on
    grounding rate AND every cross-layer row is consistent.
    INCONCLUSIVE = no positive treatment effect surfaced (typical when
    Phase 3 didn't produce usable agent traffic).
    FAIL = a cross-layer row reads NO (substrate vs NHI disagreement).
    """
    table = data.get("cross_layer_consistency_table") or []
    has_no = any(str(row.get("consistent", "")).upper() == "NO" for row in table)
    if has_no:
        return "FAIL"
    effects = data.get("treatment_effects") or {}
    positive = False
    for sid, eff in effects.items():
        for arm_key in ("vs_cold", "vs_isolated", "vs_stubbed"):
            comp = (eff or {}).get(arm_key) or {}
            try:
                if float(comp.get("delta_grounding_rate", 0)) > 0.0:
                    positive = True
                    break
            except (TypeError, ValueError):
                continue
        if positive:
            break
    if positive:
        return "PASS"
    return "INCONCLUSIVE"


def _verdict_badge(verdict: str) -> str:
    if verdict == "PASS":
        return "✅ PASS"
    if verdict == "FAIL":
        return "❌ FAIL"
    if verdict == "INCONCLUSIVE":
        return "⚠️ INCONCLUSIVE"
    return verdict or "—"


def _render_latest_nhi_insights(root: Path) -> str:
    runs = _discover_phase4_runs(root)
    if not runs:
        return (
            '!!! warning "No NHI analysis published yet"\n\n'
            "    No `runs/<campaign>/phase4-analysis.json` was found in this\n"
            "    repo. Once Phase 4 runs land, this section auto-renders the\n"
            "    most recent campaign's findings, treatment effects, and\n"
            "    cross-layer consistency rows.\n"
        )
    run_dir, data = runs[0]
    run_id = run_dir.name
    generated = data.get("generated_at_utc", "?")
    release = data.get("release", "?")
    node_id = data.get("node_id", "?")
    nhi_verdict = _derive_nhi_verdict(data)

    lines: list[str] = []
    lines.append(f"**Run:** `{run_id}` &middot; **release:** `{release}` &middot; "
                 f"**node:** `{node_id}` &middot; **generated:** `{generated}`")
    lines.append("")
    lines.append(f"**Derived NHI verdict:** {_verdict_badge(nhi_verdict)} "
                 f"(per [governance §11](governance.md#11-what-success-looks-like))")
    lines.append("")

    # Treatment-effects table
    effects = data.get("treatment_effects") or {}
    if effects:
        lines.append("### Treatment effects (Δ grounding rate vs each control arm)")
        lines.append("")
        lines.append("| Scenario | T mean | Δ vs Cold | Δ vs Isolated | Δ vs Stubbed |")
        lines.append("|---|---|---|---|---|")
        for sid in sorted(effects.keys()):
            eff = effects[sid] or {}
            t_agg = eff.get("treatment_aggregate") or {}
            t_mean = _fmt_rate(t_agg.get("grounding_rate_mean"))
            d_cold = _fmt_rate(((eff.get("vs_cold") or {})).get("delta_grounding_rate"))
            d_iso = _fmt_rate(((eff.get("vs_isolated") or {})).get("delta_grounding_rate"))
            d_stub = _fmt_rate(((eff.get("vs_stubbed") or {})).get("delta_grounding_rate"))
            lines.append(f"| **{sid}** | {t_mean} | {d_cold} | {d_iso} | {d_stub} |")
        lines.append("")

    # Cross-layer consistency table
    table = data.get("cross_layer_consistency_table") or []
    if table:
        lines.append("### Cross-layer consistency table")
        lines.append("")
        lines.append("| Substrate finding | Substrate verdict | NHI correlate | NHI observation | Consistent |")
        lines.append("|---|---|---|---|---|")
        for row in table:
            sf = row.get("substrate_finding", "?")
            sv = row.get("substrate_verdict", "?")
            nc = row.get("nhi_correlate", "?")
            no = row.get("nhi_observation", "?")
            cons = str(row.get("consistent", "?")).upper()
            cons_cell = {"YES": "✅ YES", "NO": "❌ NO"}.get(cons, f"⚠️ {cons}")
            lines.append(f"| {sf} | {sv} | {nc} | {no} | {cons_cell} |")
        lines.append("")

    # Findings — pick top 2-3 by severity
    findings = data.get("findings") or []
    sev_rank = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}
    sorted_findings = sorted(
        findings,
        key=lambda f: sev_rank.get(str(f.get("severity", "")).lower(), 99),
    )
    top = sorted_findings[:3]
    if top:
        lines.append("### Top findings (highest severity first)")
        lines.append("")
        lines.append("| ID | Severity | Class | Summary |")
        lines.append("|---|---|---|---|")
        for f in top:
            fid = f.get("id", "?")
            sev = f.get("severity", "?")
            cls = f.get("class", "?")
            summary = str(f.get("summary", "")).replace("|", "\\|")
            lines.append(f"| `{fid}` | {sev} | `{cls}` | {summary} |")
        lines.append("")

    # Pointer to raw evidence
    lines.append(
        f"*Raw evidence:* "
        f"[`runs/{run_id}/phase4-analysis.json`]"
        f"(https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/main/runs/{run_id}/phase4-analysis.json)"
    )
    return "\n".join(lines)


def _render_nhi_per_run_matrix(root: Path) -> str:
    runs = _discover_phase4_runs(root)
    if not runs:
        return (
            '!!! info "No NHI per-run analysis yet"\n\n'
            "    No campaign run has produced a `phase4-analysis.json`\n"
            "    in `runs/`. Once Phase 4 lands, every run gets a row\n"
            "    here automatically.\n"
        )

    # Discover the union of scenario ids across all runs so the matrix
    # column set is stable across rows even if a given run has fewer
    # scenarios populated.
    all_sids: list[str] = []
    for _, data in runs:
        for sid in _scenario_ids(data.get("per_cell") or {}):
            if sid not in all_sids:
                all_sids.append(sid)
    all_sids.sort()

    lines: list[str] = []
    lines.append("## Per-run NHI verdict")
    lines.append("")

    # Header — Run | Substrate | NHI | per scenario "T mean / Δ Cold" cell | Top finding | XL
    header_cells = ["Run", "Substrate", "NHI"]
    for sid in all_sids:
        header_cells.append(f"{sid} (T grounding · ΔvsCold)")
    header_cells.extend(["Top finding", "Cross-layer (S24/D)"])
    lines.append("| " + " | ".join(header_cells) + " |")
    lines.append("|" + "|".join(["---"] * len(header_cells)) + "|")

    for run_dir, data in runs:
        run_id = run_dir.name
        substrate = _read_substrate_verdict(run_dir)
        substrate_cell = {
            "PASS": "✅ PASS",
            "FAIL": "❌ FAIL",
        }.get(substrate, substrate)
        nhi_cell = _verdict_badge(_derive_nhi_verdict(data))

        run_link = f"`{run_id}`"

        per_cell = data.get("per_cell") or {}
        effects = data.get("treatment_effects") or {}
        scenario_cells: list[str] = []
        for sid in all_sids:
            t = (per_cell.get(f"{sid}/treatment") or {})
            t_mean = _fmt_rate(t.get("grounding_rate_mean"))
            eff = effects.get(sid) or {}
            d_cold = _fmt_rate(((eff.get("vs_cold") or {})).get("delta_grounding_rate"))
            scenario_cells.append(f"{t_mean} · Δ{d_cold}")

        findings = data.get("findings") or []
        sev_rank = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}
        if findings:
            top = sorted(
                findings,
                key=lambda f: sev_rank.get(str(f.get("severity", "")).lower(), 99),
            )[0]
            top_cell = (
                f"`{top.get('id', '?')}` ({top.get('severity', '?')}, "
                f"`{top.get('class', '?')}`)"
            )
        else:
            top_cell = "—"

        xl_table = data.get("cross_layer_consistency_table") or []
        # Find the S24 / Scenario D row specifically.
        xl_cell = "—"
        for row in xl_table:
            if "S24" in str(row.get("substrate_finding", "")) or \
               str(row.get("nhi_correlate", "")).strip() == "Scenario D":
                cons = str(row.get("consistent", "?")).upper()
                xl_cell = {
                    "YES": "✅ YES",
                    "NO": "❌ NO",
                }.get(cons, f"⚠️ {cons}")
                break

        row_cells = [run_link, substrate_cell, nhi_cell] + scenario_cells + [top_cell, xl_cell]
        lines.append("| " + " | ".join(row_cells) + " |")

    lines.append("")
    lines.append(f"*Total runs with `phase4-analysis.json`:* **{len(runs)}**")
    return "\n".join(lines)


def define_env(env):  # noqa: D401 — mkdocs-macros entry point
    """Bind release helpers into the Jinja env used by mkdocs-macros."""
    repo_root = Path(env.project_dir)
    releases = _discover_releases(repo_root)
    current = releases[-1][1] if releases else {}

    env.variables["current_release"] = current
    env.variables["all_releases"] = [d for _, d in releases]

    @env.macro
    def render_current_release() -> str:
        if not current:
            return (
                '!!! warning "No release summary published yet"\n\n'
                "    No `releases/<version>/summary.json` was found in this repo.\n"
            )
        return _render_current_release(current)

    @env.macro
    def render_release_history() -> str:
        return _render_release_history(releases)

    @env.macro
    def current_release_field(field: str, default: str = "") -> str:
        return str(current.get(field, default))

    @env.macro
    def render_latest_nhi_insights() -> str:
        return _render_latest_nhi_insights(repo_root)

    @env.macro
    def render_nhi_per_run_matrix() -> str:
        return _render_nhi_per_run_matrix(repo_root)
