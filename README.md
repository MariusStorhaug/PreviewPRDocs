# PreviewPRDocs

GitHub Pages demo that keeps **live** content on the default URL while publishing **PR previews** on isolated URLs.

## Behavior

- Push to `main` updates live site at:
  - `https://mariusstorhaug.github.io/PreviewPRDocs/`
- Pull request updates publish preview at:
  - `https://mariusstorhaug.github.io/PreviewPRDocs/previews/pr-<number>/`
- Closing a PR removes its preview folder automatically.

## Zensical integration

This template currently copies `site/` into `_site/` for deployment using PowerShell workflow steps.
Replace the build step in both workflow files with your Zensical command that outputs to `_site/`.
