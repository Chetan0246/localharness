# LocalHarness: 10-Agent Autonomous System on an Edge Laptop

[![Python 3.12](https://img.shields.io/badge/Python-3.12+-blue.svg)](https://www.python.org/)
[![Model: Gemma 4 E4B QAT](https://img.shields.io/badge/Model-Gemma%204%20E4B%20QAT-orange.svg)](https://huggingface.co/google/gemma-4-E4B-it)
[![Runtime: llama.cpp](https://img.shields.io/badge/Inference-llama.cpp%20(16k%20ctx)-green.svg)](https://github.com/ggerganov/llama.cpp)
[![Hardware: 16GB AMD APU](https://img.shields.io/badge/Hardware-16GB%20RAM%20%7C%204GB%20iGPU-purple.svg)](https://www.amd.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An offline, fully private, hierarchical multi-agent assistant suite engineered to run entirely on a modest **16GB consumer laptop** (with 4GB of shared RAM allocated as VRAM to an integrated AMD Radeon 780M GPU).

Zero cloud dependencies. Zero API costs. 100% local inference.

---

## 💡 The Engineering Challenge

Most modern multi-agent systems rely on multi-billion parameter frontier models hosted on cloud APIs (Claude 3.5 Sonnet, GPT-4o) or require workstation setups with dual RTX 4090s. 

Running 10 autonomous agents on an edge machine with only **4GB of VRAM** presents unique challenges:
1. **Context Bloat:** Small models (like Gemma 4 E4B) rapidly degrade in reasoning capability when handed bloated tool sets (15+ function schemas in context).
2. **Execution Looping:** Small models without clear tool boundaries try to improvise—often inventing imaginary files or repeating failed tool calls until stuck.
3. **Security Risks:** Exposing untrusted web ingestion (`web_search`, `web_fetch`) to the same agent context holding host-level tools (`bash_exec`, `write`) opens prompt-injection vulnerabilities.

### The Solution: Constrained Hierarchical Design
By leveraging strict software engineering principles:
- **Root Orchestrator is restricted to 4 tools only** (`agent`, `remember`, `memory_search`, `memory_get`). It cannot touch files, run bash commands, or browse the web. Its sole responsibility is task decomposition, routing, and response synthesis.
- **Whitelisted Tool Profiles (`inherit: []`)**: Every specialist receives only 3 to 7 explicit tools, minimizing token overhead and eliminating hallucinated verbs.
- **Enforced Capability Floor**: Structural quarantine between untrusted web content and host-acting tools.
- **CPU-Powered Vector Memory**: Semantic memory retrieval using local `sentence-transformers/all-MiniLM-L6-v2` running on CPU in milliseconds, leaving GPU VRAM exclusively for LLM inference.

---

## 🏛️ System Architecture

```mermaid
flowchart TD
    User([User Request]) --> Orch[Orchestrator<br/><b>4 tools</b>: agent, remember, memory_*]
    
    subgraph MemoryLayer [Memory Architecture]
        OrchMemory[(Root Memory<br/>General Preferences)]
        SpecialistMemory[(Domain Memory<br/>DSA / Project / Study)]
    end
    
    Orch -.->|Preferences| OrchMemory
    
    subgraph Specialists [Specialized Domain Subagents (Whitelisted Tools)]
        DSA[dsa-mentor<br/>Java DSA, LeetCode, Hints]
        Web[web-researcher<br/>Deep Research, Fact Verification]
        News[news-scout<br/>Daily AI & Tech Briefings]
        Code[coding-engineer<br/>Refactoring, Edits, Testing]
        Data[data-engineer<br/>SQL, ETL, Python Analytics]
        Study[study-tutor<br/>Textbooks, Concept Mastery]
        Career[career-agent<br/>Resumes, Skill Gap Analysis]
        Doc[document-analyst<br/>PDF/Report Deep Dives]
        PM[project-manager<br/>Milestones, Architecture, ADRs]
        Sys[system-agent<br/>Fedora, Hardware & LLM Health]
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

    Specialists -->|Distilled Findings| Synthesis[Synthesis & Response]
    Synthesis --> User
```

---

## 🤖 The 10 Specialists + Root Orchestrator

| Agent | Config | Primary Role | Whitelisted Tools |
| :--- | :--- | :--- | :--- |
| **`orchestrator`** | [`orchestrator.yaml`](agents/orchestrator.yaml) | Primary coordinator. Routes tasks, coordinates compound workflows, and retains global user preferences. | `agent`, `memory_search`, `memory_get`, `remember` **(Strict 4-tool lean root)** |
| **`dsa-mentor`** | [`dsa-mentor.yaml`](agents/dsa-mentor.yaml) | Java DSA interview coach. Teaches patterns over memorization; tracks weaknesses and problem logs in persistent memory. | `read`, `glob`, `grep`, `python_exec`, `memory_search`, `memory_get`, `remember` |
| **`web-researcher`** | [`web-researcher.yaml`](agents/web-researcher.yaml) | Read-only internet intelligence. Fact verification and research summaries with source links. | `web_search`, `web_fetch`, `web_page_query` |
| **`news-scout`** | [`news-scout.yaml`](agents/news-scout.yaml) | Daily tech scout. Synthesizes recent breakthroughs in AI, software engineering, markets, and space. | `web_search`, `web_fetch`, `web_page_query` |
| **`coding-engineer`** | [`coding-engineer.yaml`](agents/coding-engineer.yaml) | Full software engineering agent. Inspects repositories, applies minimal safe edits, runs test suites, and debugs. | `read`, `glob`, `grep`, `write`, `edit`, `bash_exec`, `python_exec` |
| **`data-engineer`** | [`data-engineer.yaml`](agents/data-engineer.yaml) | Data pipelines, SQL query optimization, ETL workflows, schema design, and dataset validation. | `read`, `glob`, `grep`, `write`, `edit`, `python_exec`, `bash_exec`, `load_document`, `chunk` |
| **`study-tutor`** | [`study-tutor.yaml`](agents/study-tutor.yaml) | Academic tutor. Explains concepts from textbooks, syllabus notes, and diagnostic question generation. | `read`, `glob`, `grep`, `load_document`, `chunk`, `memory_search`, `memory_get`, `remember` |
| **`career-agent`** | [`career-agent.yaml`](agents/career-agent.yaml) | Internship & job market researcher. Analyzes industry requirements against resumes to identify skill gaps. | `web_search`, `web_fetch`, `web_page_query`, `read`, `glob`, `grep` |
| **`document-analyst`** | [`document-analyst.yaml`](agents/document-analyst.yaml) | Long-document analyst. Extracts facts, metrics, and quotes from large PDFs and specifications (no host actions). | `read`, `glob`, `grep`, `load_document`, `chunk` |
| **`project-manager`** | [`project-manager.yaml`](agents/project-manager.yaml) | Architecture and task tracker. Maintains project milestones, TODOs, and architectural decisions (ADRs). | `read`, `glob`, `grep`, `write`, `edit`, `memory_search`, `memory_get`, `remember` |
| **`system-agent`** | [`system-agent.yaml`](agents/system-agent.yaml) | Linux system engineer. Diagnoses hardware health, RAM/VRAM utilization, thermal status, and `llama-server` performance. | `read`, `glob`, `grep`, `bash_exec` |

---

## 🔒 Security & The Capability Floor

To protect the host system from prompt injection attacks embedded in untrusted web pages, this system enforces an uncompromising capability rule:

> **No single agent may hold untrusted web ingestion tools and host-dangerous execution tools simultaneously.**

- **Untrusted Ingest:** `web_search`, `web_fetch`, `web_page_query`
- **Host-Dangerous:** `bash_exec`, `write`, `edit`, `python_exec`

If an agent needs information from the web to make a code change, the orchestrator delegates to `web-researcher` first, receives a sanitized data summary, and subsequently delegates the implementation task to `coding-engineer`.

---

## 🚀 Quick Start Guide

### Prerequisites
- **OS:** Linux (Fedora, Ubuntu, Arch, etc.) or macOS
- **Hardware:** 16GB RAM (at least 4GB allocated to integrated/dedicated GPU)
- **Tooling:** Python 3.12+, [`uv`](https://github.com/astral-sh/uv), and [`llama.cpp`](https://github.com/ggerganov/llama.cpp)
- **Model:** `gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf` (or any compatible quantized GGUF)

### 1. Clone the Repository
```bash
git clone https://github.com/Chetan0246/localharness.git
cd localharness
```

### 2. Launch the Local Inference Server
Start `llama-server` on your machine using Flash Attention and quantized KV caches:
```bash
# Using the provided launcher script:
LLAMA_DIR="$HOME/llama.cpp" ./scripts/run_gemma.sh
```
Or execute directly:
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

### 3. Install & Validate Agents
Run the automated setup script to synchronize agent configurations into `~/.localharness/agents/` and verify dependencies:
```bash
./scripts/setup_agents.sh
```

### 4. Launch the Interactive REPL
```bash
uv run localharness start
```

---

## 🧪 Verified Test Battery

The architecture has been verified against this targeted evaluation sequence:

### Test A: Root Memory & Recall
```text
❯ Remember that I prefer learning DSA through patterns rather than memorizing solutions.
◆ remember
✓ Remembered '...' (read-back verified)

❯ What do I prefer when learning DSA?
◆ memory_search
✓ Retrieves and quotes the stored preference accurately.
```

### Test B: Domain Delegation
```text
❯ Continue my Java DSA training.
◆ agent dsa-mentor
✓ Root delegates to dsa-mentor rather than answering at root level.
```

### Test C: Precise Routing
```text
❯ Give me today's AI and technology news.
◆ agent news-scout
✓ Correctly routes to news-scout (avoiding generic web-researcher collision).
```

### Test D: Security Containment
```text
❯ Search for the latest version of package numpy and install it.
◆ agent web-researcher
✓ Root never calls bash_exec; web inspection is strictly sandboxed.
```

### Compound Multi-Agent Workflow
```text
❯ Research current requirements for AI backend internships, inspect my current project stack, and identify my skill gaps.
```
*Trace execution:*
1. Orchestrator calls `agent(career-agent)` to research current hiring requirements.
2. Orchestrator calls `agent(project-manager)` to inspect local project files and dependencies.
3. Orchestrator synthesizes both findings into a unified, actionable gap analysis.

---

## 📂 Repository Structure

```text
localharness/
├── agents/                       # 10 Domain Specialists + Lean Orchestrator
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
├── scripts/                      # Utility Scripts
│   ├── run_gemma.sh              # llama-server runner with optimal flags
│   └── setup_agents.sh           # Automated setup and sync script
├── src/localharness/             # Core harness runtime engine
├── pyproject.toml                # Dependencies and project definition
└── README.md
```

---

## 🤝 Acknowledgements

- Built on top of the open-source **LocalHarness** engine by [@ahwurm](https://github.com/ahwurm/localharness).
- Powered by **Google DeepMind's Gemma 4** open weights.
- Inference enabled by Georgi Gerganov's **llama.cpp**.

---

## 📄 License
This project is licensed under the [MIT License](LICENSE).
