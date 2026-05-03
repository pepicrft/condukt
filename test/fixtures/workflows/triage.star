condukt.workflow(
    name = "triage",
    agent = condukt.agent(
        model = "openai:gpt-4.1-mini",
        system_prompt = "Triage incoming issues.",
        tools = [condukt.tool("read")],
        sandbox = condukt.sandbox.local(cwd = "."),
    ),
    triggers = [condukt.trigger.webhook(path = "/triage")],
    inputs = {"type": "object"},
)
