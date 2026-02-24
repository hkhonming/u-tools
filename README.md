# u-tools

Utility tools for comparing Ubuntu kernel derivatives.

## Tools

### compare-ubuntu-kernel.sh

A script to compare Ubuntu kernel derivatives against their base Ubuntu kernel version.

This tool provides:
- Overall commit count and diff statistics
- **Per-folder breakdown** showing which directories have the most changes (e.g., drivers/, Documentation/, arch/)
- Multiple output formats for different use cases

**Usage:**
```bash
./compare-ubuntu-kernel.sh [OPTIONS] <Ubuntu source tree> <git branch> <Ubuntu kernel version>
```

**Options:**
- `-f, --format <format>`: Output format (text, json, csv, markdown). Default: text
- `-h, --help`: Show help message

**Examples:**
```bash
# Text format (default) - includes per-folder breakdown
./compare-ubuntu-kernel.sh https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/noble master-next 6.8.0-1017.18

# CSV format for easy parsing - includes per-folder data
./compare-ubuntu-kernel.sh -f csv https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/noble master-next 6.8.0-1017.18

# Markdown format for reports - includes per-folder table
./compare-ubuntu-kernel.sh -f markdown https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/noble master-next 6.8.0-1017.18
```

**Output Features:**

The script now provides detailed per-folder analysis to help understand where changes are concentrated:

- **Overall statistics**: Total files changed, insertions, and deletions
- **Per-folder breakdown**: Shows changes grouped by top-level directory (e.g., drivers/, arch/, Documentation/)
  - Provides a high-level overview of which subsystems are affected
  - Sorted by number of files changed (most active directories first)
- **Detailed per-folder breakdown**: Shows subdirectory-level changes
  - 2 levels deep for most directories (e.g., drivers/net/, drivers/usb/)
  - 4 levels deep for arch/ directory (e.g., arch/arm64/boot/dts/)
  - Helps identify specific subsystems and hardware support changes
  - Available in all output formats (text, JSON, CSV, markdown)

### track-upstream-kernel.sh

A script to track changes between upstream Linux kernel RC releases, filtered by
folder paths or commit-message patterns defined in a JSON config file.

**Usage:**
```bash
./track-upstream-kernel.sh [OPTIONS] <kernel_repo> <from_tag> <to_tag>
```

**Options:**
- `-c, --config <file>`: JSON config file with folder/commit-message filters (optional)
- `-f, --format <format>`: Output format (text, json, markdown). Default: text
- `-h, --help`: Show help message

**Examples:**
```bash
# Compare v6.15-rc1 → v6.15-rc2, filter by config, output markdown
./track-upstream-kernel.sh \
  -f markdown \
  -c upstream-kernel-config.json \
  https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git \
  v6.15-rc1 v6.15-rc2

# No filter config – show overall stats only
./track-upstream-kernel.sh \
  https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git \
  v6.15-rc1 v6.15-rc2
```

**Config File Format (`upstream-kernel-config.json`):**

```json
{
  "filters": [
    {
      "name": "ARM64 architecture changes",
      "type": "folder",
      "paths": ["arch/arm64/"]
    },
    {
      "name": "Security and CVE fixes",
      "type": "commit_message",
      "patterns": ["CVE-", "security fix", "vulnerability"]
    }
  ]
}
```

Each filter entry requires:
- `name`: Human-readable label shown in the report
- `type`: Either `"folder"` or `"commit_message"`
- `paths` *(folder type)*: List of directory prefixes to include in the diff
- `patterns` *(commit_message type)*: List of strings to match against commit subjects/bodies

## GitHub Workflows

### Track Upstream Linux Kernel RC

**Workflow:** `.github/workflows/track-upstream-kernel.yaml`

Monitor upstream Linux kernel RC releases and report changes that match filter
rules defined in a JSON config file.

**Schedule:** Runs automatically every Monday at 06:00 UTC.  Can also be
triggered manually via the Actions tab.

**Inputs (manual trigger):**
- `kernel_repo`: Upstream kernel Git URL (default: torvalds/linux)
- `from_tag`: Base tag to compare from (e.g. `v6.15-rc1`). Auto-detected when left empty.
- `to_tag`: Target RC tag (e.g. `v6.15-rc2`). Auto-detected (latest RC) when left empty.
- `config_url`: URL to a JSON filter config file. Uses `upstream-kernel-config.json` if not provided.
- `format`: Output format – markdown (default), json, or text.

**Auto-detection logic:**
- `to_tag` defaults to the newest RC tag found in the kernel repo.
- `from_tag` defaults to the RC tag immediately before `to_tag`, or the base
  release tag (e.g. `v6.15`) if `to_tag` is `rc1`.

