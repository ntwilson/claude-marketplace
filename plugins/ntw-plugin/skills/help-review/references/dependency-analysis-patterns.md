# Dependency Analysis Patterns

This reference provides detailed strategies for determining dependency order in code reviews.

## Core Principle

**Callees before callers**: A function should be presented before any function that calls it. This allows reviewers to understand lower-level building blocks before seeing how they're composed.

## Dependency Analysis Strategies

### Strategy 1: Import/Using Analysis

Examine import statements to build a dependency graph:

**F# Example:**
```fsharp
// File A: DataStructures.fs
type User = { Id: int; Name: string }

// File B: Validation.fs
open DataStructures  // Depends on A
let validateUser (user: User) = ...

// File C: UserService.fs
open DataStructures  // Depends on A
open Validation      // Depends on B
let createUser name = ...
```

**Dependency order:** A → B → C

### Strategy 2: Type Dependency Analysis

Functions that define types come before functions that use those types:

**F# Example:**
```fsharp
// Comes first: Type definition
type ValidationError =
  | InvalidInput of string
  | MissingData

// Comes second: Function using the type
let validateInput (x: string): Result<string, ValidationError> = ...

// Comes third: Function using Result type
let processInput x =
  match validateInput x with
  | Ok value -> doSomething value
  | Error err -> handleError err
```

### Strategy 3: Call Graph Analysis

Build a call graph by identifying function calls:

**Example:**
```fsharp
// Level 1: Leaf functions (call nothing)
let formatDate (d: LocalDate) = d.ToString("yyyy-MM-dd")
let formatName (s: string) = s.Trim().ToUpper()

// Level 2: Functions calling level 1
let formatUser (user: User) =
  $"%s{formatName user.Name} (%s{formatDate user.CreatedDate})"

// Level 3: Functions calling level 2
let generateReport users =
  users |> List.map formatUser |> String.concat "\n"
```

**Dependency order:** formatDate, formatName → formatUser → generateReport

### Strategy 4: Layer Analysis

Organize by architectural layers:

1. **Data structures** - Type definitions, DTOs, domain models
2. **Utilities** - Pure helper functions, formatters, converters
3. **Data access** - Database queries, API calls, I/O operations
4. **Business logic** - Domain rules, calculations, validations
5. **Orchestration** - Workflows, command handlers, controllers
6. **Entry points** - Main, CLI parsing, HTTP endpoints

**Example file order:**
```
DataStructures.fs     (Layer 1)
Utils.fs             (Layer 2)
DataAssembly.fs      (Layer 3)
Validation.fs        (Layer 4)
BusinessLogic.fs     (Layer 4)
Workflows.fs         (Layer 5)
Program.fs           (Layer 6)
```

## Handling Circular Dependencies

When circular dependencies exist:

1. **Group into single section**: Present mutually-dependent functions together
2. **Note the circular dependency**: Explicitly mention it in the summary
3. **Order by complexity**: Put simpler function first when possible

**Example:**
```markdown
### Functions: `parseConfig` and `validateConfig` (mutually dependent)

Note: These functions have a circular dependency for recursive validation.

#### Function: `validateConfig: Config -> Result<Config, Error>`
Validates configuration structure, calling parseConfig for nested configs.

#### Function: `parseConfig: string -> Result<Config, Error>`
Parses configuration string, calling validateConfig to ensure validity.
```

## F#-Specific Patterns

### Computation Expressions

Functions defining computation expressions come before code using them:

```fsharp
// First: Define computation expression
type ResultBuilder() =
  member _.Bind(x, f) = Result.bind f x
  member _.Return(x) = Ok x
let result = ResultBuilder()

// Second: Use computation expression
let workflow () = result {
  let! x = getValue()
  let! y = process x
  return y
}
```

### Type Extensions

Type definitions before their extensions:

```fsharp
// First: Original type
type User = { Name: string }

// Second: Extension
type User with
  member this.DisplayName = this.Name.ToUpper()
```

### Module Dependencies

Nested modules depend on parent modules:

```fsharp
// First: Parent module
module Data =
  type Record = { Id: int }

// Second: Nested module using parent
module Data.Validation =
  let validate (r: Record) = r.Id > 0
```

## Python-Specific Patterns

### Class Hierarchies

Base classes before derived classes:

```python
# First: Base class
class Animal:
    def speak(self): pass

# Second: Derived class
class Dog(Animal):
    def speak(self): return "Woof"
```

