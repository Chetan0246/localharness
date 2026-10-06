"""Dynamic task-based model router for single-heavy local APU architectures.

Optimized for 16GB laptops with AMD Radeon 780M / unified memory architectures.
Enforces the box rule: at most one heavy model active at a time.
Automatically switches models (stopping incumbent, settling memory, starting target)
based on incoming user tasks and subagent delegations.
"""
from __future__ import annotations

import asyncio
import logging
import os
import re
from pathlib import Path
from typing import Any, Callable, Coroutine

import httpx

log = logging.getLogger(__name__)

# Tier 1: Fast Executor (~35 t/s, 16k context, 4.5GB)
TIER_1_MODEL = "Ling-3.0-tiny-Q4_K_M.gguf"
# Tier 2: General Purpose Daily Driver (~13 t/s, 16k context, 4.0GB)
TIER_2_MODEL = "gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf"
# Tier 3: Heavy Reasoner / Code Specialist (~7 t/s, 8k context, 5.3GB)
TIER_3_MODEL = "Qwen3.5-9B-Q4_K_M.gguf"

# Mapping from agent personas to required model tiers
AGENT_TIER_MAP: dict[str, str] = {
    # Tier 1: Fast tool execution, web search & document lookups
    "web-researcher": TIER_1_MODEL,
    "news-scout": TIER_1_MODEL,
    "document-analyst": TIER_1_MODEL,
    "search-verifier": TIER_1_MODEL,

    # Tier 3: Heavy reasoning, deep coding, algorithm design, data engineering
    "coding-engineer": TIER_3_MODEL,
    "data-engineer": TIER_3_MODEL,

    # Tier 2: Balanced general reasoning, orchestration, tutoring, system diagnostics
    "orchestrator": TIER_2_MODEL,
    "default": TIER_2_MODEL,
    "dsa-mentor": TIER_2_MODEL,
    "study-tutor": TIER_2_MODEL,
    "career-agent": TIER_2_MODEL,
    "project-manager": TIER_2_MODEL,
    "system-agent": TIER_2_MODEL,
    "explore": TIER_2_MODEL,
}

# Regex patterns that indicate high-complexity coding tasks
_CODING_PATTERNS = re.compile(
    r"\b(write\s+(?:a\s+)?(?:python|bash|java|c\+\+|rust|go|sql|shell)?\s*(?:script|program|code|function|class|module)|"
    r"implement\b|refactor\b|debug\b|fix\s+(?:the\s+)?(?:bug|error|issue|crash)|"
    r"syntax\s*error|traceback|exception|unittest|pytest|test\s+suite|"
    r"algorithm\b|data\s+structure\b|leetcode|sliding\s+window|dynamic\s+programming|"
    r"sql\s+query|database\s+schema|create\s+table|alter\s+table|etl\s+pipeline|"
    r"fastapi|flask|django|dockerfile|makefile|git\s+commit)\b",
    re.IGNORECASE,
)

# Regex patterns that indicate fast web / news / document lookup tasks
_FAST_RESEARCH_PATTERNS = re.compile(
    r"\b(search\s+(?:the\s+)?web|web\s*search|google|search\s+for|"
    r"latest\s+news|today'?s\s+news|recent\s+headlines|market\s+headlines|"
    r"browse\b|fetch\s+url|lookup\s+online|find\s+articles?|scrape)\b",
    re.IGNORECASE,
)


