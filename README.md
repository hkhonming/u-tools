# u-tools

Utility tools for comparing Ubuntu kernel derivatives.

## Tools

### compare-ubuntu-kernel.sh

A script to compare Ubuntu kernel derivatives against their base Ubuntu kernel version.

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

**Config File Format:**

The config file should be a JSON array containing kernel configuration objects:

```json
[
  {
    "name": "Raspberry Pi 5 6.8",
    "git_url": "https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/noble",
    "branch": "master-next",
    "kernel_version": "6.8.0-1017.18"
  },
  {
    "name": "Raspberry Pi 5 6.11",
    "git_url": "https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/oracular",
    "branch": "master-next",
    "kernel_version": "6.11.0-1009.10"
  }
]
```

**Using the Workflow:**

1. **With default sample config:**
   - Go to Actions tab in GitHub
   - Select "Compare Multiple Ubuntu Kernels"
   - Click "Run workflow"
   - Leave config_url empty to use `sample-config.json`
   - Select output format (markdown or csv)
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

Results are available as workflow artifacts and displayed in the workflow output.

## Example Configurations

The repository includes sample configuration files:

- `sample-config.json`: Basic example with 2 Raspberry Pi kernel configurations
- `example-configs.json`: Extended example with multiple kernel types (Raspberry Pi, Intel IoT, NVIDIA Tegra)

### Raspberry Pi Kernels
```json
[
  {
    "name": "Raspberry Pi 5 Noble (6.8)",
    "git_url": "https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/noble",
    "branch": "master-next",
    "kernel_version": "6.8.0-1017.18"
  },
  {
    "name": "Raspberry Pi 5 Oracular (6.11)",
    "git_url": "https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux-raspi/+git/oracular",
    "branch": "master-next",
    "kernel_version": "6.11.0-1009.10"
  }
]
```

### Multiple Kernel Types
See `example-configs.json` for a configuration that compares Raspberry Pi, Intel IoT, and NVIDIA Tegra kernels side-by-side.

## License

See [LICENSE](LICENSE) file for details.
