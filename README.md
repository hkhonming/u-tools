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

## GitHub Workflows

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

## Commit Categorization

Use `-c/--categorize` to classify every commit on top of the base Ubuntu
kernel. The feature lives in `lib/categorize.awk` (rules) and
`lib/categorize.sh` (data gathering and rendering) and works with plain
POSIX awk (`awk`, `mawk`, `busybox awk`; override via the `AWK` env var).

```bash
./compare-ubuntu-kernel.sh -f text \
    --repo /path/to/linux-qcom -c \
    --category-config categories/linux-qcom.conf \
    --upstream-ref origin/master origin/master-next 7.0
```

### New options

| Option | Description |
|--------|-------------|
| `-c`, `--categorize` | Add a "Commits per category" section to every output format |
| `--category-config FILE` | Custom rules/aliases file (see below) |
| `--list-commits` | With `-c`: also list each commit (short sha, category, subject) |
| `--repo PATH` | Analyse an existing repository instead of cloning; positional args become `<git ref> <version>` |
| `--base-sha SHA` | Skip base detection and use this commit as the base |
| `--base-tag TAG` | Resolve TAG and use it as the base |
| `--upstream-ref REF` | Ref containing upstream commits, used to verify `(cherry picked from commit ...)` references |
| `--no-merges` | Exclude merge commits from the analysis |

Base detection finds the first commit whose subject starts with
`UBUNTU: Ubuntu-<version>` literally (a digit must follow `Ubuntu-`, so
`Ubuntu-qcom-...` releases are never picked as the base). Without `-c` the
default output is unchanged.

### Built-in categories (first match wins)

1. **Merge** – commit with more than one parent (skipped entirely with `--no-merges`)
2. **Revert** – subject starts with ``Revert "``; subcategory = category of the reverted subject
3. Custom config rules (file order)
4. **Release** `^UBUNTU: Ubuntu-` · **Config** `^UBUNTU: [Config]` ·
   **Packaging** `^UBUNTU: [(Packaging|Debian)]`, `^UBUNTU: Start new release`, `^UBUNTU: link-to-tracker` ·
   **SAUCE** `^UBUNTU: SAUCE:` or `^UBUNTU: [SAUCE]` · **Ubuntu (other)** `^UBUNTU:` ·
   **FROMLIST** `^FROMLIST:` · **FROMGIT** `^FROMGIT:` · **BACKPORT** `^BACKPORT:` · **UPSTREAM** `^UPSTREAM:`
5. Otherwise, if the commit body has a `(cherry picked|backported) from commit <sha>` trailer:
   **Upstream (dup of base)** (sha already in the base), **Upstream (verified)**
   (sha reachable from `--upstream-ref`), else **Cherry-pick (unverified)**
6. **Uncategorized**

For FROMGIT/BACKPORT/UPSTREAM commits, `--upstream-ref` also adds a
"ref not found" subcategory when the referenced sha is missing or not
reachable from that ref.

### Category config format

`#` comments and blank lines are ignored; an invalid line aborts with
`config error line N` (exit 1):

```
inherit_defaults=yes      # keep built-in rules after custom ones (default yes)
alias|FROMLOST:|FROMLIST:  # rewrite subject prefix FROM -> TO before matching
Name|subject|^QCLINUX:     # custom rule matching the commit subject (ERE)
Name|body|some.*pattern    # custom rule matching the body collapsed to one line
```

See `categories/linux-qcom.conf` for a real example. Alias applications are
counted and reported ("Aliased: A -> B (n)"). JSON output gains
`commits_per_category` and `aliases` keys (plus `commits` with
`--list-commits`).

### Tests

```bash
tests/run-tests.sh   # builds a synthetic repo; runs under awk, mawk, busybox awk
```

## License

See [LICENSE](LICENSE) file for details.
