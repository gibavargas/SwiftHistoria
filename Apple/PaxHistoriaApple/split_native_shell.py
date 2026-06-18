"""
split_native_shell.py — standalone extraction of NativeGameShell.swift into per-destination files.
Run from the project root after the source file has stabilized.
"""
from pathlib import Path
import re

base = Path("/Users/jvguidi/Ideia/pax-historia/Apple/PaxHistoriaApple")
shell_path = base / "NativeGameShell.swift"
lines = shell_path.read_text(encoding="utf-8").splitlines()

# --- step 1: parse top-level struct/enum boundaries ---
struct_blocks = {}
depth = 0
open_block = None

for i, line in enumerate(lines, start=1):
    m = re.match(r'\s*(?:private|internal|public|fileprivate\s+)?(struct|enum)\s+(\w+)', line)
    if m and open_block is None:
        open_block = (m.group(2), i)
        depth = line.count('{') - line.count('}')
        if depth <= 0:
            struct_blocks[open_block[0]] = (open_block[1], i)
            open_block = None
        continue
    if open_block:
        depth += line.count('{')
        depth -= line.count('}')
        if depth <= 0:
            struct_blocks[open_block[0]] = (open_block[1], i)
            open_block = None
            depth = 0

# --- step 2: group assignment ---
groups = {
    "NativeGameShellShared.swift": [
        "NativeGameTab", "NativeIntelSection", "NativeMacDestination", "ConsoleTab",
        "NativeCompactStatusBar", "NativeLatestIntelTicker", "NativeTurnProgressPanel",
        "NativeGameShell",
    ],
    "NativeMapComponents.swift": [
        "NativeMapScreen", "CommandConsoleDrawer", "BattleRow", "TroopRow", "EconomicRow",
        "NativeTimelineFooter", "NativeAdaptiveYearRail", "NativeMapHUD", "NativePostureIndicator",
        "NativeFloatingAdvanceButton", "NativeMapCommandBar", "NativeCommandButton",
        "NativeAdvanceMenu", "TurnTransitionOverlay",
    ],
    "NativeOverviewComponents.swift": [
        "NativeOverviewScreen", "NativePublicOpinionSparkline",
        "NativeHeroHeader", "NativeSectionHeader", "NativeMetricsGrid", "NativeStateNotices",
        "NativeSuggestedActionsPanel", "NativeQuickActionPicker",
    ],
    "NativeIntelComponents.swift": [
        "NativeIntelScreen", "NativeIntelSectionSelector", "NativeMacDetailScreen",
        "NativeDetailScroll", "NativeOrdersEditorPanel", "NativeAdvisorPanel",
        "NativeDiplomacyPanel", "NativeEventsPanel", "NativeLibraryPanel",
    ],
    "NativeOrdersComponents.swift": ["NativeOrdersScreen"],
    "NativeSettingsComponents.swift": [
        "NativeSettingsPanel", "NativeLanguagePicker", "NativeScenarioPicker",
        "NativeAIStatusPanel", "NativePanel", "NativeStatusChip",
    ],
}

inst_to_file = {name: fname for fname, items in groups.items() for name in items}

build_order = [
    "NativeGameShellShared.swift",
    "NativeGameShell.swift",
    "NativeMapComponents.swift",
    "NativeOverviewComponents.swift",
    "NativeIntelComponents.swift",
    "NativeOrdersComponents.swift",
    "NativeSettingsComponents.swift",
]

# --- step 3: allocate lines to files ---

def is_prose(t: str) -> bool:
    t = t.strip()
    return not t or t.startswith("//")

file_lines = {f: [] for f in build_order}
assigned = set()

# Assign struct blocks
for fname in build_order:
    for name in groups[fname]:
        if name not in struct_blocks:
            continue
        s, e = struct_blocks[name]
        for i in range(s, e + 1):
            file_lines[fname].append((i, lines[i - 1]))
            assigned.add(i)

# Assign all non-blank lines before first struct start (everything before line 3)
first_struct = min(s for s, _ in struct_blocks.values())
for i in range(1, first_struct):
    line = lines[i - 1]
    if not is_prose(line):
        file_lines["NativeGameShellShared.swift"].append((i, line))
        assigned.add(i)

# Fill remaining gaps by nearest struct mid-point
leftover = [i for i in range(1, len(lines) + 1) if i not in assigned and not is_prose(lines[i - 1])]
struct_mid = {name: (s + e) // 2 for name, (s, e) in struct_blocks.items()}
for line_num in sorted(leftover):
    best_name, _ = min(struct_mid.items(), key=lambda kv: abs(kv[1] - line_num))
    fname = inst_to_file.get(best_name, "NativeGameShellShared.swift")
    file_lines[fname].append((line_num, lines[line_num - 1]))

# --- step 4: write each file preserving order ---
for fname in build_order:
    pairs = sorted(file_lines[fname], key=lambda x: x[0])
    content = "\n".join(t for _, t in pairs)
    out = base / fname
    out.write_text(content + "\n", encoding="utf-8")
    line_count = len([ln for ln in pairs if not is_prose(ln[1])])
    print(f"• {fname}: {line_count} non-blank source lines ({len(content):,} bytes)")

# --- step 5: checkoffs ---
total_lines = len(lines)
total_covered = len(set(assigned) | {i for i, _ in file_lines["NativeGameShellShared.swift"] if i < first_struct})
leftover_lines = sorted(i for i in range(1, total_lines + 1) if i not in assigned and not is_prose(lines[i - 1]))
print(f"\nSource line total : {total_lines}")
print(f"Covered non-blank : {total_covered}")
print(f"Uncovered gaps    : {len(leftover_lines)}")
if leftover_lines:
    for ln in leftover_lines[:20]:
        print(f"  L{ln}: {lines[ln - 1][:88]!r}")
