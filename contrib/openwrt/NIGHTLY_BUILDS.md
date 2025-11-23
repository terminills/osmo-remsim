# Nightly IPK Builds

The osmo-remsim project provides automated nightly builds of OpenWRT IPK packages through GitHub Actions.

## Accessing Nightly Builds

Nightly builds are automatically generated every day at 2 AM UTC and are available as GitHub Actions artifacts.

### Download from GitHub Actions

1. Go to the repository on GitHub
2. Click the "Actions" tab
3. Select "Nightly IPK Build" from the workflows list
4. Click on the latest successful workflow run
5. Scroll down to the "Artifacts" section
6. Download the IPK package archive for your architecture:
   - `ipk-packages-23.05.6-mediatek-filogic-<run-number>` - For MediaTek MT7986 (aarch64)

The archive contains:
- Dependency packages: `libtalloc`, `libosmocore`, `libosmo-gsm`, `libosmo-netif`
- Main packages: `osmo-remsim-client`, `luci-app-remsim`
- Build information: `BUILD_INFO.txt`

### Retention Policy

Nightly build artifacts are retained for **90 days** from the build date.

## Manual Trigger

You can manually trigger a build at any time:

1. Go to the Nightly IPK Build workflow (Actions tab → Nightly IPK Build)
2. Click on "Run workflow"
3. Select the branch (usually `main` or `master`)
4. Click "Run workflow"

The build typically takes 10-15 minutes to complete.

## Supported Platforms

Currently, nightly builds are generated for:

- **MediaTek Filogic (MT7986)** - OpenWRT 23.05.6
  - Architecture: aarch64_cortex-a53
  - Devices: ZBT Z8102AX V2, GL.iNet MT3000, and other MT7986-based routers

## Installation

To install packages from a nightly build:

1. Download and extract the artifact archive
2. Transfer IPK files to your router:
   ```bash
   scp *.ipk root@router:/tmp/
   ```
3. SSH to your router and install:
   ```bash
   ssh root@router
   opkg update
   
   # Install dependencies
   opkg install /tmp/libtalloc_*.ipk
   opkg install /tmp/libosmocore_*.ipk /tmp/libosmo-gsm_*.ipk
   opkg install /tmp/libosmo-netif_*.ipk
   
   # Install main packages
   opkg install /tmp/osmo-remsim-client_*.ipk
   opkg install /tmp/luci-app-remsim_*.ipk
   ```

See [INSTALL.md](INSTALL.md) for detailed installation instructions.

## Build Information

Each nightly build includes a `BUILD_INFO.txt` file with:
- Build date and time
- Git commit hash
- Git branch
- SDK version used
- List of packages built with sizes

## Building Your Own

If you need to build packages yourself or for a different architecture:

1. See [README.md](README.md) for build instructions
2. Use the `build-ipk.sh` script for automated building
3. Or follow the manual build steps in the README

## Workflow Details

The nightly build workflow:
- Runs daily at 2 AM UTC
- Uses the OpenWRT SDK 23.05.6
- Builds all packages (dependencies + main packages)
- Uploads artifacts with 90-day retention
- Can be manually triggered on demand

Workflow file: `.github/workflows/nightly-ipk-build.yml`

## Support

For issues with nightly builds:
- Check the workflow runs (Actions tab → Nightly IPK Build) for build logs
- Report issues on GitHub Issues
- For general support, see the main [README](../../README.md)
