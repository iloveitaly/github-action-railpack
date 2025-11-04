# Example RailPack Project

This is a simple example project that demonstrates how to use the RailPack GitHub Action.

## Files

- `main.sh` - A simple bash script that prints "Hello World"
- `Procfile` - Tells RailPack how to run the application

## How it works

The GitHub workflow in `.github/workflows/example.yml` builds this example project using the RailPack action defined in this repository.

## Testing locally

If you have RailPack installed, you can build this locally:

```bash
cd example
railpack build .
```
