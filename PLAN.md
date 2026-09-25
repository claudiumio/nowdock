# NowDock — plano de desenvolvimento

Companion nativo para macOS que mostra a música tocando num painel "irmão" da Dock, ocupando o espaço vazio à esquerda dela.

## 1. Objetivo e escopo

**O que é:** um painel sem borda, com a mesma altura e o mesmo alinhamento vertical da Dock, que começa perto da borda esquerda da tela (com uma folga, sem encostar) e termina antes da Dock (também com folga). Mostra:

- capa do álbum (quadrada, à esquerda, altura cheia menos padding);
- título da música, artista, álbum ou playlist;
- barra de progresso com tempo decorrido/total, clicável para seek;
- botões: shuffle, anterior, play/pause, próxima, repeat (off / all / one).

**Players suportados:**

| Fase | Player | Como |
|---|---|---|
| MVP | Spotify | Notificação distribuída `com.spotify.client.PlaybackStateChanged` + AppleScript (capa, shuffle, repeat, posição, comandos) |
| MVP | Apple Music | Notificação distribuída `com.apple.Music.playerInfo` + AppleScript (capa, playlist, shuffle, repeat, posição, comandos) |
| 6 | Qualquer outro (navegadores, VLC, IINA, Tidal, Deezer...) | MediaRemote via [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) — **exige aprovação** por ser dependência nova (ver §9) |

**Fora do escopo do MVP:** Dock na esquerda/direita da tela (o painel se esconde), letras, scrobbling, múltiplos painéis por monitor.

## 2. Princípios de consumo de recursos

Meta: **0,0 % de CPU ocioso**, **< 40 MB de memória residente**, "Impacto de energia: Baixo" no Monitor de Atividade.

- **Tudo por evento, nada de polling.** Players avisam por notificação distribuída; a geometria da Dock é recalculada só em eventos (mudança de tela, app aberto/fechado, preferência da Dock alterada), com debounce de 300 ms.
- **O relógio da barra de progresso só roda quando precisa:** tocando **e** painel visível. A posição é derivada de `posição + (agora − timestamp)` e o redesenho é a 1 Hz (`TimelineView(.periodic)`). Pausado ou oculto = zero timers.
- **Ressincronização leve de posição:** uma consulta AppleScript a cada 15 s, só enquanto toca e está visível (corrige seek feito dentro do player).
- **Nunca mandar AppleScript para um app fechado** (isso abriria o app). Sempre checar `NSRunningApplication` antes.
- **Capa:** decodificada e reduzida uma vez por faixa; só a capa atual fica em memória.
- **App agente** (`LSUIElement`): sem ícone na Dock, sem janela principal, sem ícone na barra de menus.
- AppKit para janela e sistema; SwiftUI só para o conteúdo do painel.

## 3. Stack e estrutura

- Swift 6.3, SwiftPM, **sem Xcode** (só Command Line Tools). Deployment target macOS 14. Liquid Glass (`NSGlassEffectView`) no macOS 26, `NSVisualEffectView` como fallback.
- Não-sandboxed (precisa de Acessibilidade e Apple Events para outros apps), hardened runtime.

```
nowdock/
├── Package.swift
├── AGENTS.md / PLAN.md
├── Resources/
│   ├── Info.plist              # LSUIElement, NSAppleEventsUsageDescription, bundle id dev.nowdock.NowDock
│   └── NowDock.entitlements    # com.apple.security.automation.apple-events
├── Scripts/
│   ├── build-app.sh            # swift build -c release → build/NowDock.app + codesign
│   └── run.sh                  # build-app + abre o app
├── Sources/
│   ├── NowDockCore/            # lógica pura, testável, sem AppKit
│   │   ├── Contracts.swift     # modelos compartilhados (congelado, ver §4)
│   │   ├── PlacementMath.swift
│   │   ├── NotificationParsing.swift
│   │   └── PlayerSelection.swift
│   └── NowDock/                # executável
│       ├── App/                # main.swift, AppDelegate, LaunchAtLogin
│       ├── NowPlaying/         # providers + NowPlayingCenter
│       ├── Window/             # DockGeometry, CompanionPanel, FullscreenMonitor, HoverReveal, CompanionWindowController
│       └── UI/                 # CompanionView e subviews
└── Tests/NowDockCoreTests/
```

## 4. Contratos entre módulos

`Sources/NowDockCore/Contracts.swift` é congelado: mudanças exigem atualizar todos os consumidores.

- `NowPlayingState` — snapshot: player, faixa, status, posição + timestamp, shuffle, repeat, capa (`Data` + `artworkID`), comandos suportados, permissões pendentes. `elapsed(at:)` calcula a posição atual.
- `PlayerCommand` — `togglePlayPause`, `next`, `previous`, `seek`, `setShuffle`, `setRepeat`.
- `PlacementInput` / `PlacementResult` / `PanelLayout` / `EdgeGapPreset` — cálculo de posição.

