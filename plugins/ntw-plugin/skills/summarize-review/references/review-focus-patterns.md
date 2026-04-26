# Review Focus Patterns

This reference provides detailed patterns for identifying suspicious code and areas requiring closer attention during code reviews. If you have access to the fsharp-conventions skill, also flag any violations of the conventions.

## Categories of Focus Areas

### 1. Security Concerns

**SQL Injection:**
```fsharp
// ⚠️ Suspicious: String interpolation in SQL
let query = $"SELECT * FROM users WHERE id = {userId}"

// ✅ Safe: Parameterized query
selectIO HydraReader.Read ctx {
  for user in dbo.users do
  where (user.id = userId)
}
```

**Command Injection:**
```fsharp
// ⚠️ Suspicious: Unvalidated input in shell command
let! output = Process.run $"git log {branch}"

// ✅ Better: Validate input first
let! output =
  if isValidBranchName branch then
    Process.run $"git log {branch}"
  else
    Error "Invalid branch name"
```

**Authentication/Authorization:**
- Missing authentication checks on sensitive operations
- Authorization checks after data access
- Hardcoded credentials or API keys
- Weak password validation

**Data Exposure:**
- Logging sensitive data (passwords, tokens, PII)
- Returning too much data in API responses
- Missing encryption for sensitive data

### 2. Error Handling Issues

**Unhandled Exceptions:**
```fsharp
// ⚠️ Suspicious: May throw exception
let parseDate (s: string) = DateTime.Parse(s)

// ✅ Better: Returns Result
let parseDate (s: string) =
  match DateTime.TryParse(s) with
  | true, date -> Ok date
  | false, _ -> Error $"Invalid date: {s}"
```

**Possible Failure with Option and Result:**
Functions like `Result.expect`, `Option.get`, `Option.unless`, etc. that unwrap the value without handling the error case should only be used when the error case should be unreachable:

```fsharp
// ❌️ Suspicious: May throw exception if someone calls calculateStats with an empty list
let calculateStats (xs: float list) = 
  { 
    Sum = List.sum xs
    Average = List.tryAverage xs |> Option.unless "List is empty"
    Min = List.tryMin xs |> Option.unless "List is empty"
    Max = List.tryMax xs |> Option.unless "List is empty"
  }

let statsPerStation (rows: StationData list) =
  rows
  |> List.groupBy _.Station
  |> List.map (fun (station, group) -> group |> List.map _.Value |> calculateStats)

// ⚠️ Better: `None` case is unreachable, but still flag
let statsPerStation (rows: StationData list) =
  rows
  |> List.groupBy _.Station
  |> List.map (fun (station, group) -> 
    let values = group |> List.map _.Value
    {
      Sum = List.sum values
      Average = List.tryAverage values |> Option.unless "List.groupBy produced an empty group"
      Min = List.tryMin values |> Option.unless "List.groupBy produced an empty group"
      Max = List.tryMax values |> Option.unless "List.groupBy produced an empty group"
    })

// ✅ Best: Use SafetyFirst to avoid Option.unless altogether
let statsPerStation (rows: StationData list) =
  rows
  |> List.group _.Station
  |> List.map (fun (station, group) -> 
    let values = group |> List.NonEmpty.map _.Value
    {
      Sum = List.NonEmpty.sum values
      Average = List.NonEmpty.average values
      Min = List.NonEmpty.min values
      Max = List.NonEmpty.max values
    })
```

**Missing Validation:**
- No input validation on user-provided data
- Missing null/None checks before use
- Array/list access without bounds checking
- Division without zero check

### 3. Concurrency and Thread Safety

**Race Conditions:**
```fsharp
// ⚠️ Suspicious: Check-then-act race condition
if not (cache.ContainsKey key) then
  cache.Add(key, value)  // May fail if another thread added between check and add

// ✅ Better: Atomic operation
cache.TryAdd(key, value)
```

**Shared Mutable State:**
```fsharp
// ⚠️ Suspicious: Mutable state without synchronization
let mutable counter = 0
let increment() = counter <- counter + 1  // Not thread-safe

// ✅ Better: Use Interlocked or mailbox
let increment() = Interlocked.Increment(&counter)
```

