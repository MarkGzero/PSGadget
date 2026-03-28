# Contributing to PSGadget

Thank you for contributing. Please read this document before opening a PR.

---

## Table of Contents

- [Ground rules](#ground-rules)
- [Code rules](#code-rules)
- [File rules](#file-rules)
- [Testing](#testing)
- [Pull request checklist](#pull-request-checklist)

---

## Ground rules

- Open an issue before starting significant work. This avoids duplicate
  effort and makes PRs easier to review.
- One concern per PR. A PR that fixes a bug and adds a feature is harder
  to review and harder to revert if needed.
- All PRs target `main`. There is no separate `dev` branch.

---

## Code rules

These are enforced by CI (PSScriptAnalyzer) and by code review.

### ASCII only

**No Unicode characters anywhere in the codebase.** This includes:
- Code files (`.ps1`, `.psm1`, `.psd1`)
- Comments and strings inside those files
- Markdown documentation files

Permitted ASCII-only status indicators: `[OK]`, `PASS`, `[FAIL]`,
`ERROR`, `->`. No Unicode arrows, check marks, crosses, or emoji.

To check for non-ASCII characters before committing:

```powershell
# Run from the repo root
Get-ChildItem -Recurse -Include *.ps1,*.psm1,*.psd1,*.md |
    ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match '[^\x00-\x7F]') {
            Write-Warning "Non-ASCII found: $($_.FullName)"
        }
    }
```

### PS 5.1 compatibility

All PowerShell code must run on PS 5.1 (.NET Framework 4.8) without errors.

**Forbidden operators (PS 7+ only):**
- Ternary: `condition ? value_if_true : value_if_false`
- Null coalescing: `$x ?? $default`
- Null conditional: `$obj?.Property`
- Pipeline chain operators: `cmd1 && cmd2`, `cmd1 || cmd2`

**Platform checks -- use these exact patterns:**
```powershell
# Check for Windows (PS 5.1 compatible)
if ([System.Environment]::OSVersion.Platform -eq 'Win32NT') { }

# Check PS version
if ($PSVersionTable.PSVersion.Major -le 5) { }
```

**Every new script file must begin with:**
```powershell
#Requires -Version 5.1
```

### Comment-based help

Every function in `Public/` must have a CBH block before the `function`
keyword. Minimum sections: `.SYNOPSIS`, `.DESCRIPTION`, one `.PARAMETER`
per parameter, `.EXAMPLE` (at least one), `.OUTPUTS`.

Run `Get-Help <FunctionName>` locally and verify that synopsis, description,
and examples all render before submitting.

---

## File rules

### Module load order -- do not change PSGadget.psm1

The dot-source order in `PSGadget.psm1` is load-order sensitive. Do not
change it. The order is:

1. `Classes/PsGadgetLogger.ps1` -- must be first; all other classes depend on it
2. `Classes/PsGadgetI2CDevice.ps1`
3. `Classes/PsGadgetSsd1306.ps1`
4. `Classes/PsGadgetFtdi.ps1`
5. `Classes/PsGadgetMpy.ps1`
6. `Classes/PsGadgetPca9685.ps1`
7. All `Private/*.ps1` (glob, alphabetical)
8. All `Public/*.ps1` (glob, alphabetical)

### PSGadget.psd1 export list

Do not add to or remove from `FunctionsToExport` in `PSGadget.psd1` without
a matching new or removed file in `Public/`. The export list and the Public/
directory must stay in sync. If you add a new public function, add both:
1. `Public/Verb-PsGadgetNoun.ps1` (the implementation)
2. A new entry in `FunctionsToExport` in `PSGadget.psd1`

### Layer discipline

Do not put hardware logic (byte arrays, protocol constants, MPSSE opcodes)
in `Public/*.ps1`. Public cmdlets call device-layer methods or private
functions. They do not contain protocol-level code.

Do not call transport functions directly from `Classes/*.ps1`. Classes call
protocol-layer functions from `Private/`.

---

## Testing

### Before submitting

Run the Pester suite locally. All tests must pass:

```powershell
Invoke-Pester ./Tests/PsGadget.Tests.ps1 -Output Detailed
```

The test suite runs in stub mode and does not require hardware.

### With hardware (Windows)

If your change touches GPIO, EEPROM, I2C, or MPSSE logic and you have a
physical FTDI device:

```powershell
. ./Tests/Test-PsGadgetWindows.ps1
```

### PSScriptAnalyzer

Run the linter against any files you changed:

```powershell
$rules = @(
    'PSProvideCommentHelp',
    'PSUseCmdletCorrectly',
    'PSUseOutputTypeCorrectly',
    'PSAvoidUsingWriteHost',
    'PSUseApprovedVerbs',
    'PSUseShouldProcessForStateChangingFunctions'
)
Invoke-ScriptAnalyzer -Path Public/ -IncludeRule $rules -Recurse
```

CI runs the same rules and will fail the PR if any violations are found.

---

## Pull request checklist

Before opening a PR, confirm all of the following:

- [ ] No non-ASCII characters in any changed file
- [ ] All changed .ps1 files begin with `#Requires -Version 5.1`
- [ ] No PS 7-only operators (`?:`, `??`, `?.`, `&&`, `||`)
- [ ] `PSGadget.psm1` load order unchanged
- [ ] `PSGadget.psd1` export list matches `Public/` directory
- [ ] New public functions have CBH (`Get-Help <FunctionName>` shows synopsis)
- [ ] `Invoke-Pester ./Tests/PsGadget.Tests.ps1` passes locally
- [ ] PSScriptAnalyzer reports no violations on changed Public/ files
- [ ] PR description explains the problem being solved and references an issue
