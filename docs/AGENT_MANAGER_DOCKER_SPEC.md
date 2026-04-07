# Spec — `agent_manager.py` docker-aware per slug `researcher`

> GTD `db896a84` (Loomy → DBA, 2026-04-07).
> Owner implementazione: Loomy (il file vive in `00. LoomX Consulting/hub/agent_manager.py`).
> Owner spec: DBA (S011 cont., 2026-04-07).
> Architettura di riferimento: **Design C** (cfr. D-017 in `docs/DECISIONS.md`).

## 0. Background — perché Design C, non quello del GTD originale

Il GTD `db896a84` originariamente diceva: "iniettare `BW_CLIENTID/SECRET/PASSWORD` nel container, lì dentro fa `bw unlock` e `bw get item`". Funzionante, ma cattivo threat model:

- La master password (o le credenziali per ottenerla) finiscono nel container, in env, possibilmente in cmdline visibili a `ps`. Blast radius del container = intero vault.
- Il container deve trasportare `bw` CLI e tutta la sua logica di unlock.
- Multi-PC: ogni container in ogni PC ha le credenziali sue (o riusa le stesse, sparse).

**Design C** ribalta:

1. **Solo l'host parla con Bitwarden.** Il launcher (`agent_manager.py`) sull'host estrae dal vault **solo la password DB** del ruolo da invocare.
2. **Il container è cieco al vault.** Riceve un singolo env var `DB_PASSWORD`, scrive `.pgpass` in tmpfs, esegue `claude`. Niente `bw` dentro, niente master, niente API key.
3. **Master password mai su disco.** Quando il launcher ha bisogno di unlock, prompta interattivamente l'utente via `getpass()`. La master vive solo nella RAM del processo Python il tempo necessario per ottenere `BW_SESSION`, poi viene scartata.

Trade-off accettato: ogni invocazione di un agente containerizzato richiede prompt master (D-017 "Opt 1"). Niente cache di session su disco. Per uso normale (Doc invocato sporadicamente durante il giorno) è accettabile. Se diventa scomodo, in futuro si valuta una cache short-TTL fuori OneDrive.

## 1. Test di accettazione

### A) Happy path
```bash
python hub/agent_manager.py invoke researcher "ping di test"
```
Atteso:
1. Prompt: `Bitwarden master password: ` (input nascosto)
2. L'utente digita la master, premi Invio
3. Il launcher fa unlock vault, fetch `loomx/agents/doc_researcher`, lock vault, scarta la session
4. `docker run --rm -i loomx/doc-researcher:poc` parte con `DB_PASSWORD=<value>` come env
5. Container esegue il pre-flight governance (preambolo Loomy + slug research)
6. Doc risponde "ping di test" (claude execution)
7. Container exit, summary visibile a Loomy nel board come da prassi attuale

### B) Altri agenti invariati
```bash
python hub/agent_manager.py invoke dba "..."
```
Comportamento identico a oggi: host-direct, niente Docker, niente prompt master.

### C) Modalità interactive
```bash
python hub/agent_manager.py interactive researcher
```
Atteso: `docker run --rm -it ...` per sessione interattiva. Stesso prompt master all'avvio.

### D) Resistenza a credential leak
- `ps -ef | grep doc_researcher` durante l'esecuzione del container → **non deve mostrare** né master, né `DB_PASSWORD`, né `BW_*`. La password DB va passata SOLO via `-e DB_PASSWORD` (env), non via `--env DB_PASSWORD=<value>` espanso in argv.
- Il file `.bash_history` non contiene la master.
- Nessun log script logga master, session, o DB password.

## 2. Implementazione richiesta in `hub/agent_manager.py`

### 2.1 Dict AGENTS — flag runtime
Aggiungere a `researcher` (e in futuro agli altri agenti containerizzati):
```python
AGENTS = {
    ...,
    "researcher": {
        ...,
        "runtime": "docker",
        "docker": {
            "image": "loomx/doc-researcher:poc",
            "vault_item": "loomx/agents/doc_researcher",  # secure note Bitwarden
            "tmpfs_runtime": "/runtime",                    # tmpfs interno al container
            "bind_mount": ("hub/researcher", "/work"),      # host → container path
        },
    },
}
```

Tutti gli altri agenti restano senza chiave `runtime` o con `runtime: "host"`.

### 2.2 Dispatcher
Estendere `invoke()` / `interactive()` / `status()` (quelli che oggi lanciano `claude` direttamente):

```python
def invoke(slug, prompt, ...):
    agent = AGENTS[slug]
    runtime = agent.get("runtime", "host")
    if runtime == "docker":
        return _invoke_docker(agent, prompt)
    return _invoke_host(agent, prompt)  # codice attuale
```

### 2.3 `_invoke_docker(agent, prompt)`

Pseudo-codice:

