"""Tests for config_manager.py module."""

import os
import pytest
import yaml


class TestLoadConfig:
    def test_valid_file(self, config_manager, config_file):
        result = config_manager.load_config(str(config_file))
        assert isinstance(result, dict)
        assert result["config_version"] == 1

    def test_nonexistent_file(self, config_manager):
        result = config_manager.load_config("/nonexistent/config.yaml")
        assert result == {}

    def test_corrupt_yaml(self, config_manager, tmp_path, capsys):
        f = tmp_path / "corrupt.yaml"
        f.write_text("key: [unclosed\n  bad: indent")
        result = config_manager.load_config(str(f))
        assert result == {}
        captured = capsys.readouterr()
        assert "Warning" in captured.err


class TestSaveConfig:
    def test_atomic_write(self, config_manager, tmp_path):
        path = tmp_path / "output.yaml"
        data = {"config_version": 1, "state": {"profile": "test"}}
        config_manager.save_config(str(path), data)
        assert path.exists()
        loaded = yaml.safe_load(path.read_text())
        assert loaded["config_version"] == 1

    def test_creates_parent_dirs(self, config_manager, tmp_path):
        path = tmp_path / "deep" / "nested" / "config.yaml"
        config_manager.save_config(str(path), {"key": "value"})
        assert path.exists()


class TestGetNested:
    def test_simple_key(self, config_manager):
        data = {"name": "test"}
        assert config_manager.get_nested(data, "name") == "test"

    def test_dot_notation(self, config_manager):
        data = {"a": {"b": {"c": "deep"}}}
        assert config_manager.get_nested(data, "a.b.c") == "deep"

    def test_nonexistent_returns_none(self, config_manager):
        data = {"a": {"b": "val"}}
        assert config_manager.get_nested(data, "a.x") is None


class TestSetNested:
    def test_new_key(self, config_manager):
        data = {}
        config_manager.set_nested(data, "a.b.c", "value")
        assert data["a"]["b"]["c"] == "value"

    def test_overwrite(self, config_manager):
        data = {"a": {"b": "old"}}
        config_manager.set_nested(data, "a.b", "new")
        assert data["a"]["b"] == "new"


class TestCoerceValue:
    @pytest.mark.parametrize("raw,expected", [
        ("true", True), ("True", True), ("yes", True),
        ("false", False), ("False", False), ("no", False),
    ])
    def test_boolean(self, config_manager, raw, expected):
        assert config_manager.coerce_value(raw) is expected

    @pytest.mark.parametrize("raw", ["null", "none", "~", "None"])
    def test_null(self, config_manager, raw):
        assert config_manager.coerce_value(raw) is None

    def test_int(self, config_manager):
        assert config_manager.coerce_value("42") == 42
        assert isinstance(config_manager.coerce_value("42"), int)

    def test_float(self, config_manager):
        assert config_manager.coerce_value("3.14") == 3.14
        assert isinstance(config_manager.coerce_value("3.14"), float)

    def test_string(self, config_manager):
        assert config_manager.coerce_value("hello") == "hello"


class TestMaskValue:
    def test_short_value(self, config_manager):
        assert config_manager.mask_value("abc") == "****"

    def test_long_value(self, config_manager):
        result = config_manager.mask_value("secrettoken123")
        assert result.startswith("****")
        assert result.endswith("n123")  # last 4 chars of "secrettoken123"


class TestMergeDefaults:
    def test_empty_data_gets_defaults(self, config_manager):
        result = config_manager.merge_defaults({})
        assert "config_version" in result
        assert "state" in result
        assert "paths" in result

    def test_user_data_preserved(self, config_manager):
        data = {"state": {"default_profile": "my-server"}}
        result = config_manager.merge_defaults(data)
        assert result["state"]["default_profile"] == "my-server"
        assert "paths" in result


class TestCmdGet:
    def test_existing_key(self, config_manager, config_file, capsys):
        config_manager.cmd_get(str(config_file), "config_version")
        captured = capsys.readouterr()
        assert captured.out.strip() == "1"

    def test_nonexistent_key_exits(self, config_manager, config_file):
        with pytest.raises(SystemExit) as exc_info:
            config_manager.cmd_get(str(config_file), "nonexistent.key")
        assert exc_info.value.code == 1


