# NowDock

Companion nativo para macOS que mostra a música tocando num painel "irmão" da Dock: mesma altura e mesma base, ocupando o espaço vazio à esquerda dela.

![Plataforma](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![Status](https://img.shields.io/badge/status-em%20desenvolvimento-yellow)

## O que é

O macOS não tem exibição prática da música tocando — só o botão na barra de menus. O NowDock resolve isso com um painel sempre visível ao lado da Dock, mostrando capa, título, artista, álbum ou playlist, barra de progresso com seek e botões de controle (shuffle, anterior, play/pause, próxima, repeat).

- **Nativo e leve:** Swift + AppKit, sem Electron, sem polling. Meta: 0% de CPU ocioso.
- **Players:** Spotify e Apple Music.
- **Respeita o fullscreen:** some quando um app entra em tela cheia e reaparece ao passar o mouse na área.

## Estado do projeto

🚧 Em desenvolvimento. Veja o [PLAN.md](PLAN.md) para o plano completo e o estado das fases.

## Contribuindo

Encontrou um bug ou tem uma ideia? Abra uma [issue](../../issues) — bugs, sugestões e ideias são bem-vindos de todos. Leia o [CONTRIBUTING.md](CONTRIBUTING.md) antes.

## Licença

O NowDock **não é open-source**. O código é público para transparência e colaboração via issues. Veja [LICENSE.md](LICENSE.md).
