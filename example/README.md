# Example RailPack Project

This is a simple example project that demonstrates how to use the RailPack GitHub Action.

## Files

- `index.js` - A simple Node.js application that prints "Hello World"
- `package.json` - Node.js project configuration
- `Procfile` - Tells RailPack how to run the application
- `main.sh` - Alternative bash script (not used by default)

## How it works

The GitHub workflow in `.github/workflows/example.yml` builds this example project using the RailPack action defined in this repository. RailPack automatically detects this as a Node.js project and builds it accordingly.

## Testing locally

If you have RailPack installed, you can build this locally:

```bash
cd example
railpack build .
```