**Deadlock Potential:**
- Multiple locks acquired in different orders
- Locks held during async operations
- Recursive lock acquisition

### 4. Performance Issues

**N+1 Queries:**
```fsharp
// ⚠️ Suspicious: Query in loop
for user in users do
  let! orders = getOrdersForUser user.Id  // N queries

// ✅ Better: Batch query
let userIds = users |> List.map (_.Id)
let! allOrders = getOrdersForUsers userIds  // 1 query
```

**Inefficient Algorithms:**
- Nested loops with large datasets
- Repeated expensive operations in loops
- Lack of memoization for pure functions
- Unnecessary allocations in hot paths

**Unbounded Growth:**
- Caches without eviction policies
- Collections that grow indefinitely
- Recursive functions without base cases
- Event handlers never unsubscribed

### 5. Logic Errors

- Off-by-One Errors
- Floating Point Equality
- Boolean Logic Errors
- Timezone Issues

### 6. Code Quality Issues

**Deep Nesting:**
- More than 3-4 levels of nesting
- Difficult to follow control flow
- Should be refactored into smaller functions

**Code Duplication:**
- Same logic repeated in multiple places
- Should be extracted to shared function
- Violates DRY principle

**Magic Numbers:**
```fsharp
// ⚠️ Suspicious: What does 86400 mean?
let secondsInDay = 86400

// ✅ Better: Named constant
let secondsInDay = 24 * 60 * 60
```

### 7. Testing Concerns

**Missing Test Coverage:**
- New functionality without tests
- Complex logic without unit tests
- Edge cases not tested
- Error paths not covered

**Inadequate Test Cases:**
- Only happy path tested
- No boundary condition tests
- Missing negative test cases
- Tests that don't verify actual behavior

**Test Quality Issues:**
- Tests that always pass
- Tests with hard-coded expected values
- Brittle tests (too tightly coupled to implementation)
- Non-deterministic tests (flaky tests)

## Language-Specific Patterns

### F# Specific

**Always-flag items** — these should be flagged every time they appear in changed code:

**Functions that may throw:**
```fsharp
// ⚠️ Always flag: throws on empty collection
let first = items |> Array.head
let first = items |> List.head
let only = items |> Seq.exactlyOne

// ⚠️ Always flag: throws on missing key
let value = dict.[key]
let value = map |> Map.find key

// ⚠️ Always flag: throws on None
let value = someOption |> Option.get
```

**Mutable declarations:**
```fsharp
// ⚠️ Always flag
let mutable counter = 0
```

**Mutable collection operations:**
```fsharp
// ⚠️ Always flag: in-place mutation
dict.Add(key, value)
resizeArray.Add(item)
hashSet.Remove(item)
list.Insert(0, item)
dict.[key] <- newValue
```

**Non-deterministic operations outside `io { ... }`:**
```fsharp
// ⚠️ Always flag when outside io { }
let now = DateTime.UtcNow
let id = Guid.NewGuid()
let envVar = Environment.GetEnvironmentVariable("KEY")

// ✅ OK: inside io { }
io {
  let now = DateTime.UtcNow
  ...
}
```

**Side effects outside `io { ... }`:**
```fsharp
// ⚠️ Always flag when outside io { }
let contents = File.ReadAllText(path)
Console.WriteLine("debug")
let response = httpClient.GetAsync(url)

// ✅ OK: inside io { }
io {
  let! contents = File.ReadAllText(path)
  ...
}
```

**Partial Active Patterns:**
```fsharp
// ⚠️ Suspicious: Partial match in let binding
let (Some value) = tryGetValue()  // Throws if None

// ✅ Better: Complete match
match tryGetValue() with
| Some value -> processValue value
| None -> handleMissing()
```

**Recursive Function Without Base Case:**
```fsharp
// ⚠️ Suspicious: No termination condition
let rec processList lst =
  match lst with
  | head :: tail ->
      doSomething head
      processList tail
  // Missing: | [] -> () base case
```

### PureScript Specific

**Always-flag items** — these should be flagged every time they appear in changed code:

