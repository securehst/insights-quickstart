# Brand Assets

Replace the placeholder files in this directory with your own brand assets:

- **`logo.png`** — Your company logo (recommended: 300x50px, transparent PNG)
- **`favicon.png`** — Your favicon (recommended: 32x32px or 64x64px PNG)

These files are automatically mounted into the container at the correct path. No environment variables are needed — just replace the files and restart.

To use a different image path, override `SUPERSET_APP_ICON` or `SUPERSET_FAVICON` in your `.env` file.
