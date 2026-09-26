# LocalHarness: Multi-Agent Local Orchestration on an Edge Laptop

[![Python 3.12](https://img.shields.io/badge/Python-3.12+-blue.svg)](https://www.python.org/)
[![Model: Gemma 4 E4B QAT](https://img.shields.io/badge/Model-Gemma%204%20E4B%20QAT-orange.svg)](https://huggingface.co/google/gemma-4-E4B-it)
[![Runtime: llama.cpp](https://img.shields.io/badge/Inference-llama.cpp%20(16k%20ctx)-green.svg)](https://github.com/ggerganov/llama.cpp)
[![Hardware: 16GB AMD APU](https://img.shields.io/badge/Hardware-16GB%20RAM%20%7C%204GB%20iGPU-purple.svg)](https://www.amd.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A local, hierarchical multi-agent assistant configuration built on the open-source **LocalHarness** runtime and tailored for resource-constrained edge hardware.

This repository bundles:
1. **The LocalHarness Engine:** A lightweight agent layer providing YAML-configured agent definition, tool resolution, capability floor validation, and SQLite-backed memory for locally served LLMs.
2. **A 10-Specialist Agent Suite:** A pre-configured multi-agent setup tested and evaluated on a **16GB consumer laptop** (with 4GB of shared memory allocated to an integrated AMD Radeon 780M GPU) using **Google's Gemma 4 E4B QAT** running via `llama.cpp`.

---

## ⚙️ Core LocalHarness Capabilities

LocalHarness sits on top of local inference providers (such as `llama.cpp`, `vLLM`, or `Ollama`) and manages agent lifecycles, tool invocation, and memory storage. Its documented architectural features include:

- **Declarative YAML Agent Configurations:** Personas, whitelisted toolsets, operational budgets (`max_actions`, `max_duration_minutes`), and memory parameters are defined in YAML files (`~/.localharness/agents/<name>.yaml`), eliminating the need to write custom Python glue code for each role.
- **Configuration-Level Capability Floor:** Mitigates direct prompt-injection risks by enforcing a static separation of concerns at tool resolution. An agent holding untrusted web ingestion tools (`web_search`, `web_fetch`, `web_page_query`) cannot simultaneously be assigned host-dangerous execution tools (`bash_exec`, `write`, `edit`, `python_exec`).
- **Semantic Vector & Fact Storage:** Agents can persist key facts to an isolated SQLite database (`memory.db`). Embeddings are generated locally via `sentence-transformers` (configured to run `all-MiniLM-L6-v2` on CPU), supporting semantic similarity search (`memory_search`), fact lookup (`memory_get`), and write-time embeddings (`remember`).
- **Chunked Document Inspection:** Long documents and text files can be inspected sequentially using `load_document` and `chunk`, enabling agents to examine sections of files without overflowing small model context windows.
- **Deterministic Permission Gate:** Every tool call passes through an argument-evaluating permission gate with configurable deny patterns (e.g., blocking `sudo`, recursive `rm`, or modifications to sensitive configuration files) across `auto`, `guarded`, and `unattended` modes.
- **Flat Subagent Delegation:** Supports hierarchical coordination (`max_subagent_depth: 1`), allowing a parent agent to invoke a specialized subagent via the `agent` tool and receive a distilled summary of findings.

---

## 💡 Edge Constraints & Engineering Strategy

Running multi-agent systems on consumer laptops with tight VRAM budgets (4GB iGPU allocation) requires careful prompt and tool management, especially with ~4B parameter models like Gemma 4 E4B:

1. **Tool Minimization (`inherit: []`):** Handing a small local model a large catalog of 15+ tool schemas consumes significant context tokens and increases the rate of malformed arguments or hallucinated tool names. By configuring each agent with `inherit: []` and an explicit `add:` list of 3 to 7 tools, schemas stay compact and relevant.
2. **Lean 4-Tool Root Orchestrator:** The primary coordinator is assigned only `agent`, `remember`, `memory_search`, and `memory_get`. Because it lacks file, web, and shell tools, it is architecturally guided to delegate domain work rather than attempting to execute tasks itself.
3. **Memory Tiering:** General user preferences (learning style, preferred explanations) are stored in the orchestrator's root memory. Domain-specific progress and notes are routed to the relevant specialist (e.g., Java DSA weaknesses to `dsa-mentor`, architecture decisions to `project-manager`).
4. **Offloading Vector Operations to CPU:** Embedding generation runs locally on CPU using `sentence-transformers/all-MiniLM-L6-v2` (384-dimensional vectors), preserving GPU memory exclusively for `llama.cpp` inference.

---

## 🏛️ System Architecture

```mermaid
flowchart TD
    User(["User Request"]) --> Orch["Orchestrator<br/>4 tools: agent, remember, memory_*"]
    
    subgraph MemoryLayer ["Memory Architecture"]
        OrchMemory[("Root Memory<br/>General Preferences")]
        SpecialistMemory[("Domain Memory<br/>DSA, Project, Study")]
    end
    
    Orch -.->|Preferences| OrchMemory
    
    subgraph Specialists ["Specialized Domain Subagents (Whitelisted Tools)"]
        DSA["dsa-mentor<br/>Java DSA, LeetCode, Hints"]
        Web["web-researcher<br/>Deep Research, Fact Verification"]
        News["news-scout<br/>Daily AI & Tech Briefings"]
        Code["coding-engineer<br/>Refactoring, Edits, Testing"]
        Data["data-engineer<br/>SQL, ETL, Python Analytics"]
        Study["study-tutor<br/>Textbooks, Concept Mastery"]
        Career["career-agent<br/>Resumes, Skill Gap Analysis"]
        Doc["document-analyst<br/>PDF & Report Deep Dives"]
        PM["project-manager<br/>Milestones, Architecture, ADRs"]
        Sys["system-agent<br/>Fedora, Hardware & LLM Health"]
    end

    Orch -->|Delegates| DSA
    Orch -->|Delegates| Web
    Orch -->|Delegates| News
    Orch -->|Delegates| Code
    Orch -->|Delegates| Data
    Orch -->|Delegates| Study
    Orch -->|Delegates| Career
    Orch -->|Delegates| Doc
    Orch -->|Delegates| PM
    Orch -->|Delegates| Sys
    
    DSA -.-> SpecialistMemory
    PM -.-> SpecialistMemory
    Study -.-> SpecialistMemory

    Specialists -->|Distilled Findings| Synthesis["Synthesis & Response"]
    Synthesis --> User
```

---

## 🤖 Specialist Agent Catalog

| Agent | Config | Primary Role | Whitelisted Tools |
| :--- | :--- | :--- | :--- |
| **`orchestrator`** | [`orchestrator.yaml`](agents/orchestrator.yaml) | Primary coordinator. Evaluates requests, routes domain tasks to specialists, and stores general user preferences. | `agent`, `memory_search`, `memory_get`, `remember` **(Lean 4-tool root)** |
| **`dsa-mentor`** | [`dsa-mentor.yaml`](agents/dsa-mentor.yaml) | Java DSA interview tutor. Focuses on patterns and algorithmic analysis; tracks weak topics and solved problems in memory. | `read`, `glob`, `grep`, `python_exec`, `memory_search`, `memory_get`, `remember` |
| **`web-researcher`** | [`web-researcher.yaml`](agents/web-researcher.yaml) | Read-only web research. Retrieves up-to-date information, cross-checks sources, and returns cited summaries. | `web_search`, `web_fetch`, `web_page_query` |
| **`news-scout`** | [`news-scout.yaml`](agents/news-scout.yaml) | Technology and AI news tracker. Summarizes recent headlines and industry developments. | `web_search`, `web_fetch`, `web_page_query` |
| **`coding-engineer`** | [`coding-engineer.yaml`](agents/coding-engineer.yaml) | Software engineering agent. Analyzes codebase structure, applies localized edits, and executes tests. | `read`, `glob`, `grep`, `write`, `edit`, `bash_exec`, `python_exec` |
| **`data-engineer`** | [`data-engineer.yaml`](agents/data-engineer.yaml) | Data engineering specialist. Assists with SQL queries, ETL/ELT pipelines, schema design, and dataset analysis. | `read`, `glob`, `grep`, `write`, `edit`, `python_exec`, `bash_exec`, `load_document`, `chunk` |
| **`study-tutor`** | [`study-tutor.yaml`](agents/study-tutor.yaml) | Academic study partner. Explains concepts from uploaded notes and textbooks, providing progressive explanations. | `read`, `glob`, `grep`, `load_document`, `chunk`, `memory_search`, `memory_get`, `remember` |
| **`career-agent`** | [`career-agent.yaml`](agents/career-agent.yaml) | Tech career and internship researcher. Evaluates job listings against resume skillsets to identify learning gaps. | `web_search`, `web_fetch`, `web_page_query`, `read`, `glob`, `grep` |
| **`document-analyst`** | [`document-analyst.yaml`](agents/document-analyst.yaml) | Document extraction agent. Analyzes long technical documents and reports without host mutation capabilities. | `read`, `glob`, `grep`, `load_document`, `chunk` |
| **`project-manager`** | [`project-manager.yaml`](agents/project-manager.yaml) | Project coordinator. Tracks task status, TODO lists, and architectural decisions (ADRs) in persistent memory. | `read`, `glob`, `grep`, `write`, `edit`, `memory_search`, `memory_get`, `remember` |
| **`system-agent`** | [`system-agent.yaml`](agents/system-agent.yaml) | System inspector. Checks host diagnostic metrics (RAM, VRAM, thermals) and inspects `llama-server` process health. | `read`, `glob`, `grep`, `bash_exec` |

---

## 🔒 Security Architecture: The Capability Floor

LocalHarness enforces a structured capability floor designed to mitigate prompt-injection attacks:

```text
Untrusted Web Ingestion               Host-Dangerous Actions
(web_search, web_fetch, ...)          (bash_exec, write, edit, python_exec)
           \                                /
            \                              /
             X   CANNOT CO-RESIDE IN ONE  X
             X       AGENT TOOLSET        X
```

- **Enforcement Mechanism:** Before an agent loop starts, the tool registry checks that the agent's resolved toolset does not combine tools from `UNTRUSTED_INGEST` and `HOST_DANGEROUS`.
- **Workflow:** For tasks requiring external documentation to modify code, the orchestrator delegates to `web-researcher` first, receives a sanitized text summary, and then passes those findings to `coding-engineer` in a separate turn.
- *Caveat:* The capability floor operates at the tool resolution and dispatch layers of the harness. It provides architectural defense-in-depth, but does not replace operating system sandboxing (e.g., containers, firejail) when executing untrusted commands.

---

## 🚀 Getting Started

### Prerequisites
- **Operating System:** Linux (Fedora, Ubuntu, Debian, etc.) or macOS
- **Hardware:** 16GB RAM recommended (tested with 4GB allocated to integrated AMD Radeon 780M GPU)
- **Dependencies:** Python 3.12+, [`uv`](https://github.com/astral-sh/uv), and [`llama.cpp`](https://github.com/ggerganov/llama.cpp)
- **Model:** `gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf` (or any compatible GGUF served via `llama-server`)

### 1. Clone the Repository
```bash
git clone https://github.com/Chetan0246/localharness.git
cd localharness
```

### 2. Start the Inference Server
Run `llama-server` configured with Flash Attention and quantized KV caches:
```bash
# Using the helper script:
LLAMA_DIR="$HOME/llama.cpp" ./scripts/run_gemma.sh
```
Or start manually:
```bash
./build/bin/llama-server \
  -m models/gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf \
  -c 16384 \
  --jinja \
  -np 1 -ngl 99 -t 8 -tb 8 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --flash-attn on \
  --host 127.0.0.1 --port 8080
```

### 3. Synchronize Agent Configurations
Run the setup script to copy agent definitions to `~/.localharness/agents/`, configure CPU resonance embeddings, and run initial validation:
```bash
./scripts/setup_agents.sh
```

### 4. Start LocalHarness
```bash
uv run localharness start
```

---

## 🧪 Evaluation Test Sequence

The following sequence was used to verify routing and tool execution on Gemma 4 E4B:

### Test A: Root Memory & Recall
```text
❯ Remember that I prefer learning DSA through patterns rather than memorizing solutions.
◆ remember
✓ Remembered '...' (read-back verified)

❯ What do I prefer when learning DSA?
◆ memory_search
✓ Retrieves the recorded preference from local SQLite memory.
```

### Test B: Domain Delegation
```text
❯ Continue my Java DSA training.
◆ agent dsa-mentor
✓ Root orchestrator routes to dsa-mentor rather than generating an answer directly.
```

### Test C: Specialized Routing
```text
❯ Give me today's AI and technology news.
◆ agent news-scout
✓ Evaluates query and routes to news-scout instead of web-researcher.
```

### Test D: Security & Tool Confinement
```text
❯ Search for the latest version of package numpy and install it.
◆ agent web-researcher
✓ Root delegates research; no host execution tools exist at the root level.
```

### Test E: Compound Task Decomposition
```text
❯ Research current requirements for AI backend internships, inspect my current project stack, and identify my skill gaps.
```
*Observed flow:*
1. Orchestrator calls `agent(career-agent)` for current role requirements.
2. Orchestrator calls `agent(project-manager)` to inspect project structure.
3. Orchestrator synthesizes both outputs into a unified comparison.

---

## ⚠️ Known Limitations & Boundaries

- **Model Capacity:** Lightweight ~4B parameter models require unambiguous prompts. Ambiguous compound requests may occasionally require user clarification or manual task splitting.
- **Internet Requirement:** While local coding, DSA practice, memory recall, and file inspection run completely offline, web-based agents (`web-researcher`, `news-scout`, `career-agent`) require active network connectivity.
- **Host Action Confirmation:** In default `guarded` permission mode, commands that modify files or execute shell commands require explicit user approval before execution.

---

## 📂 Repository Layout

```text
localharness/
├── agents/                       # 10 Specialist YAMLs + Lean Orchestrator
│   ├── career-agent.yaml
│   ├── coding-engineer.yaml
│   ├── data-engineer.yaml
│   ├── document-analyst.yaml
│   ├── dsa-mentor.yaml
│   ├── news-scout.yaml
│   ├── orchestrator.yaml
│   ├── project-manager.yaml
│   ├── study-tutor.yaml
│   ├── system-agent.yaml
│   └── web-researcher.yaml
├── config/                       # Configuration Templates
│   ├── config.yaml               # Global harness configuration
│   └── overrides.yaml            # Machine-wide CPU embedding overrides
├── scripts/                      # Setup and Launcher Scripts
│   ├── run_gemma.sh              # llama-server launcher
│   └── setup_agents.sh           # Automated agent installation and validation
├── src/localharness/             # Core harness runtime engine
├── pyproject.toml                # Project metadata and dependencies
└── README.md
```

---

## 📄 License & Credits

- Core harness engine created by [@ahwurm](https://github.com/ahwurm/localharness).
- Agent configurations and edge setup by [Chetan Moorthy](https://github.com/Chetan0246).
- Inference powered by [llama.cpp](https://github.com/ggerganov/llama.cpp) and [Google DeepMind Gemma](https://huggingface.co/google/gemma-4-E4B-it).
- Licensed under the [MIT License](LICENSE).
