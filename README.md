# u-tools

Utility tools for comparing Ubuntu kernel derivatives.

## Tools

### compare-ubuntu-kernel.sh

A script to compare Ubuntu kernel derivatives against their base Ubuntu kernel version.

**Features:**
- Identifies the base Ubuntu kernel commit
- Counts commits on top of the base version
- Shows overall diff statistics (files changed, insertions, deletions)
- Provides per-folder difference analysis showing which directories have the most changes

**Usage:**
```bash
./compare-ubuntu-kernel.sh [OPTIONS] <Ubuntu source tree> <git branch> <Ubuntu kernel version>
```

**Options:**
- `-f, --format <format>`: Output format (text, json, csv, markdown). Default: text
- `-h, --help`: Show help message

**Examples:**
```bash
# Text format (default)
./compare-ubuntu-kernel.sh https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/noble master-next 6.8.0-1017.18

# CSV format for easy parsing
./compare-ubuntu-kernel.sh -f csv https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/noble master-next 6.8.0-1017.18

# Markdown format for reports
./compare-ubuntu-kernel.sh -f markdown https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/noble master-next 6.8.0-1017.18
```

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

## License

See [LICENSE](LICENSE) file for details.
