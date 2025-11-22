# Dependency Patches

This directory contains patches that are automatically applied to external dependencies during the build process.

## Structure

```
patches/
├── libosmocore/
│   └── 0001-make-sctp-include-conditional.patch
└── <dependency-name>/
    └── <patch-files>.patch
```

## How It Works

The `build.sh` script's `build_dependency()` function automatically:
1. Clones or updates the dependency repository
2. Looks for patches in `patches/<dependency-name>/`
3. Applies all `.patch` files in alphanumeric order
4. Builds and installs the patched dependency

## Patch Naming Convention

Patches should be named with a numeric prefix for ordering:
- `0001-description.patch` - First patch
- `0002-description.patch` - Second patch
- etc.

## Creating Patches

Patches should be in unified diff format (`diff -u` or `git diff`):

```bash
# Example: Create a patch from git diff
cd deps/libosmocore
git diff > /path/to/osmo-remsim/patches/libosmocore/0001-my-patch.patch
```

## Existing Patches

### libosmocore

#### 0001-make-sctp-include-conditional.patch
- **Purpose**: Fix OpenWRT build failure due to missing `netinet/sctp.h`
- **Details**: Makes the SCTP header include conditional on `HAVE_LIBSCTP` being defined
- **Affects**: `src/core/osmo_io_internal.h` and `src/core/osmo_io_uring.c`
- **When applied**: Always (harmless on systems with SCTP support)

## Notes

- Patches are reapplied on every build (repository is reset first)
- Failed patch application will stop the build process
- Patches are only applied during dependency builds, not for osmo-remsim itself
