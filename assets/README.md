# Brand Assets

Replace the placeholder files in this directory with your own brand assets:

- **`logo.png`** — Your company logo (recommended: 300×50px, transparent PNG)
- **`favicon.png`** — Your favicon (recommended: 32×32px or 64×64px PNG)

Then set the following in your `.env` file:

```bash
SUPERSET_APP_ICON=/app/superset_home/assets/logo.png
SUPERSET_FAVICON=/app/superset_home/assets/favicon.png
```

The `assets/` directory is mounted into the container at `/app/superset_home/assets/`, making your files accessible to Superset at runtime.