class TestCmdSet:
    def test_valid_key(self, config_manager, tmp_path):
        path = tmp_path / ".swarmcli.yaml"
        path.write_text(yaml.dump({"config_version": 1}))
        config_manager.cmd_set(str(path), "operations.timeout", "600")
        loaded = yaml.safe_load(path.read_text())
        assert loaded["operations"]["timeout"] == 600

    def test_invalid_key_exits(self, config_manager, tmp_path):
        path = tmp_path / ".swarmcli.yaml"
        path.write_text(yaml.dump({"config_version": 1}))
        with pytest.raises(SystemExit) as exc_info:
            config_manager.cmd_set(str(path), "invalid.unknown.key", "val")
        assert exc_info.value.code == 1


class TestCmdList:
    def test_lists_all_keys(self, config_manager, config_file, capsys):
        config_manager.cmd_list(str(config_file))
        captured = capsys.readouterr()
        assert "config_version" in captured.out
        assert "operations.timeout" in captured.out

    def test_sensitive_keys_masked(self, config_manager, config_file, capsys):
        config_manager.cmd_list(str(config_file))
        captured = capsys.readouterr()
        assert "****" in captured.out


class TestCmdExportEnv:
    def test_exports_env_vars(self, config_manager, config_file, capsys, monkeypatch):
        monkeypatch.setenv("PLATFORM_ROOT", "/test")
        config_manager.cmd_export_env(str(config_file))
        captured = capsys.readouterr()
        assert "LOG_FORMAT=text" in captured.out
        assert "TIMEOUT_SECONDS=900" in captured.out

    def test_relative_path_resolved(self, config_manager, config_file, capsys, monkeypatch):
        monkeypatch.setenv("PLATFORM_ROOT", "/opt/swarm")
        config_manager.cmd_export_env(str(config_file))
        captured = capsys.readouterr()
        assert "SECRETS_ROOT=" in captured.out
        for line in captured.out.strip().split("\n"):
            if line.startswith("SECRETS_ROOT="):
                assert line.split("=", 1)[1].startswith("/")

    def test_path_traversal_skipped(self, config_manager, tmp_path, capsys, monkeypatch):
        monkeypatch.setenv("PLATFORM_ROOT", str(tmp_path))
        f = tmp_path / "cfg.yaml"
        f.write_text(yaml.dump({
            "config_version": 1,
            "paths": {"secrets": "../../etc/passwd"},
        }))
        config_manager.cmd_export_env(str(f))
        captured = capsys.readouterr()
        assert "Warning" in captured.err


class TestCmdInit:
    def test_creates_file(self, config_manager, tmp_path, capsys):
        path = tmp_path / ".swarmcli.yaml"
        config_manager.cmd_init(str(path))
        assert path.exists()
        captured = capsys.readouterr()
        assert "Created" in captured.out

    def test_existing_file_exits(self, config_manager, config_file):
        with pytest.raises(SystemExit) as exc_info:
            config_manager.cmd_init(str(config_file))
        assert exc_info.value.code == 1


class TestCmdRepair:
    def test_corrupt_file_backed_up(self, config_manager, tmp_path, capsys):
        f = tmp_path / ".swarmcli.yaml"
        f.write_text("bad: [yaml: {unclosed")
        try:
            config_manager.cmd_repair(str(f))
        except Exception:
            pass
        assert (tmp_path / ".swarmcli.yaml.bak").exists()
        captured = capsys.readouterr()
        assert "backed up" in captured.out.lower() or "Corrupt" in captured.out

    def test_valid_file_re_merged(self, config_manager, tmp_path, capsys):
        f = tmp_path / ".swarmcli.yaml"
        f.write_text(yaml.dump({"config_version": 1, "custom": "data"}))
        config_manager.cmd_repair(str(f))
        loaded = yaml.safe_load(f.read_text())
        assert "state" in loaded
        assert "paths" in loaded


class TestValidSetKeys:
    def test_contains_expected_keys(self, config_manager):
        keys = config_manager.VALID_SET_KEYS
        assert "operations.timeout" in keys
        assert "paths.secrets" in keys
        assert "state.default_profile" in keys
        assert "git.auth.http_token" in keys
