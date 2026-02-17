# Example: Interactive Branch Comparison Review - `main...feature-validation-improvements`

## Phase 1: Initial Overview

> User: "Review changes from main to feature-validation-improvements"

# Code Review Summary

Refactors input validation in ValidationComparison to use Result types consistently and adds comprehensive error reporting for invalid comparison parameters. Extracts validation logic into a dedicated module for testability and adds property-based tests.

## Files Changed (in dependency order)
1. **`ValidationComparison/DataStructures.fs`** - Adds error discriminated union types for validation failures and expands comparison parameters record with validation rules.
2. **`ValidationComparison/Validation.fs`** - New module with pure validation functions extracted from Program.fs for testability.
3. **`ValidationComparison/DataAssembly.fs`** - Updates database query functions to return Result types instead of throwing exceptions.
4. **`ValidationComparison/ValidationComparisonSpec.fs`** - Adds comprehensive test coverage including property-based tests for validation functions.
5. **`ValidationComparison/Program.fs`** - Refactors CLI argument processing to use Validation module with detailed error messages.

Say **next** to begin walking through individual changes.

---

## Phase 2: Walkthrough

> User: "next"

## `ValidationComparison/DataStructures.fs`
Adds a new `ValidationError` discriminated union to represent all failure modes, and extends `ComparisonParameters` with configurable validation constraints (`minSampleSize`, `maxDateRange`).

### Type: `ValidationError`

```diff
+type ValidationError =
+  | InvalidDateRange of string
+  | MissingWeatherData of string
+  | InsufficientSampleSize of actual: int * required: int
+  | ConfigurationError of string
```

New discriminated union covering all validation failure modes with descriptive payloads.

---

> User: "next"

### Type: `ComparisonParameters`

```diff
 type ComparisonParameters = {
   StartDate: LocalDate
   EndDate: LocalDate
   ForecastPoint: ForecastPointId
+  MinSampleSize: int
+  MaxDateRange: Period
 }
```

Adds `MinSampleSize` (default: 30) and `MaxDateRange` (default: 10 years) fields to enforce statistical validity constraints.

---

> User: "next"

## `ValidationComparison/Validation.fs`
New module containing three pure validation functions extracted from Program.fs. Uses Result types and error accumulation via `Result.combine` so all validation failures are reported at once rather than short-circuiting.

### Function: `validateDateRange: LocalDate -> LocalDate -> ResultTrace<unit, ValidationError>`

Validates that date range is positive, not in the future, and within the maximum allowed range.

---

> User: "next"

### Function: `validateSampleSize: int -> int -> ResultTrace<unit, ValidationError>`

```diff
+let validateSampleSize (actual: int) (required: int) =
+  if actual >= required then Ok ()
+  else Error (InsufficientSampleSize (actual, required))
```

Checks that sample size meets minimum threshold for statistical significance.

---

> User: "next"

### Function: `validateAll: ComparisonParameters -> ResultTrace<unit, ValidationError list>`

Composes all validation functions using `Result.combine`, collecting all errors rather than short-circuiting on first failure.

---

> User: "next"

## `ValidationComparison/DataAssembly.fs`
Changes the data retrieval function from throwing exceptions on missing data to returning `Error MissingWeatherData` with details about which dates/points are missing.

### Function: `retrieveWeatherData: ForecastPointId -> DateRange -> HubContext -> io<ResultTrace<WeatherData list, ValidationError>>`

Changed from throwing on missing data to returning `Error MissingWeatherData` with details about which dates/points are missing.

⚠️ **Breaking change**: Signature changed from returning `WeatherData list` to `ResultTrace<WeatherData list, ValidationError>`. All call sites must be updated to handle the Result type.

---

> User: "next"

## `ValidationComparison/ValidationComparisonSpec.fs`
Adds three test groups covering boundary conditions, threshold enforcement, and error accumulation using property-based testing.

### Test: `validateDateRange handles edge cases correctly`

Covers boundary conditions: same-day range, leap years, timezone boundaries, future dates.

---

> User: "next"

### Test: `validateSampleSize enforces minimum threshold`

Verifies rejection of insufficient samples and acceptance of valid sample sizes.

---

> User: "next"

### Test: `validateAll accumulates multiple errors`

Property test ensuring all validation errors are collected when multiple validations fail simultaneously.

---

> User: "next"

## `ValidationComparison/Program.fs`
Refactors argument processing to use the new Validation module and formats all validation errors for user-friendly display on early exit.

### Function: `parseAndValidateArgs: string[] -> ResultTrace<ComparisonParameters, ValidationError list>`

Updated to call `Validation.validateAll` and format error messages for user display.

---

> User: "next"

### Function: `main: argv -> int`

Adds early exit on validation failure with formatted error output showing all validation issues at once.

Review complete.
