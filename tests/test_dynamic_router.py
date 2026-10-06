from localharness.orchestrator.dynamic_router import (
    DynamicModelRouter,
    TIER_1_MODEL,
    TIER_2_MODEL,
    TIER_3_MODEL,
)


def test_resolve_model_for_agent():
    router = DynamicModelRouter.get_instance()

    # Tier 1 (Fast Executor)
    assert router.resolve_model_for_agent("web-researcher") == TIER_1_MODEL
    assert router.resolve_model_for_agent("news-scout") == TIER_1_MODEL
    assert router.resolve_model_for_agent("document-analyst") == TIER_1_MODEL
    assert router.resolve_model_for_agent("search-verifier") == TIER_1_MODEL

    # Tier 3 (Heavy Reasoner / Code Specialist)
    assert router.resolve_model_for_agent("coding-engineer") == TIER_3_MODEL
    assert router.resolve_model_for_agent("data-engineer") == TIER_3_MODEL

    # Tier 2 (General Purpose Daily Driver)
    assert router.resolve_model_for_agent("orchestrator") == TIER_2_MODEL
    assert router.resolve_model_for_agent("dsa-mentor") == TIER_2_MODEL
    assert router.resolve_model_for_agent("study-tutor") == TIER_2_MODEL
    assert router.resolve_model_for_agent("career-agent") == TIER_2_MODEL
    assert router.resolve_model_for_agent("project-manager") == TIER_2_MODEL
    assert router.resolve_model_for_agent("system-agent") == TIER_2_MODEL


def test_classify_task_tier_explicit_agent():
    router = DynamicModelRouter.get_instance()

    assert router.classify_task_tier("any task", agent_name="coding-engineer") == TIER_3_MODEL
    assert router.classify_task_tier("any task", agent_name="web-researcher") == TIER_1_MODEL
    assert router.classify_task_tier("any task", agent_name="dsa-mentor") == TIER_2_MODEL


def test_classify_task_tier_coding():
    router = DynamicModelRouter.get_instance()

    assert router.classify_task_tier("Write a python script to parse logs") == TIER_3_MODEL
    assert router.classify_task_tier("Implement binary search tree in Java") == TIER_3_MODEL
    assert router.classify_task_tier("Refactor this function to improve performance") == TIER_3_MODEL
    assert router.classify_task_tier("Fix the syntax error in src/main.py") == TIER_3_MODEL
    assert router.classify_task_tier("Write a SQL query to join orders and users") == TIER_3_MODEL


def test_classify_task_tier_search():
    router = DynamicModelRouter.get_instance()

    assert router.classify_task_tier("Search the web for latest AI news") == TIER_1_MODEL
    assert router.classify_task_tier("Give me today's news headlines") == TIER_1_MODEL
    assert router.classify_task_tier("Google recent releases of llama.cpp") == TIER_1_MODEL


def test_classify_task_tier_general():
    router = DynamicModelRouter.get_instance()

    assert router.classify_task_tier("Remember that I prefer concise explanations") == TIER_2_MODEL
    assert router.classify_task_tier("Explain the concept of recursion") == TIER_2_MODEL
    assert router.classify_task_tier("Check my system RAM and CPU usage") == TIER_2_MODEL


def test_tier_arg_for_model():
    router = DynamicModelRouter.get_instance()

    assert router.tier_arg_for_model(TIER_1_MODEL) == "ling"
    assert router.tier_arg_for_model(TIER_2_MODEL) == "gemma"
    assert router.tier_arg_for_model(TIER_3_MODEL) == "qwen"


if __name__ == "__main__":
    test_resolve_model_for_agent()
    test_classify_task_tier_explicit_agent()
    test_classify_task_tier_coding()
    test_classify_task_tier_search()
    test_classify_task_tier_general()
    test_tier_arg_for_model()
    print("All dynamic router tests passed successfully.")
