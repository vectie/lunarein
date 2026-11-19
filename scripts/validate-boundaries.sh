#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if rg -n 'vectie/(lunaflux|lunanexa)' "$repo_root" --glob 'moon.pkg' --glob '*.mbt' --glob '!_build/**'; then
  echo 'LunaRein core imports a sibling MoonSuite product' >&2
  exit 1
fi

if rg -n -i '\b(python|pytorch|torch|ray|megatron|sglang)\b' "$repo_root" \
  --glob 'moon.pkg' --glob '*.mbt' --glob '!_build/**'; then
  echo 'LunaRein production source contains a forbidden backend/runtime dependency' >&2
  exit 1
fi

if rg -n '\bAny\b|Map\[String' "$repo_root" --glob '*.mbt' --glob '!_build/**'; then
  echo 'LunaRein core contains an untyped extension surface' >&2
  exit 1
fi

if rg -n 'vectie/lunarein/(algorithms|protocols|orchestrator|adapters)' \
  "$repo_root/contracts" --glob 'moon.pkg'; then
  echo 'A LunaRein contract package imports an upper architectural layer' >&2
  exit 1
fi

if [ -d "$repo_root/algorithms" ] && \
  rg -n 'vectie/lunarein/(protocols|orchestrator|adapters)' \
    "$repo_root/algorithms" --glob 'moon.pkg'; then
  echo 'A LunaRein algorithm package imports an execution layer' >&2
  exit 1
fi

if [ -d "$repo_root/protocols" ] && \
  rg -n 'vectie/lunarein/(algorithms|orchestrator|adapters)' \
    "$repo_root/protocols" --glob 'moon.pkg'; then
  echo 'A LunaRein protocol package imports orchestration or implementation' >&2
  exit 1
fi

if [ -d "$repo_root/operations" ] && \
  rg -n 'vectie/lunarein/adapters' "$repo_root/operations" --glob 'moon.pkg'; then
  echo 'A LunaRein operations package imports an implementation adapter' >&2
  exit 1
fi

rg --files "$repo_root" --glob '*.mbt' --glob '*.c' --glob '*.h' \
  --glob '!_build/**' | while IFS= read -r source_file; do
  line_count=$(wc -l < "$source_file")
  if [ "$line_count" -gt 800 ]; then
    echo "Source exceeds the 800-line architecture limit: $source_file" >&2
    exit 1
  fi
done

echo 'LunaRein dependency and debt boundaries: ok'
