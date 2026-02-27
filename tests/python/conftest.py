"""Common fixtures for Python tests."""

import os
import sys
import importlib.util
from pathlib import Path

import pytest
import yaml


PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
LIB_DIR = PROJECT_ROOT / "bin" / "lib"
SCRIPTS_DIR = PROJECT_ROOT / "scripts"


def _import_module_from_path(module_name: str, file_path: Path):
    """Import a Python module from an arbitrary filesystem path."""
    spec = importlib.util.spec_from_file_location(module_name, str(file_path))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = mod
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def yaml_parser():
    """Import yaml_parser module."""
    return _import_module_from_path("yaml_parser", LIB_DIR / "utils" / "yaml_parser.py")


@pytest.fixture
def config_manager():
    """Import config_manager module."""
    return _import_module_from_path("config_manager", LIB_DIR / "config" / "config_manager.py")


@pytest.fixture
def templates_module():
    """Import templates module."""
    return _import_module_from_path("templates", LIB_DIR / "templates" / "templates.py")


@pytest.fixture
def yaml_file(tmp_path):
    """Create a simple valid YAML file."""
    content = {"name": "test", "version": "1.0", "nested": {"key": "value"}}
    path = tmp_path / "test.yaml"
    path.write_text(yaml.dump(content))
    return path


@pytest.fixture
def empty_yaml_file(tmp_path):
    """Create an empty YAML file."""
    path = tmp_path / "empty.yaml"
    path.write_text("")
    return path


@pytest.fixture
def invalid_yaml_file(tmp_path):
    """Create an invalid YAML file."""
    path = tmp_path / "invalid.yaml"
    path.write_text("name: test\n  bad indent: [unclosed")
    return path


@pytest.fixture
def nested_yaml_file(tmp_path):
    """Create a deeply nested YAML file."""
    content = {
        "services": {
            "api": {
                "image": "local/api",
                "repo": "https://github.com/test/api.git",
                "enabled": True,
            },
            "worker": {
                "image": "redis:7-alpine",
                "enabled": False,
            },
        },
        "settings": {"timeout": 30, "retries": 3},
    }
    path = tmp_path / "nested.yaml"
    path.write_text(yaml.dump(content))
    return path


@pytest.fixture
def config_file(tmp_path):
    """Create a .swarmcli.yaml config file."""
    content = {
        "config_version": 1,
        "state": {"default_profile": "test-server"},
        "paths": {"secrets": ".secrets", "locks": ".locks"},
        "operations": {"log_format": "text", "timeout": 900, "lock_timeout": 3600},
        "git": {"auth": {"http_user": "user", "http_token": "secret123", "http_password": None}},
    }
    path = tmp_path / ".swarmcli.yaml"
    path.write_text(yaml.dump(content, default_flow_style=False))
    return path


@pytest.fixture
def stack_dir(tmp_path):
    """Create a minimal stack directory with all necessary files."""
    stack = tmp_path / "stacks" / "test-stack"
    stack.mkdir(parents=True)

    (stack / "services.yaml").write_text(
        yaml.dump(
            {
                "services": {
                    "api": {
                        "image": "local/api",
                        "meta": {"group": "core", "name": "API Service"},
                    },
                    "worker": {
                        "image": "local/worker",
                        "meta": {"group": "core", "name": "Worker"},
                    },
                    "postgres": {"image": "postgres:16"},
                }
            }
        )
    )

    (stack / "variables.yaml").write_text(
        yaml.dump(
            {
                "common": {"APP_NAME": "testapp"},
                "runtime": {
                    "ENVIRONMENT": "test",
                    "env": {
                        "DEBUG_MODE": "true",
                        "DATABASE_HOST": "localhost",
                    },
                },
            }
        )
    )

    (stack / "docker-stack.yml").write_text(
        "version: '3.8'\nservices:\n  api:\n    image: ${IMAGE}\n"
    )

    return stack


@pytest.fixture
def profile_stacks_dir(tmp_path):
    """Create a profile stacks directory with globals and endpoints."""
    stacks = tmp_path / "stacks"
    stacks.mkdir(parents=True)

    (stacks / "globals.yaml").write_text(
        yaml.dump({"TZ": "UTC", "DOMAIN": "example.com"})
    )

    (stacks / "endpoints.yaml").write_text(
        yaml.dump(
            {
                "endpoints": {
                    "internal": {
                        "api": {"host": "api.local", "port": 8080},
                        "db": {
                            "host": "db.local",
                            "port": 5432,
                            "database": "mydb",
                        },
                    }
                }
            }
        )
    )

    return stacks
