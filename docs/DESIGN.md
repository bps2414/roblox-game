# Send Goblins — Design

> Ideia original: *Goblin Dungeon / Goblin Delve*. Nome de trabalho: **Send Goblins**.

Você é um empreiteiro de masmorra. Equipa goblins, escolhe a profundidade, aperta **SEND** e assiste.
Você não controla nada. O RNG é a masmorra. Manda 10, voltam 2. Ver um goblin abrir a porta
errada e ser achatado *é* o produto.

- Andares mais fundos = loot melhor = mais mortes.
- Goblins que sobrevivem ganham XP. A maioria não sobrevive.
- O loot sempre volta pra você (mesmo de goblin morto). Goblin morto não volta.
- Sobreviventes podem ser vendidos, reequipados ou mandados mais fundo.
- A câmera segue um goblin por vez; dá pra trocar entre eles como uma câmera de segurança.
- Se todos morrem, a expedição acaba; você fica com o que já foi saqueado.

Gênero: **dungeon crawler incremental / idle em 2D**.

## Arquitetura

O servidor **simula a expedição inteira na hora** (seed + RNG próprio, determinístico) e gera uma
**linha do tempo de eventos**. O cliente só reproduz essa linha do tempo com animação.

- Recompensas só são creditadas quando o tempo da linha do tempo acaba (validado no servidor) → sem trapaça.
- Idle/offline sai de graça: a expedição já está resolvida.
- A simulação é Luau puro (sem APIs do Roblox) → testável fora do Studio com [Lune](https://lune-org.github.io/docs).
- Balanceamento por Monte Carlo (milhares de expedições simuladas).

```
src/shared/Sim/        Luau puro, sem APIs do Roblox
  Rng.luau              PRNG determinístico (xorshift32)
  Config.luau           todos os números de balanceamento
  Items.luau            equipamentos
  Goblin.luau           criação, stats efetivos, XP/nível
  Rooms.luau            tipos de sala e resolução
  Expedition.luau       roda a expedição → resultado + eventos
  Narration.luau        texto de cada evento (legenda da "câmera")
src/server/             economia, roster, DataStore, RemoteEvents
src/client/             UI, câmera de segurança, reprodução 2D
tests/                  testes, transmissão em texto, Monte Carlo (Lune)
```

## Visual: 2D com sprites

Tudo em `ScreenGui`, sem modelos 3D (arte 2D/pixel art é muito mais fácil de produzir).

- Sprites em `ImageLabel` com `ResampleMode = Pixelated` (pixel art nítido).
- Animação por sprite sheet: `ImageRectOffset`/`ImageRectSize` trocando frames.
- Cada sala é uma "cena" lateral (estilo side-view): porta de entrada, conteúdo, 1–3 portas de saída.
- "Câmera de segurança": a tela principal mostra o feed de um goblin; miniaturas dos outros na lateral
  (com estado: vivo / morto / voltou). Q/E ou clique para trocar.
- Morte = animação curta + "efeito" (achatado, engolido, etc.) + lápide na miniatura.
- Imagens precisam ser enviadas ao Roblox (Asset Manager / Creator Hub) e referenciadas por `rbxassetid://`.
  Até ter arte, usamos retângulos coloridos/emoji como placeholder.

## Sistemas

### Goblin
| Stat | Efeito |
|---|---|
| HP | morre em 0 |
| Fome (comida) | gasta 1 por sala; em 0, perde HP a cada sala (morre de fome) |
| Percepção | chance de notar armadilha/mímico e de ler as pistas das portas |
| Sorte | multiplica o ouro encontrado |
| Ataque / Defesa | vêm do equipamento + nível |
| Nível / XP | sobe sobrevivendo; cada nível dá +HP, +Percepção, +Ataque |

**Traits** (1 aleatória por goblin): Ganancioso, Covarde, Burro, Parrudo, Guloso, Sortudo, Sorrateiro.
Elas mudam escolhas de porta e reações — é daí que saem as mortes engraçadas.

### Equipamento (3 slots)
Arma, Armadura, Utilitário (tocha, ração, amuleto da sorte...).

### Salas
| Sala | Efeito |
|---|---|
| Vazia | só gasta fome; às vezes o goblin se perde (gasta mais) |
| Tesouro | ouro (e às vezes um item) |
| Armadilha | teste de Percepção; falhou = dano (ou morte instantânea nos andares fundos) |
| Mímico | parece Tesouro; Percepção revela; senão mordida + luta |
| Monstro | combate simples por rodadas |
| Santuário | cura, comida ou bênção |

**Portas:** a cada passo o goblin vê 1–3 portas com uma *pista* (brilho, silêncio, cheiro, arranhões).
Pistas podem enganar; goblins perceptivos leem melhor. Ao fim do andar, o goblin volta com o loot.

### Economia / incremental
- Taverna: recrutar goblins aleatórios (preço escala).
- Vender sobreviventes (valor sobe com nível).
- Loja de equipamentos; desbloquear andares mais fundos.
- Upgrades permanentes (vagas no quartel, recrutas melhores).
- Fase 2: alugar goblins para grupos de aventureiros NPC (renda passiva).

### Progressão de andares
O andar N só desbloqueia quando um goblin **volta vivo** do andar N−1. Sem isso, mandar goblins
iniciais para o fundo vira exploit (eles morrem, mas o loot de andar fundo volta mesmo assim).

### Metas de balanceamento
- Andar 1: ~80% de sobrevivência com equipamento inicial.
- Andar "médio" (~5): ~20–30% ("manda 10, voltam 2").
- Andar 10+: só goblins de nível alto e bem equipados voltam.

### Resultado atual (M1, `lune run scripts/balance`)
| Equipamento | Andar 1 | Andar 3 | Andar 5 | Andar 8 |
|---|---|---|---|---|
| inicial (graveto, trapos) | 95% | 28% | 3% | 0% |
| básico (adaga, couro, tocha) | 100% | 60% | 12% | 0% |
| médio L5 | 100% | 95% | 63% | 8% |
| tardio L10 | 100% | 98% | 94% | 80% |

## Marcos

| # | Entrega | Studio? |
|---|---|---|
| M1 | Simulação em Luau + testes Lune + transmissão em texto + Monte Carlo | não |
| M2 | Server/client: RemoteEvents, roster, equipar, andar, SEND, resultado (UI simples) | só para jogar |
| M3 | Visual 2D: cenas das salas, sprites placeholder, câmera de segurança, efeitos de morte | sim, para ver |
| M4 | Persistência (DataStore), loop de economia completo, upgrades | sim |
| M5 | Polimento (sons, partículas), aluguel para grupos, progresso offline | sim |

Texto do jogo em inglês (público global do Roblox); código e docs podem ficar em português/inglês.