```python
import getpass, subprocess, json

def _invoke_docker(agent, prompt):
    docker_cfg = agent["docker"]

    # 1) Prompt master, mai loggato, mai persistito
    master = getpass.getpass("Bitwarden master password: ")

    # 2) Unlock vault — usa env, NON argv
    env_unlock = {**os.environ, "BW_PASSWORD": master}
    res = subprocess.run(
        ["bw", "unlock", "--passwordenv", "BW_PASSWORD", "--raw"],
        env=env_unlock,
        capture_output=True, text=True, check=False,
    )
    del master  # immediate scrub
    env_unlock.pop("BW_PASSWORD", None)

    if res.returncode != 0 or not res.stdout.strip():
        raise RuntimeError("bw unlock failed (master sbagliata o vault non raggiungibile)")
    bw_session = res.stdout.strip()

    # 3) Fetch DB password (secure note, ultima riga del campo notes)
    item_json = subprocess.check_output(
        ["bw", "get", "item", docker_cfg["vault_item"], "--session", bw_session],
        text=True,
    )
    notes = json.loads(item_json)["notes"]
    db_password = notes.rsplit("\n", 1)[-1].strip()

    # 4) Lock immediato + scarto session
    subprocess.run(["bw", "lock"], env={**os.environ, "BW_SESSION": bw_session},
                   check=False, stdout=subprocess.DEVNULL)
    del bw_session

    # 5) Costruisci comando docker
    bind_src, bind_dst = docker_cfg["bind_mount"]
    abs_src = os.path.abspath(bind_src)
    cmd = [
        "docker", "run", "--rm", "-i",
        "--tmpfs", f"{docker_cfg['tmpfs_runtime']}:rw,noexec,nosuid,size=16m,mode=0700,uid=1000,gid=1000",
        "-v", f"{abs_src}:{bind_dst}",
        "-e", "DB_PASSWORD",  # NB: SOLO il nome, il valore arriva via env Python
        # Eventuali altre env non sensibili (preambolo governance, slug, ecc.)
        "-e", f"AGENT_SLUG={agent.get('db_role', 'doc_researcher')}",
        docker_cfg["image"],
        "claude",  # o quello che serve in base al modo (invoke/interactive)
    ]

    # 6) Lancio container con DB_PASSWORD nell'env del subprocess
    container_env = {**os.environ, "DB_PASSWORD": db_password}
    del db_password
    # Il prompt va passato come stdin oppure come arg dopo il preambolo governance
    proc = subprocess.run(cmd, env=container_env, input=build_preamble(agent) + prompt, text=True)
    return proc
```

**Note critiche:**

- **Mai** `-e DB_PASSWORD=<value>` esplicito nei `cmd`: solo `-e DB_PASSWORD` (variabile dal nome), il valore vive nell'env del subprocess Python e viene ereditato. Questo evita argv leak via `ps`.
- **Mai** loggare `master`, `bw_session`, `db_password` (no `print`, no `logging.debug`, no traceback con locals).
- **Mai** scrivere sti tre valori in file. L'unico file scritto è `.pgpass` dentro al container (in tmpfs, fuori dal disco host).
- `bw config server https://vault.bitwarden.eu` deve essere già stato eseguito una volta sull'host (D-014). Il launcher può anche chiamarlo idempotentemente all'inizio, ma fallisce con "Logout required" se già configurato — `|| true` o catch dell'errore.
- `bw login --apikey` simile: idempotente, fallisce con "You are already logged in" se già loggato — gestire come no-op.

### 2.4 Preambolo governance
Il preambolo che oggi viene prependeded al prompt (logica esistente) **deve essere passato dentro al container** stesso testo, stesso flusso. Suggerimento: passa via stdin come `preambolo + "\n\n" + prompt`. Non cambia per il comportamento attuale degli altri agenti.

### 2.5 Modalità `interactive`
Identica a `_invoke_docker` ma con `docker run --rm -it` invece di `--rm -i`, e senza `input=...` (la sessione resta interattiva, l'utente digita direttamente).

### 2.6 Output
stdout/stderr del container devono ritornare al chiamante esattamente come oggi. `subprocess.run` senza capture per modo interattivo, con capture per modo headless (se serve postprocessing).

## 3. Cosa NON fare

- ❌ Cache di `BW_SESSION` su disco. La master viene chiesta ogni volta. Decisione esplicita di Achille (Opt 1, D-017 §3).
- ❌ Riusare le credenziali Bitwarden dell'host attivo (es. leggere il data file di `bw` di un altro processo). Sempre fresh unlock.
- ❌ Caricare `BW_PASSWORD` da `env.local.txt` o file simile. La master non vive su disco. Mai.
- ❌ Caricare la master da una qualsiasi env var pre-esistente. Solo `getpass()` interattivo.
- ❌ Loggare nulla che contenga `master`, `session`, `db_password`, anche in error path / except.

## 4. Quello che rimane out of scope qui

- Estensione ad altri 9 agenti containerizzati (Fase 2 D-020) — refactoring del dispatcher dovrebbe già coprirli, ma il rollout dei ruoli DB e immagini è separato.
- Co-engagement N:N (`loomx_item_agents`, D-018) — la policy RLS attuale di `doc_researcher` resta su `owner='researcher' OR waiting_on='researcher'`.
- Audit log shipping S3 — separato.
- Cache TTL della master / session — esplicitamente fuori scope (D-017 Opt 1).

## 5. Output finale e ack

Quando il launcher è pronto e Test A/B/C/D passano sul tuo lato (Loomy):
1. Manda board message di tipo `done` al DBA referenziando questo doc, allegando i 4 risultati di test
2. Chiudi il GTD `db896a84` come `done`
3. Parte la settimana di POC vera (Doc dockerizzato in uso reale di Achille, D-019 step 7)

Per dubbi sulla parte container-side / SQL / vault: ping al DBA via board, type `question`.
