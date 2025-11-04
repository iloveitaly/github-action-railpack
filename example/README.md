# Example RailPack Shell Script Project

This is a simple shell script example project that demonstrates how to use the RailPack GitHub Action.

## Files

- `start.sh` - A simple bash script that prints "Hello World" (RailPack auto-detects this)
- `Procfile` - Tells RailPack how to run the application
- `main.sh` - Alternative example script

## How it works

The GitHub workflow in `.github/workflows/example.yml` builds this example project using the RailPack action defined in this repository. RailPack automatically detects this as a shell script project because of the `start.sh` file.

## Testing locally

If you have RailPack installed, you can build this locally:

```bash
cd example
railpack build .
```
