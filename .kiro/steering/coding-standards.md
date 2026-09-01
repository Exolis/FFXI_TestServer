---
inclusion: auto
---

# LandSandBoat Coding Standards

## C++ Style

- **Naming**: UpperCamelCase for namespaced functions/classes, UPPER_SNAKE_CASE for enums, lowerCamelCase for everything else
- **Braces**: Allman style (braces on new line)
- **Indentation**: 4 spaces, no tabs
- **Pointers**: Left-aligned (`CBigType* type`, not `CBigType *type`)
- **Casting**: Use `static_cast<>` over C-style casts; use `dynamic_cast<>` for downcasts
- **Includes**: Sorted alphabetically in logical blocks
- **Conditionals**: Always use braces, even for single-line bodies
- **Line breaks between consecutive if/else blocks**
- **Wide conditionals**: Break after the operator (`&&`, `||`)
- **Lambdas**: Wrap in `// clang-format off/on` blocks

## Lua Style

- **Naming**: lowerCamelCase for functions and members
- **Variables**: Always use `local` unless intentionally global
- **Tables**: Allman style for multi-line, trailing comma on last entry
- **Conditionals**: No parentheses unless needed for clarity; long conditions use multi-line format with `and`/`or` at end of line, `then` on its own line
- **No semicolons**
- **No single-line functions or conditions**
- **Inline tables**: Exception to brace rules when passing tables as function arguments
- **Spacing**: Space after commas, around operators, after `if`/`while`/`for` keywords
- **Newline after `end`** before next statement at same indentation

### Lua Conditional Format
```lua
-- Short condition
if condition then
    action()
end

-- Long/multiple conditions
if
    condition1 and
    condition2 or
    not condition3
then
    action()
end
```

### Lua Table Format
```lua
-- Multi-line (Allman)
local myTable =
{
    key1 = value1,
    key2 = value2,
}

-- Single-line (short tables)
local coords = { 1, 2, 3, 4 }
```

## SQL Style

- No quotes around numeric fields
- No line breaks mid-statement
- Uppercase SQL keywords (`INSERT INTO`, not `insert into`)
- Add comments for non-obvious entries: `-- (Mob Name) item_name`
- Comment out incomplete/placeholder rows rather than using dummy data

## General

- Use the STL freely in C++
- Prefer `npcUtil` helpers in Lua for trades, item giving, key items
- Dynamic entities use `zone:insertDynamicEntity({...})` pattern
- Campaign currency: `player:getCurrency('allied_notes')` / `player:addCurrency('allied_notes', amount)`
- Player variables: `player:getCharVar('name')` / `player:setCharVar('name', value)`
- Zone variables: `zone:getLocalVar('name')` / `zone:setLocalVar('name', value)`