**Output:**
- Overall commit count and diff statistics between the two RC tags.
- Per-filter results showing either diff stats for monitored folders or a list
  of commits matching the provided patterns.
- Report uploaded as a workflow artifact (30-day retention).

### Compare Ubuntu Kernel (Single)

**Workflow:** `.github/workflows/compare-kernel.yaml`

Compare a single Ubuntu kernel derivative against its base version.

**Inputs:**
- `git_url`: Git URL for kernel code (required)
- `branch`: Git branch (required)
- `kernel_version`: Base Ubuntu kernel version (required)
- `format`: Output format - text, json, csv, or markdown (optional, default: text)
- `artifact_name`: Output artifact name (optional, default: kernel-diff)

### Compare Multiple Ubuntu Kernels

**Workflow:** `.github/workflows/compare-kernel-multi.yaml`

Compare multiple Ubuntu kernel derivatives in a single workflow run and generate a combined comparison table.

**Inputs:**
- `config_url`: URL to config.tgz or config.json file (optional - uses sample-config.json if not provided)
- `output_format`: Output format for comparison table - markdown or csv (optional, default: markdown)
- `publish_to_pages`: Publish results to GitHub Pages for easy web access (optional, default: false)

**Config File Format:**

The config file should be a JSON array containing kernel configuration objects:

```json
[
  {
    "name": "Raspberry Pi Noble 6.8",
    "git_url": "https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/noble",
    "branch": "master-next",
    "kernel_version": "6.8.0-1017.18"
  },
  {
    "name": "Intel IoT Noble 6.8",
    "git_url": "https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-intel-iotg/+git/noble",
    "branch": "master-next",
    "kernel_version": "6.8.0-1015.22"
  }
]
```

**Using the Workflow:**

1. **With default sample config:**
   - Go to Actions tab in GitHub
   - Select "Compare Multiple Ubuntu Kernels"
   - Click "Run workflow"
   - Leave config_url empty to use `sample-config.json` (includes 4 kernel configs by default)
   - Select output format (markdown or csv)
   - Optionally enable "Publish to GitHub Pages" to make results accessible via web
   - Click "Run workflow"

2. **With custom config URL:**
   - Prepare your config file (JSON format or tgz archive containing JSON)
   - Host it on an accessible URL
   - Go to Actions tab in GitHub
   - Select "Compare Multiple Ubuntu Kernels"
   - Click "Run workflow"
   - Enter your config URL in `config_url` field
   - Select output format
   - Click "Run workflow"

3. **With local config file:**
   - Update `sample-config.json` in the repository
   - Commit and push changes
   - Run the workflow without specifying config_url

**Output:**

The workflow generates a combined comparison table showing:
- Configuration name
- Git URL
- Branch
- Base Ubuntu version
- Base commit SHA
- Number of commits on top of base
- Files changed
- Lines inserted
- Lines deleted
- **Generation timestamp** (date and time the report was created)

Results are available in multiple ways:
- **Workflow artifacts**: Download from Actions tab (30-day retention)
- **GitHub Pages** (if enabled): Accessible at `https://<username>.github.io/<repo>/`
- **Workflow output**: View directly in the Actions run logs

**Note:** The default `sample-config.json` includes 25 kernel configurations covering multiple kernel types:
- Raspberry Pi kernels (3 configs: focal, jammy, noble)
- RISC-V kernels (2 configs: noble, questing)
- Intel IoT kernels (1 config: jammy)
- Bluefield kernels (3 configs: focal, jammy, noble)
- NVIDIA/NVIDIA Tegra kernels (6 configs: jammy, noble with various versions)
- Xilinx kernels (3 configs: focal, jammy, noble)
- MediaTek kernels (1 config: jammy)
- Qualcomm kernels (1 config: noble)
- Cloud kernels: AWS, Oracle, GCP, Azure, IBM (5 configs: all noble)

## Example Configuration

The repository includes `sample-config.json` which demonstrates a comprehensive comparison with various kernel types:

```json
[
  {
    "git_url": "https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/focal",
    "branch": "master-next",
    "kernel_version": "5.4",
    "name": "linux-raspi-focal"
  },
  {
    "git_url": "https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/jammy",
    "branch": "master-next",
    "kernel_version": "5.15",
    "name": "linux-raspi-jammy"
  },
  {
    "git_url": "https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/noble",
    "branch": "master-next",
    "kernel_version": "6.8",
    "name": "linux-raspi-noble"
  }
  // ... and 22 more kernel configurations
]
```

## License

See [LICENSE](LICENSE) file for details.
