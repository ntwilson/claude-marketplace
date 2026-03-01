# Dependency Analysis Patterns

This reference provides detailed strategies for determining dependency order in code reviews.

## Core Principle

**Callees before callers**: A function should be presented before any function that calls it. This allows reviewers to understand lower-level building blocks before seeing how they're composed.

## F# Dependency Order Shortcuts

**For F# projects, dependency analysis is significantly simpler** because the language and project system enforce dependency order:

### Within a Project: Read the .fsproj File

The `.fsproj` file lists all `.fs` files in dependency order. You can simply use this ordering directly:

```xml
<ItemGroup>
  <Compile Include="DataStructures.fs" />
  <Compile Include="Validation.fs" />
  <Compile Include="BusinessLogic.fs" />
  <Compile Include="Program.fs" />
</ItemGroup>
```

**Result:** Present files in the exact order they appear in the `.fsproj` file.

### Between Projects: Check .fsproj References

Project dependencies are declared explicitly in `.fsproj` files:

```xml
<ItemGroup>
  <ProjectReference Include="..\DataLayer\DataLayer.fsproj" />
  <ProjectReference Include="..\BusinessLayer\BusinessLayer.fsproj" />
</ItemGroup>
```

**Result:** Present projects in dependency order based on `ProjectReference` elements.

### F# Review Strategy Summary

For F# codebases, instead of complex dependency analysis:

1. **Read the .fsproj file(s)** to get file ordering
2. **List changed files** in the order they appear in .fsproj
3. **Within each file**, present changes in the order they appear
4. **Done** - no call graph analysis, import tracking, or topological sorting needed

**This approach is faster, simpler, and guaranteed to be correct** because it leverages the F# compiler's own dependency enforcement.

## Dependency Analysis Strategies (For Non-F# Languages)

### Strategy 1: Import/Using Analysis

Examine import statements to build a dependency graph:

**PureScript Example:**
```purescript
-- File A: DataStructures.purs
type User = { id :: Int, name :: String }

-- File B: Validation.purs
import GasDay.DataStructures (User)  -- Depends on A

validateUser :: User -> ...
validateUser user = ...

-- File C: UserService.purs
import GasDay.DataStructures (User)      -- Depends on A
import GasDay.Validation (validateUser)  -- Depends on B

createUser String -> ...
createUser name = ...
```

**Dependency order:** A → B → C

### Strategy 2: Type Dependency Analysis

Functions that define types come before functions that use those types:

**PureScript Example:**
```purescript
-- Comes first: Type definition
data ValidationError 
  = InvalidInput String
  | MissingData

-- Comes second: Function using the type
validateInput :: String -> Either ValidationError String
validateInput x = ...

-- Comes third: Function using Result type
processInput :: String -> Effect Unit
processInput x =
  case validateInput x of
    Right value -> doSomething value
    Left err -> handleError err
```

### Strategy 3: Call Graph Analysis

Build a call graph by identifying function calls:

**Example:**
```purescript
-- Level 1: Leaf functions (call nothing)
formatDate :: Date -> String
formatDate = format [Year, Placeholder "-", MonthTwoDigit, Placeholder "-", DayTwoDigit]

formatName String -> String
formatName = String.trim >>> String.upper

-- Level 2: Functions calling level 1
formatUser User -> String
formatUser user =
  formatName user.name <> " " <> formatDate user.createdDate

-- Level 3: Functions calling level 2
generateReport :: ∀ f. Foldable f => f User -> String
generateReport users =
  users <#> formatUser # String.joinWith "\n"
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
DataStructures.purs    (Layer 1)
Utils.purs             (Layer 2)
DataAssembly.purs      (Layer 3)
Validation.purs        (Layer 4)
BusinessLogic.purs     (Layer 4)
Workflows.purs         (Layer 5)
Program.purs           (Layer 6)
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
- `DataStructures.purs` - Added new type `CacheKey`
- `CacheManager.purs` - New file using `CacheKey`
- `DataAssembly.purs` - Modified to use `CacheManager`
- `Program.purs` - Initializes cache from `CacheManager`

**Dependency order:**
1. DataStructures.purs (defines CacheKey)
2. CacheManager.purs (uses CacheKey)
3. DataAssembly.purs (uses CacheManager)
4. Program.purs (orchestrates everything)

### Example 2: Bug Fix PR

**Files changed:**
- `Validation.purs` - Fixed validation logic
- `UserService.purs` - Updated to handle new validation behavior
- `UserServiceSpec.purs` - Added test coverage

**Dependency order:**
1. Validation.purs (core fix)
2. UserService.purs (adapts to fix)
3. UserServiceSpec.purs (tests the adapted behavior)

### Example 3: Feature Addition

**Files changed:**
- `DataStructures.purs` - New types for feature
- `Utils.purs` - Helper functions for feature
- `ApiClient.purs` - API integration
- `BusinessLogic.purs` - Feature implementation
- `Program.purs` - CLI command for feature

**Dependency order:**
1. DataStructures.purs
2. Utils.purs
3. ApiClient.purs
4. BusinessLogic.purs
5. Program.purs

## Edge Cases

### Self-Contained Files

Files with no external dependencies can appear in any order, but typically:
- Group by functionality
- Place utilities early
- Place tests near what they test

### Test Files

Test files typically come after the code they test:
```
BusinessLogic.purs
BusinessLogicSpec.purs  (tests BusinessLogic.purs)
```

### Configuration Files

Configuration typically comes early (defines constants/settings used elsewhere):
```
Config.purs       (first - defines settings)
DataAccess.purs   (uses Config)
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
