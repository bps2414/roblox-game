# roblox-game

Jogo para Roblox, desenvolvido com [Rojo](https://rojo.space) (código em arquivos `.luau`, sincronizado com o Studio).

## Estrutura

| Pasta          | Vai para no Roblox                          |
|----------------|---------------------------------------------|
| `src/server`   | `ServerScriptService.Server`                |
| `src/client`   | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared`   | `ReplicatedStorage.Shared`                  |
| `Packages`     | `ReplicatedStorage.Packages` (Wally)        |

## No seu PC

1. Instale o [Rokit](https://github.com/rojo-rbx/rokit) e rode `rokit install` (instala rojo, selene, stylua, wally, lune).
2. Instale o plugin do Rojo no Studio (`rojo plugin install`).
3. `rojo serve` e clique em **Connect** no plugin dentro do Studio.

## Checagens (rodam sem o Studio)

```sh
scripts/check.sh        # formatação, lint, tipos (luau-lsp) e build do .rbxl
scripts/check.sh --fix  # idem, mas corrige a formatação
```

Simulação (Luau puro, roda com [Lune](https://lune-org.github.io/docs)):

```sh
lune run tests/sim.spec              # testes
lune run scripts/watch -- 3 6 1234   # "transmissão" em texto: andar, nº de goblins, seed
lune run scripts/balance -- 2000     # Monte Carlo de balanceamento
```

O design do jogo está em [`docs/DESIGN.md`](docs/DESIGN.md).

O build gera `build/game.rbxl`, que pode ser aberto direto no Roblox Studio.
