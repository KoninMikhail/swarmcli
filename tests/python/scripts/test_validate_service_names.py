"""Tests for scripts/validate_service_names.py."""

import pytest
import yaml
from pathlib import Path

from conftest import _import_module_from_path, SCRIPTS_DIR


@pytest.fixture
def validate_names():
    return _import_module_from_path(
        "validate_service_names", SCRIPTS_DIR / "validate_service_names.py"
    )


class TestGetServicesFromServicesYaml:
    def test_normal_file(self, validate_names, tmp_path):
        f = tmp_path / "services.yaml"
        f.write_text(yaml.dump({"services": {"api": {}, "worker": {}}}))
        result = validate_names.get_services_from_services_yaml(str(f))
        assert result == {"api", "worker"}


class TestGetServicesFromDockerStack:
    def test_normal_file(self, validate_names, tmp_path):
        f = tmp_path / "docker-stack.yml"
        f.write_text(yaml.dump({"services": {"api": {"image": "test"}, "db": {"image": "pg"}}}))
        result = validate_names.get_services_from_docker_stack(str(f))
        assert result == {"api", "db"}