**Any use of `unsafe` functions:**
```purescript
-- ⚠️ Always flag: bypasses type safety
unsafeCoerce value
unsafePartial (fromJust maybeValue)
unsafePerformEffect (log "debug")
unsafeThrow (error "crash")
unsafeFreeze mutableArray
unsafeThaw immutableArray
-- Any other function with "unsafe" in the name
```

### Python Specific

**Mutable Default Arguments:**
```python
# ⚠️ Suspicious: Mutable default argument
def process(items=[]):  # Same list reused across calls
    items.append(1)
    return items

# ✅ Better: None default
def process(items=None):
    items = items or []
    items.append(1)
    return items
```

**Unclosed Resources:**
```python
# ⚠️ Suspicious: File may not close
f = open('file.txt')
data = f.read()
f.close()

# ✅ Better: Context manager
with open('file.txt') as f:
    data = f.read()
```

### General Patterns

**Null/None Dereference:**
- Accessing properties without null check
- Array access without length check
- Dictionary lookup without containment check

## Prioritization Guidelines

### High Priority (Must Review Carefully)

1. **Security vulnerabilities** - Could lead to data breaches
2. **Data corruption risks** - Could lose or corrupt data
3. **Critical business logic** - Core functionality changes
4. **Authentication/authorization** - Access control changes

### Medium Priority (Should Review)

6. **Performance concerns** - Could impact user experience
7. **Error handling gaps** - Could lead to poor UX or debugging difficulty
8. **Complex refactorings** - High risk of introducing bugs
9. **Database migrations** - Could cause deployment issues
10. **Missing tests** - Reduces confidence in changes

### Lower Priority (Nice to Review)

11. **Code style issues** - Readability and maintainability
12. **Documentation gaps** - Helpful but not critical
13. **Minor optimizations** - Small improvements
14. **Logging changes** - Observability improvements

## Review Focus Section Template

Structure the Review Focus section as:

```markdown
## Review Focus

### ⚠️ Items Requiring Attention
- **[Category]: [Location]** - [Specific concern and why it matters]
- **Security: `Auth.fs:validateToken`** - Token validation allows expired tokens if clock skew exceeds 5 minutes
- **Breaking change: `API.fs:getUserData`** - Removed `email` field from response, may break existing clients
- **Race condition: `Cache.fs:getOrAdd`** - Check-then-act pattern not thread-safe under concurrent load
- **Missing validation: `Input.fs:parseUserInput`** - No sanitization before database query, potential SQL injection

### 📍 Priority Files/Functions
- **`path/to/file.ext:functionName`** - [Why this needs closer review and what to look for]
- **`Auth.fs:validateToken`** - Core security function; verify all validation rules are correct and can't be bypassed
- **`DataMigration.fs:migrateUserData`** - Data migration with no rollback; ensure thorough testing before deployment
- **`Cache.fs`** - Entire file introduces caching; review for thread safety, memory bounds, and invalidation logic
```

## Identifying Subtle Issues

### Type System Bypasses

```fsharp
// ⚠️ Suspicious: Downcasting
let user = obj :?> User  // May fail at runtime

// ⚠️ Suspicious: Type erasure
let data = deserialize<'T> json  // Unchecked cast
```

### Async/Await Issues

```fsharp
// ⚠️ Suspicious: Blocking on async
let result = asyncOp |> Async.RunSynchronously  // Deadlock risk

// ⚠️ Suspicious: Fire and forget
async { do! backgroundWork() } |> Async.Start  // No error handling
```

### Boundary Conditions

- Empty collections
- Single-element collections
- Very large collections
- Minimum/maximum values
- Null/None values
- Special characters in strings

## Summary

When building the Review Focus section:

1. **Scan for patterns** from this reference
2. **Prioritize by impact** - security > data integrity > performance > style
3. **Be specific** - Include file:function locations and concrete concerns
4. **Explain why** - Don't just say "review this", explain what to look for
5. **Limit to key items** - 5-10 items max; more suggests PR is too large
6. **Group related items** - Multiple issues in same function can be one item
7. **Note if nothing concerning** - "No significant concerns found" is valid

The goal is to help reviewers focus their limited time on the most important aspects of the change.
