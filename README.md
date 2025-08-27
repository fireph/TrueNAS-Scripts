# TrueNAS Scripts

Utility scripts for TrueNAS Scale administration and automation.

## Scripts

### update-apps.sh

Automates application updates via the TrueNAS Scale API with Plex session detection to avoid interrupting active streams.

**Usage:**
```bash
./update-apps.sh --api-key your-api-key
```

**Key Options:**
- `--dry-run` - Preview updates without executing
- `--force` - Update even with active Plex sessions  
- `--wait` - Wait for each update to complete
- `--skip-plex-check` - Disable Plex session detection

**Requirements:** TrueNAS API key, `jq` package

## Setup

1. Create API key: TrueNAS Web UI → User Icon → My API Keys → Add
2. Install dependencies: `apt install jq curl` (Debian/Ubuntu)
3. Make executable: `chmod +x update-apps.sh`

## License

MIT License - see [LICENSE](LICENSE) file.