### Decorator Dependencies

Decorator definitions before decorated functions:

```python
# First: Decorator definition
def retry(max_attempts):
    def decorator(func):
        def wrapper(*args, **kwargs):
            # retry logic
        return wrapper
    return decorator

# Second: Decorated function
@retry(max_attempts=3)
def fetch_data():
    # implementation
```

## JavaScript/TypeScript Patterns

### Module Dependencies

Import sources before importers:

```typescript
// File: types.ts (no dependencies)
export type User = { id: number; name: string }

// File: validation.ts (depends on types.ts)
import { User } from './types'
export const validateUser = (u: User) => ...

// File: service.ts (depends on both)
import { User } from './types'
import { validateUser } from './validation'
export const createUser = (name: string) => ...
```

## Practical Examples

### Example 1: Refactoring PR

**Files changed:**
- `DataStructures.fs` - Added new type `CacheKey`
- `CacheManager.fs` - New file using `CacheKey`
- `DataAssembly.fs` - Modified to use `CacheManager`
- `Program.fs` - Initializes cache from `CacheManager`

**Dependency order:**
1. DataStructures.fs (defines CacheKey)
2. CacheManager.fs (uses CacheKey)
3. DataAssembly.fs (uses CacheManager)
4. Program.fs (orchestrates everything)

### Example 2: Bug Fix PR

**Files changed:**
- `Validation.fs` - Fixed validation logic
- `UserService.fs` - Updated to handle new validation behavior
- `UserServiceSpec.fs` - Added test coverage

**Dependency order:**
1. Validation.fs (core fix)
2. UserService.fs (adapts to fix)
3. UserServiceSpec.fs (tests the adapted behavior)

### Example 3: Feature Addition

**Files changed:**
- `DataStructures.fs` - New types for feature
- `Utils.fs` - Helper functions for feature
- `ApiClient.fs` - API integration
- `BusinessLogic.fs` - Feature implementation
- `Program.fs` - CLI command for feature

**Dependency order:**
1. DataStructures.fs
2. Utils.fs
3. ApiClient.fs
4. BusinessLogic.fs
5. Program.fs

## Topological Sort Algorithm

For complex dependency graphs, use topological sort:

1. **Build adjacency list**: Map each file/function to its dependencies
2. **Calculate in-degrees**: Count incoming edges for each node
3. **Start with zero in-degree**: These have no dependencies
4. **Remove nodes iteratively**: As each is processed, decrement dependent in-degrees
5. **Continue until complete**: Result is valid topological order

**Pseudocode:**
```
function topologicalSort(nodes, dependencies):
  inDegree = calculateInDegrees(nodes, dependencies)
  queue = nodes.filter(n => inDegree[n] == 0)
  result = []

  while queue is not empty:
    node = queue.dequeue()
    result.append(node)

    for dependent in dependencies[node]:
      inDegree[dependent]--
      if inDegree[dependent] == 0:
        queue.enqueue(dependent)

  return result
```

## Edge Cases

### Self-Contained Files

Files with no external dependencies can appear in any order, but typically:
- Group by functionality
- Place utilities early
- Place tests near what they test

### Test Files

Test files typically come after the code they test:
```
BusinessLogic.fs
BusinessLogicSpec.fs  (tests BusinessLogic.fs)
```

### Configuration Files

Configuration typically comes early (defines constants/settings used elsewhere):
```
Config.fs       (first - defines settings)
DataAccess.fs   (uses Config)
```

## PR Body Review Order Override

If PR body contains review order instructions, use that instead:

**PR Body Example:**
```markdown
## Review Order

Please review in this order for context:
1. `docs/design.md` - Understand the design first
2. `DataStructures.fs` - See new types
3. `Implementation.fs` - See implementation
4. `Tests.fs` - See test coverage

## Summary
...
```

**When this exists:**
- Use the specified order exactly
- Note in summary that order is per PR author's guidance
- Still provide dependency insights in focus areas section

## Summary Checklist

When determining dependency order:

- [ ] Built dependency graph from imports/using statements
- [ ] Identified type definitions and placed before usage
- [ ] Analyzed function call graph
- [ ] Grouped by architectural layer
- [ ] Handled circular dependencies appropriately
- [ ] Checked for PR body review order override
- [ ] Verified order makes logical sense for reviewer
- [ ] Noted any unusual ordering decisions in summary