Tipos do executável que atravessam camadas (nomes fixos):

- `@MainActor final class NowPlayingCenter: ObservableObject` — `@Published private(set) var state: NowPlayingState`, `start()`, `perform(_:)`, `openPlayer(_:)`, `installedPlayers: [PlayerID]`, `isProgressActive: Bool` (a janela seta conforme visibilidade).
- `@MainActor final class CompanionWindowController: ObservableObject` — `init()`, `setContentView(_ view: NSView)`, `start()`, `requestAccessibilityPermission()`, `@Published private(set) var layout: PanelLayout`, `isUnavailable`, `isPanelVisible`, `usesDockFallback`, `edgeGapPreset: EdgeGapPreset` (persistido), `onVisibilityChange: ((Bool) -> Void)?`.
- `struct CompanionView: View` — `init(center: NowPlayingCenter, window: CompanionWindowController)`.

## 5. Camada Now Playing

### 5.1 Spotify (`SpotifyProvider`)
- Assina `com.spotify.client.PlaybackStateChanged` no `DistributedNotificationCenter`. `userInfo`: `Name`, `Artist`, `Album`, `Track ID`, `Duration` (ms), `Playback Position` (s), `Player State` (`Playing`/`Paused`/`Stopped`).
- AppleScript pré-compilado para: `artwork url of current track` (baixa com `URLSession`, cache pela URL), `shuffling`, `repeating`, `player position`.
- Comandos: `playpause`, `next track`, `previous track`, `set player position`, `set shuffling`, `set repeating`.
- Repeat via AppleScript do Spotify é só on/off → `.all` ↔ `true`; `.one` não é suportado (o botão alterna off/all).
- Playlist não é exposta pelo AppleScript do Spotify → mostra álbum.

### 5.2 Apple Music (`AppleMusicProvider`)
- Assina `com.apple.Music.playerInfo`. `userInfo`: `Name`, `Artist`, `Album`, `Total Time` (ms), `Player State`, `PersistentID`.
- AppleScript: `raw data of artwork 1 of current track`, `name of current playlist`, `shuffle enabled`, `song repeat` (`off`/`one`/`all`), `player position`.
- Comandos: `playpause`, `next track`, `previous track`, `set player position`, `set shuffle enabled`, `set song repeat`.
- Linha secundária: `Artista — Playlist` quando há playlist (que não seja a biblioteca), senão `Artista — Álbum`.

### 5.3 Execução de AppleScript
- Fila serial própria (utility), nunca na main thread. Scripts compilados uma vez.
- Erro `-1743` (sem permissão de Automação) → `PermissionIssue.automation(player)`; a UI oferece abrir `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`.

### 5.4 Seleção do player (`PlayerSelection`, puro)
1. O player que passou para `playing` mais recentemente vence.
2. Se o ativo pausa, continua sendo exibido.
3. Se o ativo fecha, cai para outro player aberto com faixa; senão, estado vazio.
4. Estado vazio: "Nada tocando" + botões para abrir Spotify / Música (só os instalados).
- Observa `NSWorkspace.didLaunchApplication`/`didTerminateApplication` para `com.spotify.client` e `com.apple.Music`.

## 6. Janela, posição e fullscreen

### 6.1 Painel (`CompanionPanel: NSPanel`)
- `[.borderless, .nonactivatingPanel]`, fundo transparente, sombra, `isMovable = false`, `hidesOnDeactivate = false`, não vira key/main.
- Nível `CGWindowLevelForKey(.dockWindow)` — o mesmo da Dock.
- `collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]` — a visibilidade em fullscreen é controlada por nós (§6.4).
- Hosting view com `acceptsFirstMouse = true` (clique funciona sem ativar o app).
- Cantos arredondados no estilo da Dock (raio ≈ 0,3 × altura), material glass/vibrancy.

### 6.2 Geometria da Dock (`DockGeometry`)
- **Fonte principal:** Accessibility API. `AXUIElementCreateApplication(pid da Dock)` → filho `AXList` → `AXPosition` + `AXSize`, convertendo de coordenadas top-left (Quartz) para bottom-left (AppKit).
- Pede permissão uma vez com `AXIsProcessTrustedWithOptions(prompt: true)`; se negada, usa o fallback e mostra aviso no menu de contexto.
- **Fallback:** altura = `visibleFrame.minY − frame.minY` da tela principal; largura estimada por `com.apple.dock` (`tilesize`, número de `persistent-apps` + `persistent-others` + recentes); a borda esquerda da Dock é `centro − largura/2`.
- **Orientação:** `orientation` em `com.apple.dock`. Se não for `bottom`, `isUnavailable = true` e o painel some.
- **Recalcular em:** `didChangeScreenParametersNotification`, `NSWorkspace.didLaunch/didTerminateApplication`, distribuída `com.apple.dock.prefchanged`, `activeSpaceDidChangeNotification`. Debounce 300 ms. Opcional: `AXObserver` com `kAXResizedNotification`.

