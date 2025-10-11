#!/usr/bin/env python3
"""
Expand environment variables in configuration files.

Reads a template file and expands all ${VAR} and $VAR style environment
variables, writing the result to an output file.
"""

import os
import sys
import re


def expand_vars(content):
    """Expand environment variables in content.

    Supports both ${VAR} and $VAR formats.
    """
    def replace_var(match):
        var_name = match.group(1) or match.group(2)
        return os.environ[var_name]

    # Match ${VAR} or $VAR (word characters only for $VAR)
    pattern = r'\$\{([^}]+)\}|\$(\w+)'
    return re.sub(pattern, replace_var, content)


def main():
    if len(sys.argv) != 3:
        print("Usage: expand_vars.py <input_file> <output_file>", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    try:
        with open(input_file, 'r') as f:
            content = f.read()

        expanded = expand_vars(content)

        with open(output_file, 'w') as f:
            f.write(expanded)

        print(f"Expanded: {input_file} -> {output_file}", file=sys.stderr)

    except KeyError as e:
        print(f"Error: Unknown variable: {e}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print(f"Error: Input file not found: {input_file}", file=sys.stderr)
        sys.exit(1)
    except PermissionError as e:
        print(f"Error: Permission denied: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
