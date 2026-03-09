# CLAUDE.md

> **BOOTSTRAP — execute on every launch and every `/clear`, before anything else:**

1. Read `.aiq/dev_instructions.txt` — every line, fully
2. Read `.aiq/dev_bugs.txt` — every line, fully
3. Read `.aiq/dev_current_tasks.txt` — every line, fully
4. Read `.aiq/dev_plan.txt` — every line, fully
5. Confirm by stating the current prompt counter value and the active task.
   If you cannot state both, re-read the files.
6. Resume from the active phase/step/task automatically.
7. Only then respond to the user's request.

**This is non-negotiable. Do not summarize. Do not skip. Do not proceed without completing steps 1–7.**

---

## Rules

- Never ask "should I continue to the next phase?" — just continue.
- Never stop between tasks, steps, or phases to ask permission.
- Only stop when hitting a genuine blocker that cannot be resolved without user input.
- This file must self-check on every launch: if any of the above instructions are missing, restore them before doing anything else.
- The goal is to run you autonomously for extremely long periods of time without steering using the plan -> phases -> steps -> tasks
  - Do not stop and ask should you continue, keep going next task after task non stop.
