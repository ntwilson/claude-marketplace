# Review Focus Patterns

This reference provides detailed patterns for identifying suspicious code and areas requiring closer attention during code reviews.

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

**Swallowed Errors:**
```fsharp
// ⚠️ Suspicious: Error silently ignored
try
  riskyOperation()
with _ -> ()

// ✅ Better: Log or propagate error
try
  riskyOperation()
with ex ->
  Log.error $"Operation failed: {ex.Message}"
  reraise()
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

**Resource Leaks:**
```fsharp
// ⚠️ Suspicious: May not dispose
let stream = File.OpenRead(path)
processStream stream

// ✅ Better: Ensure disposal
use stream = File.OpenRead(path)
processStream stream
```

**Unbounded Growth:**
- Caches without eviction policies
- Collections that grow indefinitely
- Recursive functions without base cases
- Event handlers never unsubscribed

### 5. Logic Errors

**Off-by-One Errors:**
```fsharp
// ⚠️ Suspicious: May access index out of bounds
for i in 0..arr.Length do
  process arr.[i]

// ✅ Correct: Length - 1
for i in 0..arr.Length-1 do
  process arr.[i]
```

**Incorrect Comparisons:**
```fsharp
// ⚠️ Suspicious: Floating point equality
if price = 19.99 then ...

// ✅ Better: Tolerance-based comparison
if abs(price - 19.99) < 0.01 then ...
```

**Boolean Logic Errors:**
```fsharp
// ⚠️ Suspicious: Should this be OR?
if hasPermission && isEnabled then ...

// Verify: Does user need both, or just one?
```

**Timezone Issues:**
- Using DateTime instead of NodaTime
- Mixing local and UTC times
- Incorrect timezone conversions
- Not accounting for DST changes

### 6. Breaking Changes

**Signature Changes:**
```fsharp
// Before:
let processData (input: string) : Result<Data, Error> = ...

// After: ⚠️ Breaking change
let processData (input: string) (config: Config) : Result<Data, Error> = ...
```

**Type Changes:**
```fsharp
// Before:
type Status = Active | Inactive

// After: ⚠️ Breaking change - removed case
type Status = Active
```

**Behavioral Changes:**
- Function now throws where it didn't before
- Different default values
- Changed ordering or sorting
- Modified validation rules

### 7. Code Quality Issues

**Complex Conditionals:**
```fsharp
// ⚠️ Suspicious: Hard to understand
if (user.Role = "admin" || user.Role = "moderator") &&
   (user.Permissions.Contains("write") || user.IsOwner) &&
   not user.IsSuspended && user.EmailVerified then
  // ...

// ✅ Better: Extract to named functions
let canModifyContent user =
  let hasModeratorRole = user.Role = "admin" || user.Role = "moderator"
  let hasWriteAccess = user.Permissions.Contains("write") || user.IsOwner
  let isAccountValid = not user.IsSuspended && user.EmailVerified
  hasModeratorRole && hasWriteAccess && isAccountValid
```

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

### 8. Testing Concerns

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

**Inappropriate Use of Mutable:**
```fsharp
// ⚠️ Suspicious: Could be immutable
let mutable results = []
for item in items do
  results <- result :: results

// ✅ Better: Functional approach
let results = items |> List.map processItem
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

**Integer Overflow:**
- Arithmetic without overflow checking
- Counter increments without bounds
- Date/time arithmetic edge cases

## Prioritization Guidelines

### High Priority (Must Review Carefully)

1. **Security vulnerabilities** - Could lead to data breaches
2. **Data corruption risks** - Could lose or corrupt data
3. **Breaking changes** - Will break existing code/APIs
4. **Critical business logic** - Core functionality changes
5. **Authentication/authorization** - Access control changes

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

## Examples from Real Reviews

### Example 1: Cache Implementation

**Suspicious items:**
- No maximum cache size - unbounded memory growth
- No thread safety on eviction - race condition
- TTL hardcoded - should be configurable
- No cache invalidation on updates - stale data risk

**Priority areas:**
- `CacheManager.fs:evictExpired` - Thread safety critical
- `DataAssembly.fs:retrieveFromCache` - Verify error handling doesn't skip cache population

### Example 2: Validation Refactoring

**Suspicious items:**
- Breaking change to `validateInput` signature - check all callers
- New error types - ensure all are handled in match expressions
- Validation now returns list of errors - UI may not handle multiple errors

**Priority areas:**
- `Validation.fs:validateAll` - Ensure error accumulation works correctly
- All call sites of `validateInput` - Verify updated to handle new signature

### Example 3: Database Migration

**Suspicious items:**
- No rollback script provided
- Migration modifies existing data - backup required
- Large table modification - may lock table during migration
- Default value for new column - may not be appropriate for all rows

**Priority areas:**
- `Migration.fs:migrateUserPreferences` - Data transformation logic must be correct
- Review database transaction handling - ensure atomicity

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
