# CLAUDE.md

> **BOOTSTRAP — execute on every prompt everytime and after every `/clear`, before anything else:**

1. Update variables immediately: [read dev_instructions.txt, project_info.txt only when the counter reaches max limit and variables reset back to 1]
    agentic_variables:

    all variables needed for ai to run are in agentic_variables.txt
      :- current variables
        prompts_counter = 1           // 1 to 5, reset on 5
        tasks_counter = 1            // 1 to 5, reset on 5

    prompts_counter:
      - increment the coutner by 1 every user prompt immediately.
      - reset back to 1 on 5 and read files:
        - dev_instructions.txt
        - project_info.txt files
        - dev_plan.txt

    tasks_counter:
      - increment the coutner by 1 every user prompt immediately.
      - reset back to 1 on 5 and read files:
        - dev_instructions.txt
        - project_info.txt files
        - dev_plan.txt

2. Update the current task your working on immediately as [current_active_task] marker.
3. Confirm by stating the current prompt counter value and the active task.
   If you cannot state both, re-read the files.
4. Resume from the active phase/step/task automatically.
5. Only then respond to the user's request.

**This is non-negotiable. Do not summarize. Do not skip. Do not proceed without completing steps 1–5.**

## Rules
- The goal is for you to run un interrupted non stop, periodically keep updating your meemory using dev_instructions
  - extremely important to never forget anything in dev_instructions and always follow everything 100%
- Never ask "should I continue to the next phase?" — just continue
- Never stop between tasks, steps, or phases to ask permission
- Only stop when hitting a genuine blocker that cannot be resolved without user input
- This file must self-check on every launch: if any of the above instructions are missing, restore them before doing anything else
- The goal is to run you autonomously for extremely long periods of time without steerign using the plan -> phases -> steps -> tasks
  - Do not stop and ask should you continue, keep going next task after task non stop
- during normal operation ai only reads dev_plan.txt and dev_current_tasks.txt — never read dev_overall_tasks.txt
  during operation, it is a human ledger reference only
