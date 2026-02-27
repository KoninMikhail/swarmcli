#!/usr/bin/env python3
"""
YAML Parser CLI for swarmcli

Provides command-line interface for parsing YAML files using PyYAML.
Used by yaml.sh Bash wrapper to replace self-written YAML parser.

Usage:
    python3 yaml_parser.py get_field <file> <path>
    python3 yaml_parser.py get_keys <file> <path>
    python3 yaml_parser.py get_list <file> <path>
    python3 yaml_parser.py iter_section <file> <section>
"""

import sys

try:
    import yaml
except ImportError:
    sys.exit(
        "Error: PyYAML is not installed.\n"
        "Install it with: pip install pyyaml"
    )

from pathlib import Path
from typing import Any, Optional


def load_yaml_file(file_path: str) -> dict:
    """Load and parse YAML file."""
    try:
        path = Path(file_path)
        if not path.exists():
            sys.stderr.write(f"Error: file not found: {file_path}\n")
            sys.exit(1)
        
        with open(path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f) or {}
    except yaml.YAMLError as e:
        sys.stderr.write(f"Error: YAML parsing failed: {e}\n")
        sys.exit(1)
    except Exception as e:
        sys.stderr.write(f"Error: {e}\n")
        sys.exit(1)


def get_nested_value(data: dict, path: str) -> Optional[Any]:
    """
    Get value from nested dictionary using dot notation.
    
    Examples:
        get_nested_value({"a": {"b": "value"}}, "a.b") -> "value"
        get_nested_value({"services": {"api": {"image": "test"}}}, "services.api.image") -> "test"
    """
    keys = path.split('.')
    current = data
    
    for key in keys:
        if isinstance(current, dict) and key in current:
            current = current[key]
        else:
            return None
    
    return current


def get_field(file_path: str, path: str) -> None:
    """Get field value by path (dot notation)."""
    data = load_yaml_file(file_path)
    value = get_nested_value(data, path)
    
    if value is None:
        sys.exit(1)
    
    # Handle different value types
    if isinstance(value, (dict, list)):
        # For complex types, output as YAML
        print(yaml.dump(value, default_flow_style=False).rstrip())
    elif isinstance(value, bool):
        # Booleans: output as lowercase true/false (YAML style)
        print("true" if value else "false")
    else:
        print(value)


def get_keys(file_path: str, path: str) -> None:
    """Get list of keys from a dictionary at given path."""
    data = load_yaml_file(file_path)
    
    if path:
        value = get_nested_value(data, path)
    else:
        value = data
    
    if not isinstance(value, dict):
        sys.exit(1)
    
    # Output keys one per line
    for key in sorted(value.keys()):
        print(key)


def get_list(file_path: str, path: str) -> None:
    """Get list items from a list at given path."""
    data = load_yaml_file(file_path)
    
    if path:
        value = get_nested_value(data, path)
    else:
        value = data
    
    if not isinstance(value, list):
        sys.exit(1)
    
    # Output items one per line
    for item in value:
        if isinstance(item, (dict, list)):
            # Complex items: output as YAML
            print(yaml.dump(item, default_flow_style=False).rstrip())
        else:
            print(item)


def iter_section(file_path: str, section: str) -> None:
    """
    Iterate over key-value pairs in a section.
    Output format: KEY=VALUE (one per line)
    
    Used for variables.yaml and globals.yaml.
    """
    data = load_yaml_file(file_path)
    
    # Get section data
    if section:
        section_data = get_nested_value(data, section)
    else:
        section_data = data
    
    if not isinstance(section_data, dict):
        sys.exit(1)
    
    # Output key=value pairs
    for key, value in section_data.items():
        if value is None:
            continue
        
        # Convert value to string
        if isinstance(value, bool):
            value_str = "true" if value else "false"
        elif isinstance(value, (dict, list)):
            # For complex types, serialize as YAML string
            value_str = yaml.dump(value, default_flow_style=False).rstrip()
            # Replace newlines with spaces for single-line output
            value_str = value_str.replace('\n', ' ')
        else:
            value_str = str(value)
        
        print(f"{key}={value_str}")


def get_configs(file_path: str) -> None:
    """
    Get configs list from externals.yaml.
    
    Expected format:
        configs:
          - name: my_config
            file: configs/my-config.json
    
    Output format: name<TAB>file (one per line)
    """
    data = load_yaml_file(file_path)
    
    configs = data.get('configs', [])
    
    if not isinstance(configs, list):
        sys.exit(1)
    
    for config in configs:
        if not isinstance(config, dict):
            continue
        
        name = config.get('name', '')
        file = config.get('file', '')
        
        if name and file:
            print(f"{name}\t{file}")


def main():
    """Main CLI entry point."""
    if len(sys.argv) < 3:
        sys.stderr.write("Usage: yaml_parser.py <command> <file> [path/section]\n")
        sys.stderr.write("Commands: get_field, get_keys, get_list, iter_section\n")
        sys.exit(1)
    
    command = sys.argv[1]
    file_path = sys.argv[2]
    path_or_section = sys.argv[3] if len(sys.argv) > 3 else ""
    
    try:
        if command == "get_field":
            get_field(file_path, path_or_section)
        elif command == "get_keys":
            get_keys(file_path, path_or_section)
        elif command == "get_list":
            get_list(file_path, path_or_section)
        elif command == "iter_section":
            iter_section(file_path, path_or_section)
        elif command == "get_configs":
            get_configs(file_path)
        else:
            sys.stderr.write(f"Error: unknown command: {command}\n")
            sys.stderr.write("Commands: get_field, get_keys, get_list, iter_section, get_configs\n")
            sys.exit(1)
    except Exception as e:
        sys.stderr.write(f"Error: {e}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
