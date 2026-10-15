# Send Goblins — guia para o Claude

Jogo de Roblox 2D (incremental/idle dungeon crawler): o jogador equipa goblins, escolhe o andar, aperta
SEND e assiste pelas "câmeras de segurança" enquanto o RNG decide o destino deles.
Design completo e roadmap: `docs/DESIGN.md`. Leia antes de começar uma fase nova.

O dono do projeto fala português: responda em português. Texto dentro do jogo fica em inglês
(público global do Roblox).

## Ferramentas

Instaladas via [Rokit](https://github.com/rojo-rbx/rokit) a partir de `rokit.toml` (`rokit install`):
rojo, selene, stylua, wally, lune, luau-lsp.

```sh
rojo serve                                   # sincroniza com o Studio (plugin do Rojo → Connect)
rojo build default.project.json -o build/game.rbxl
lune run tests/sim.spec                      # testes da simulação
lune run tests/profile.spec                  # testes de economia/ações do jogador
lune run scripts/watch -- 3 6 1234           # expedição narrada no terminal (andar, goblins, seed)
lune run scripts/balance -- 2000             # Monte Carlo de balanceamento
scripts/check.sh                             # tudo: stylua, selene, testes, luau-lsp, emulador, build (bash/Git Bash)
```

Antes de dar commit: `scripts/check.sh` precisa passar. No Windows, rode pelo Git Bash.

## Arquitetura

```
src/shared/Sim/   Luau PURO (sem APIs do Roblox) → roda no Studio e no Lune
  Rng            PRNG determinístico (xorshift32). Nunca use math.random/Random na simulação.
  Config         todos os números de balanceamento
  Goblin, Items  dados e stats
  Rooms          resolução de cada tipo de sala → eventos
  Expedition     roda a expedição inteira na hora → resultado + timeline de eventos por goblin
  Narration      evento → legenda em texto
  Playback       estado das câmeras num instante t (usado pelo cliente)
  Profile        save do jogador + todas as ações (recruit, buy, equip, send, collect...), com validação
src/server/       init.server.luau: sessões, DataStore (Store.luau), seeds aleatórias, relógio, remote
src/client/       UI construída em código num canvas fixo 1280x720 escalado (Ui.luau = toolkit)
  App            troca de telas e estado de UI;  Screens/Base, Run, Results
tests/            specs do Lune
tools/emulator/   "Roblox falso" no Lune que roda cliente+servidor reais e renderiza a UI em PNG
```

Regras:
- **O servidor é a autoridade.** Ele simula a expedição com uma seed secreta e só paga depois que o tempo
  da timeline passou (`GetServerTimeNow`). O cliente só reproduz a timeline.
- Uma única `RemoteFunction`: `ReplicatedStorage.Remotes.Request(action, payload)` → sempre devolve o perfil.
  Ação nova = função em `Profile.luau` (pura, testada) + entrada em `handlers` no servidor.
- Dentro de `Sim/` use `require("./Modulo")` (funciona no Roblox e no Lune). Fora dele use
  `require(script.Parent.X)` / `require(ReplicatedStorage.Shared.Sim.X)`.
- Toda mudança de regra/balanceamento vem com teste em `tests/` e, se mexer nos números,
  rode `scripts/balance` e atualize a tabela em `docs/DESIGN.md`.
- Selene usa `roblox_lite.yml` (std local); a checagem de tipos de verdade é o luau-lsp.

## Testando no Roblox Studio

1. `rojo serve` → no Studio abra `build/game.rbxl` (ou um Baseplate) → Plugins → Rojo → Connect → Play.
2. Para salvar progresso no Studio: Game Settings → Security → Enable Studio Access to API Services.
3. Se o MCP do Roblox Studio estiver disponível nesta sessão, use-o para rodar playtests, ler o Output
   e tirar prints da tela em vez de pedir ao usuário.

## Status e próxima fase

- M1 ✅ simulação + testes + balanceamento. M2 ✅ loop jogável (UI em texto, save básico).
- **M3 (próxima): visual 2D em pixel art.** Trocar o feed de texto da tela `Run` por cenas:
  - sprites de pixel art desenhados com uma grade de `Frame`s (sem upload de imagens), num módulo
    `PixelSprite` que recebe matrizes de caracteres + paleta (como no mockup: goblin, mímico, baú, lápide,
    porta, tocha, monstros);
  - uma cena lateral por sala (parede de tijolos, chão, portas), o goblin andando entre salas com Tween,
    reações por evento (dano piscando vermelho, número de dano subindo, "SIGNAL LOST" + lápide na morte);
  - miniaturas das câmeras com o mesmo estilo; manter o feed de texto como legenda.
  - Mais tarde trocar por spritesheets enviadas ao Roblox (`ImageLabel` + `ResampleMode = Pixelated`).
- M4: DataStore robusto (session lock, UpdateAsync), upgrades permanentes. M5: polimento, aluguel de goblins.
