---
name: simplify
description: >
  Simplify recently modified code by renaming variables for clarity, extracting repeated logic
  into functions, flattening nested conditionals, and removing redundant abstractions. Use when
  asked to clean up, refactor, polish, tidy, or make code more readable after writing it.
version: 1.0.1
license: MIT
---

## References

Consult these resources as needed:

- ./references/transformation-patterns.md -- Before/after examples for common simplification patterns

## Workflow

1. Identify recently modified code sections (use git diff or session context)
2. Analyze each section for simplification opportunities against project standards
3. Apply transformations — rename, extract, flatten, deduplicate — one concern at a time
4. Run existing tests to verify functionality is unchanged before committing refinements
5. Summarize what changed and why in the commit or response

## Example: Flatten Nested Conditionals

Before:

```ts
function processOrder(order: Order): Result {
  if (order) {
    if (order.items.length > 0) {
      if (order.status === "pending") {
        return submitOrder(order);
      } else {
        return { error: "Order already processed" };
      }
    } else {
      return { error: "No items" };
    }
  } else {
    return { error: "No order" };
  }
}
```

After:

```ts
function processOrder(order: Order): Result {
  if (!order) return { error: "No order" };
  if (order.items.length === 0) return { error: "No items" };
  if (order.status !== "pending") return { error: "Order already processed" };

  return submitOrder(order);
}
```

## Principles

1. **Preserve behavior** — never change what the code does, only how it reads
2. **Apply project standards** from CLAUDE.md (ES modules, `function` keyword, explicit return types, React Props types, consistent naming)
3. **Enhance clarity** — flatten nesting, extract repeated logic, rename for intent, remove redundant comments, avoid nested ternaries (prefer switch/if-else)
4. **Maintain balance** — don't over-simplify; keep helpful abstractions, avoid dense one-liners, prefer readability over fewer lines
5. **Focus scope** — only refine recently modified code unless told otherwise