### 6.3 Cálculo do frame (`PlacementMath`, puro e testado)

```
x      = screen.minX + edgeGap
y      = dock.minY
height = dock.height
width  = min(maxWidth, dock.minX − edgeGap − x)
se width < minWidth → .hidden
```

Layout por largura: **completo** (≥ 420 pt: todos os botões + tempos), **compacto** (300–420: sem shuffle/repeat e sem tempos), **mínimo** (220–300: capa + título + play/pause).

### 6.4 Fullscreen e auto-hide
- **Detecção:** em `activeSpaceDidChange` e `didActivateApplication`, `CGWindowListCopyWindowInfo(.optionOnScreenOnly, .excludeDesktopElements)` → janela de layer 0, de outro processo, com bounds iguais ao frame da tela da Dock. Não precisa de Gravação de Tela.
- **Em fullscreen:** o painel some com fade (0,2 s). `NSEvent.addGlobalMonitorForEvents(.mouseMoved)` fica instalado **só enquanto em fullscreen**. Mouse na área do painel por 150 ms → aparece; fora por 700 ms → some.
- **Saiu do fullscreen:** remove o monitor e mostra o painel.
- **Dock com auto-hide:** mesmo comportamento, para acompanhar a Dock.
- Nada de janela invisível como "hot zone": ela bloquearia cliques do app em fullscreen.

## 7. Interface

- Altura típica da Dock: 55–80 pt. Tudo proporcional à altura.
- Esquerda: capa (placeholder com ícone de nota).
- Centro: título (semibold, 1 linha), `Artista — Álbum/Playlist`, barra de progresso fina com tempos (layout completo). Clicar/arrastar faz seek.
- Direita: shuffle, anterior, play/pause (maior), próxima, repeat (`repeat.1` quando `.one`). Desativados quando não suportados.
- Clique na capa/título → ativa o player.
- **Menu de contexto:** player atual, abrir Spotify/Música, permissões pendentes, "Abrir ao iniciar sessão" (`SMAppService.mainApp`), folga da borda, "Sair do NowDock".
- Crossfade da capa na troca de faixa. Respeitar "Reduzir movimento" e claro/escuro.

## 8. Build, assinatura e permissões

- `Scripts/build-app.sh`: `swift build -c release`, monta `build/NowDock.app`, assina com hardened runtime + entitlements.
- Assinatura: `NOWDOCK_SIGN_IDENTITY` se definido (recomendado: certificado autoassinado "NowDock Dev" no Acesso às Chaves); senão ad-hoc. **Com ad-hoc, o macOS pode pedir de novo Acessibilidade/Automação a cada rebuild.**
- Permissões: Acessibilidade (medir a Dock), Automação para Spotify e Música.
- Distribuição futura: Developer ID + notarização + DMG (precisa de conta Apple Developer).

## 9. Fases

1. **Fundação** — Package, contratos, build, painel na posição certa.
2. **Now Playing Spotify + Música** — providers, seleção, comandos. ✅ troca de faixa reflete em < 300 ms.
3. **UI completa** — três layouts, glass, menu de contexto, estado vazio, avisos de permissão.
4. **Fullscreen e auto-hide.**
5. **Polimento e medição** — login item, multi-monitor, medir CPU/memória.
6. **Players genéricos (precisa de aprovação)** — MediaRemote foi restrito no macOS 15.4+; o caminho viável é o `mediaremote-adapter` (BSD-3), helper rodando via `/usr/bin/perl`. Entra como `SystemNowPlayingProvider` no mesmo contrato.

## 10. Verificação

- `swift build` e `Scripts/test.sh` (`PlacementMath`, `NotificationParsing`, `PlayerSelection`, `elapsed`).
- Checklist manual:
  - [ ] Painel começa na folga esquerda, termina antes da Dock, mesma altura e base.
  - [ ] Adicionar/remover app da Dock reposiciona o painel.
  - [ ] Spotify: título, artista, álbum, capa, progresso, 5 botões.
  - [ ] Música: idem + playlist + repeat one.
  - [ ] Fullscreen: some; mouse na área → aparece; sai → some; sai do fullscreen → volta.
  - [ ] Dock com auto-hide: igual.
  - [ ] Pausado: 0,0 % CPU em `top -pid <pid>` por 60 s.
  - [ ] Memória residente < 40 MB.
