# killport
A simple bash script to kill services listening on ports.

```bash
Kill processes listening on specified port(s).

Usage: killport [OPTIONS] <PORT> [END_PORT]
       killport <PORT>
       killport <START_PORT> <END_PORT>

Options:
  -h, --help     Show this help message
  -l, --list     List processes without killing
  -f, --force    Force kill with SIGKILL (default: SIGTERM)
  -v, --verbose  Show detailed information

Examples:
  killport 3000          # Kill process on port 3000
  killport 3000 3010     # Kill processes on ports 3000-3010
  killport -l 3000       # List process on port 3000
  killport -f 8080       # Force kill process on port 8080
  ```
