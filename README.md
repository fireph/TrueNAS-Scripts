# TrueNAS Scripts

Utility scripts for TrueNAS Scale administration and automation.

## Scripts

### update-apps.sh

Automates application updates via the TrueNAS Scale API with Plex session detection to avoid interrupting active streams.

#### Usage

Pull and execute in one line:
```bash
curl -s https://raw.githubusercontent.com/your-username/TrueNAS-Scripts/main/update-apps.sh | bash -s -- --api-key your-api-key
```

Or download and run:
```bash
wget https://raw.githubusercontent.com/your-username/TrueNAS-Scripts/main/update-apps.sh
chmod +x update-apps.sh
./update-apps.sh --api-key your-api-key
```

#### Key Options
- `--dry-run` - Preview updates without executing
- `--force` - Update even with active Plex sessions  
- `--wait` - Wait for each update to complete
- `--skip-plex-check` - Disable Plex session detection

#### Setup

Create API key: TrueNAS Web UI → User Icon → My API Keys → Add

## License

MIT License - see [LICENSE](LICENSE) file.