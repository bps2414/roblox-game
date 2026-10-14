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

## Jogando no Studio

Dê **Play** no Studio. Você começa com 100 de ouro e 3 goblins:

1. **Quartel**: veja os goblins, clique nos slots de equipamento pra equipar, marque quem vai na expedição.
2. **Taverna**: contrate goblins novos. **Loja**: compre e venda equipamentos.
3. Escolha o andar e aperte **SEND**. Assista pelas câmeras (Q/E ou clique pra trocar).
4. Quando todos voltarem ou morrerem, **COLLECT** e veja o resultado.

Pra salvar o progresso no Studio, ative *Game Settings → Security → Enable Studio Access to API Services*
(sem isso o progresso fica só na memória e some ao parar o Play).

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
