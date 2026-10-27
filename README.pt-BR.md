<h1 align="center"><img src="assets/logo.png" alt="maestri-session-restart-fix" width="200"><br>maestri-session-restart-fix</h1>

<p align="center"><strong>Cada aba do Maestri volta na sua própria sessão do Claude Code, toda vez que o Maestri reinicia.</strong></p>

<p align="center"><a href="README.md">Read in English</a></p>

## O problema

Você roda o Claude Code em várias abas do Maestri. O Maestri fecha (atualização, queda, reinício do PC ou só sair dele)
e reabre. Algumas abas voltam na sessão certa. A maioria volta como **sessão nova em branco**, e algumas voltam na
**sessão errada** ou dão `No conversation found`. Aí você caça id de sessão na mão, aba por aba.

Por que acontece (detalhes em [docs/how-it-works.md](docs/how-it-works.md)): o Maestri só retoma uma aba quando tem um
`claude --resume <id>` para ela. Ele pega essa linha lendo o texto que o Claude imprime ao sair, e só quando fecha
direito. Depois de uma queda ou atualização, ele usa o comando com que abriu a aba da última vez. Por isso falha
quando:

- a aba foi aberta com `claude` puro;
- o Maestri não fechou direito;
- a linha quebrou numa aba estreita e o id veio cortado (`910`, `b454cb40-`);
- a tela mostrava o id de outra sessão.

Medido numa máquina: depois de um reinício, 39 de 44 abas voltaram em branco. Com o fix, 41 de 41 voltaram na sessão
certa (as outras 3 nunca tiveram sessão).

## Começo rápido

**Deixe seu agente de IA fazer.** Abra o Claude Code (ou outro agente de código) e diga:

```text
Instale https://github.com/theohaiek/maestri-session-restart-fix no meu Maestri
```

O agente segue o [CLAUDE.md](CLAUDE.md). Ele faz duas perguntas (nível de esforço padrão e ultracode), roda as
checagens, instala, mapeia as sessões abertas agora e avisa quando reiniciar o Maestri.

**Ou à mão.** Windows (PowerShell):

```powershell
git clone https://github.com/theohaiek/maestri-session-restart-fix
cd maestri-session-restart-fix
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

macOS ou Linux:

```bash
git clone https://github.com/theohaiek/maestri-session-restart-fix
cd maestri-session-restart-fix
bash ./install.sh
```

Depois feche e abra o Maestri uma vez. Para ver o estado, rode `doctor.ps1` (Windows) ou `./doctor.sh` (macOS,
Linux).

## O que ele faz

| Peça | O que faz |
|---|---|
| Hook (`UserPromptSubmit` e `SessionStart`) | A cada prompt numa aba (e a cada resume, clear ou compact), grava "a aba X roda a sessão Y". Uma sessão em branco nunca sobrescreve a real, porque não recebeu prompt. |
| Lançador `claude` | Fica no perfil do PowerShell (ou no `~/.zshrc` e `~/.bashrc`) e só age dentro das abas do Maestri. Quando o Maestri digita `claude` ou um `claude --resume` quebrado, ele reabre a sessão da própria aba. |
| Mapa na instalação | Lê o `MAESTRI_TERMINAL_ID` dos processos do Claude abertos agora, então o primeiro reinício já funciona. |
| Fila | As abas abrem uma depois da outra (3 s + 4 s por GB de transcript), para 40 sessões grandes não estourarem a RAM juntas. |
| Padrão da sessão | Nível de esforço e ultracode opcionais para toda sessão que o fix abre. A flag que você digitar sempre vale mais. |

Como o lançador decide:

- **O id que o Maestri passa está cortado, em branco ou é de outra aba:** ele abre a sessão da aba.
- **O id é de uma sessão mais nova, com prompt, que nenhuma outra aba tem:** ele usa esse id.
- **Você digitou `claude --resume X`:** vale o X.
- **A sessão já está aberta em outro processo:** ele nunca a abre de novo, porque seriam dois processos escrevendo no mesmo transcript.
- **`-p`, `--continue`, `--help` e `--version`:** passam sem mudança.
- **Sessão nova numa aba:** `claude --new-session`.

## Incompatibilidades que ele resolve

| Situação | O que acontece |
|---|---|
| Política de execução `Restricted` ou `AllSigned` | O instalador para e explica. Com `-SetExecutionPolicy`, ele põe `RemoteSigned` só para o seu usuário. Se for política de grupo, ele manda falar com o administrador. |
| Arquivos baixados em ZIP (Mark of the Web) | Os scripts instalados são desbloqueados. |
| Pasta Documentos redirecionada para o OneDrive | O caminho do perfil vem do Windows. |
| PowerShell 7 em vez do Windows PowerShell | Os dois perfis são configurados. |
| Claude Code instalado pelo npm (`claude.cmd`, `node`) | Suportado nas checagens de processo e no lançador. |
| `CLAUDE_CONFIG_DIR` ou `MAESTRI_DATA_DIR` definidos | Respeitados. |
| `claude -p` iniciado de dentro de uma aba (scripts, agentes) | Não sobrescreve a sessão da aba. |
| Aba com cmd, fish ou nushell | O doctor avisa. Use PowerShell, zsh ou bash. |
| macOS sem python3 | O `settings.json` é editado com JavaScript for Automation. |
| Transcript apagado pela limpeza do Claude Code (30 dias) | A aba abre uma sessão nova, sem erro. |
| Hooks e configurações que já existem | São mantidos. O `settings.json` ganha backup antes de cada mudança. |

A lista completa está em [docs/troubleshooting.md](docs/troubleshooting.md).

## Requisitos

- Maestri com abas do Claude Code. Testado com Maestri 0.27 e Claude Code 2.1.311.
- Windows 10 ou 11 com Windows PowerShell 5.1 ou PowerShell 7.
- macOS ou Linux com bash 3.2 ou mais novo, e abas rodando zsh ou bash.

## Desinstalar

```powershell
powershell -NoProfile -File .\uninstall.ps1            # -RemoveData também apaga o mapa das abas
```

```bash
bash ./uninstall.sh                                    # --remove-data também apaga o mapa das abas
```

## Privacidade e segurança

- Tudo fica na sua máquina, sem nenhuma chamada de rede.
- O fix grava:
  - seus scripts e o mapa das abas;
  - duas entradas de hook no `settings.json` do Claude Code, com backup antes;
  - uma linha no perfil do shell.
- Ele lê o ambiente de outros processos só dos seus próprios processos do Claude, na instalação e no doctor, e só
  para pegar o `MAESTRI_TERMINAL_ID`. Veja [SECURITY.md](SECURITY.md).
- Ele nunca mexe nos arquivos do Maestri.

## Estado

Versão 1.0.0. O caminho do Windows foi usado num workspace real do Maestri com 44 abas. O caminho de macOS e Linux
roda a mesma lógica e é testado no CI em macOS e Ubuntu, mas ainda não rodou num Maestri de verdade num Mac. Relatos
são bem-vindos: abra uma issue com a saída do doctor.

## Licença

[MIT](LICENSE)
