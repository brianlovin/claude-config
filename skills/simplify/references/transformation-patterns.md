# Transformation Patterns

Before/after examples for common simplification patterns.

## Nested Ternary to Switch

Before:

```ts
const label = status === "active" ? "Active" : status === "pending" ? "Pending" : status === "error" ? "Error" : "Unknown";
```

After:

```ts
function getStatusLabel(status: string): string {
  switch (status) {
    case "active":
      return "Active";
    case "pending":
      return "Pending";
    case "error":
      return "Error";
    default:
      return "Unknown";
  }
}
```

## Extract Repeated Logic

Before:

```ts
async function createUser(data: UserInput): Promise<Response> {
  const trimmedName = data.name.trim();
  if (!trimmedName || trimmedName.length < 2) {
    return Response.json({ error: "Invalid name" }, { status: 400 });
  }
  const trimmedEmail = data.email.trim();
  if (!trimmedEmail || !trimmedEmail.includes("@")) {
    return Response.json({ error: "Invalid email" }, { status: 400 });
  }
  // ...
}
```

After:

```ts
function validateRequired(value: string, label: string, check?: (v: string) => boolean): string {
  const trimmed = value.trim();
  if (!trimmed || (check && !check(trimmed))) {
    throw new ValidationError(`Invalid ${label}`);
  }
  return trimmed;
}

async function createUser(data: UserInput): Promise<Response> {
  const name = validateRequired(data.name, "name", (v) => v.length >= 2);
  const email = validateRequired(data.email, "email", (v) => v.includes("@"));
  // ...
}
```

## Flatten Nested Conditionals

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
      return { error: "No items in order" };
    }
  } else {
    return { error: "No order provided" };
  }
}
```

After:

```ts
function processOrder(order: Order): Result {
  if (!order) return { error: "No order provided" };
  if (order.items.length === 0) return { error: "No items in order" };
  if (order.status !== "pending") return { error: "Order already processed" };

  return submitOrder(order);
}
```

## Remove Redundant Abstraction

Before:

```ts
function getFormattedDate(date: Date): string {
  return formatDate(date);
}

function formatDate(date: Date): string {
  return date.toISOString().split("T")[0];
}

// Usage
const display = getFormattedDate(new Date());
```

After:

```ts
function formatDate(date: Date): string {
  return date.toISOString().split("T")[0];
}

// Usage
const display = formatDate(new Date());
```
