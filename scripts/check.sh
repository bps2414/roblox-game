#!/usr/bin/env bash
# Formata, faz lint, checa tipos e builda o place. Uso: scripts/check.sh [--fix]
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--fix" ]]; then
	stylua src tests scripts
else
	stylua --check src tests scripts
fi

selene src

for spec in tests/*.spec.luau; do
	lune run "${spec%.luau}"
done

# Tipos do Roblox para o luau-lsp (baixados uma vez)
if [[ ! -f globalTypes.d.luau ]]; then
	curl -fsSL -o globalTypes.d.luau \
		https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json \
	--definitions=globalTypes.d.luau src

mkdir -p build
rojo build default.project.json -o build/game.rbxl
echo "OK: build/game.rbxl"