class DynamicModelRouter:
    """Manages dynamic model switching across tiers based on tasks and agents."""

    _instance: DynamicModelRouter | None = None

    def __init__(
        self,
        base_url: str = "http://127.0.0.1:8080/v1",
        enabled: bool = True,
        switcher_script: Path | None = None,
    ) -> None:
        self.base_url = base_url
        self.enabled = enabled
        self._switcher_script = switcher_script or self._find_switcher_script()
        self._lock = asyncio.Lock()
        DynamicModelRouter._instance = self

    @classmethod
    def get_instance(cls) -> DynamicModelRouter:
        if cls._instance is None:
            cls._instance = DynamicModelRouter()
        return cls._instance

    @staticmethod
    def _find_switcher_script() -> Path:
        """Locate switch_model.sh relative to repository or standard locations."""
        candidates = [
            Path(__file__).resolve().parent.parent.parent.parent / "scripts" / "switch_model.sh",
            Path.cwd() / "scripts" / "switch_model.sh",
            Path.home() / "localharness" / "scripts" / "switch_model.sh",
        ]
        for c in candidates:
            if c.is_file() and os.access(c, os.X_OK):
                return c
        return candidates[0]

    def resolve_model_for_agent(self, agent_id: str) -> str:
        """Resolve the model required by a specific specialist agent."""
        norm = agent_id.strip().lower().replace("_", "-")
        return AGENT_TIER_MAP.get(norm, TIER_2_MODEL)

    def classify_task_tier(self, task: str, agent_name: str | None = None) -> str:
        """Classify a free-form task into the appropriate model tier."""
        # 1. If an explicit agent is specified and is not the generic orchestrator, use its tier
        if agent_name and agent_name not in ("orchestrator", "default"):
            return self.resolve_model_for_agent(agent_name)

        low = task.lower()

        # 2. Check for explicit agent delegation in text (e.g. "ask coding-engineer to...")
        for name, model in AGENT_TIER_MAP.items():
            if name in low and name not in ("orchestrator", "default"):
                return model

        # 3. Check for heavy coding / engineering tasks
        if _CODING_PATTERNS.search(low):
            return TIER_3_MODEL

        # 4. Check for fast web / news search tasks
        if _FAST_RESEARCH_PATTERNS.search(low):
            return TIER_1_MODEL

        # 5. Default to Tier 2 (General / Daily Driver)
        return TIER_2_MODEL

    async def get_active_model(self) -> str | None:
        """Query http://127.0.0.1:8080/v1/models to see what is currently serving."""
        try:
            async with httpx.AsyncClient(timeout=1.5) as client:
                r = await client.get(f"{self.base_url.rstrip('/')}/models")
                if r.status_code == 200:
                    data = r.json()
                    models = data.get("data", [])
                    if models and "id" in models[0]:
                        return models[0]["id"]
        except Exception:
            pass
        return None

    def tier_arg_for_model(self, model_id: str) -> str:
        """Convert a model id or filename to switch_model.sh tier argument."""
        if "ling" in model_id.lower():
            return "ling"
        if "qwen" in model_id.lower():
            return "qwen"
        return "gemma"

    async def switch_model(
        self,
        target_model: str,
        *,
        llm: Any = None,
        on_status: Callable[[str], Any] | None = None,
    ) -> bool:
        """Switch the serving backend to `target_model` if not already active.

        Stops incumbent server, settles memory, launches target, and rebinds `llm`.
        """
        if not self.enabled:
            return True

        async with self._lock:
            current = await self.get_active_model()
            if current == target_model:
                # Already serving target model
                return True

            tier_arg = self.tier_arg_for_model(target_model)
            tier_display = (
                "Tier 1 (Ling-3.0-tiny · Fast)" if tier_arg == "ling"
                else "Tier 3 (Qwen3.5-9B · Heavy Reasoner)" if tier_arg == "qwen"
                else "Tier 2 (Gemma-4-E4B · Daily Driver)"
            )

            msg = f"[Dynamic Router] Switching model: {current or 'none'} ➔ {target_model} ({tier_display})..."
            log.info(msg)
            if on_status:
                try:
                    res = on_status(msg)
                    if asyncio.iscoroutine(res):
                        await res
                except Exception:
                    pass

            script = self._switcher_script
            if not script.exists():
                log.error("switcher script not found at %s", script)
                return False

            # Run switch_model.sh in a subprocess
            proc = await asyncio.create_subprocess_exec(
                str(script),
                tier_arg,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
            )
            stdout, _ = await proc.communicate()
            if proc.returncode != 0:
                err_msg = f"[Dynamic Router] Model switch failed (exit {proc.returncode}):\n{stdout.decode()}"
                log.error(err_msg)
                if on_status:
                    try:
                        res = on_status(err_msg)
                        if asyncio.iscoroutine(res):
                            await res
                    except Exception:
                        pass
                return False

            # Verify the model is now reachable
            ready_model = await self.get_active_model()
            if not ready_model:
                log.error("[Dynamic Router] Model server not answering after switch")
                return False

            # Rebind LLMClient if provided
            if llm is not None:
                try:
                    llm.rebind_endpoint(self.base_url, provider_type="llamacpp")
                    llm.config.model = ready_model
                    await llm.detect_capabilities()
                    log.info("[Dynamic Router] LLM client rebound to %s", ready_model)
                except Exception as exc:
                    log.error("[Dynamic Router] Failed to rebind LLM client: %s", exc)

            ready_msg = f"[Dynamic Router] Active model is now {ready_model}."
            log.info(ready_msg)
            if on_status:
                try:
                    res = on_status(ready_msg)
                    if asyncio.iscoroutine(res):
                        await res
                except Exception:
                    pass

            return True
