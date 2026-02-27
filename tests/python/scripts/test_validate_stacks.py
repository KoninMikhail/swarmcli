"""Tests for scripts/validate_stacks.py."""

import sys
import pytest
import yaml
from pathlib import Path

from conftest import _import_module_from_path, SCRIPTS_DIR


@pytest.fixture
def validate_stacks():
    return _import_module_from_path("validate_stacks", SCRIPTS_DIR / "validate_stacks.py")


class TestValidateYamlFile:
    def test_valid_yaml(self, validate_stacks, tmp_path):
        f = tmp_path / "valid.yaml"
        f.write_text(yaml.dump({"key": "value"}))
        assert validate_stacks.validate_yaml_file(str(f)) is None

    def test_invalid_yaml(self, validate_stacks, tmp_path):
        f = tmp_path / "invalid.yaml"
        f.write_text("bad: [unclosed")
        result = validate_stacks.validate_yaml_file(str(f))
        assert result is not None


class TestCheckDockerStack:
    def test_valid_stack(self, validate_stacks, tmp_path):
        f = tmp_path / "docker-stack.yml"
        f.write_text(yaml.dump({"services": {"api": {"image": "test"}}}))
        errors = validate_stacks.check_docker_stack(str(f))
        assert errors == []

    def test_missing_services(self, validate_stacks, tmp_path):
        f = tmp_path / "docker-stack.yml"
        f.write_text(yaml.dump({"version": "3.8"}))
        errors = validate_stacks.check_docker_stack(str(f))
        assert any("services" in e.lower() for e in errors)


class TestCheckServicesYaml:
    def test_valid_services(self, validate_stacks, tmp_path):
        f = tmp_path / "services.yaml"
        f.write_text(yaml.dump({
            "services": {
                "api": {
                    "type": "git",
                    "image": "local/api",
                    "repo": "https://github.com/test/api.git",
                    "default_branch": "main",
                }
            }
        }))
        errors = validate_stacks.check_services_yaml(str(f))
        assert errors == []
