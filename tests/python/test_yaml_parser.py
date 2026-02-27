"""Tests for yaml_parser.py module."""

import pytest
import yaml


class TestLoadYamlFile:
    def test_valid_yaml(self, yaml_parser, yaml_file):
        result = yaml_parser.load_yaml_file(str(yaml_file))
        assert isinstance(result, dict)
        assert result["name"] == "test"
        assert result["version"] == "1.0"

    def test_empty_file(self, yaml_parser, empty_yaml_file):
        result = yaml_parser.load_yaml_file(str(empty_yaml_file))
        assert result == {}

    def test_invalid_yaml(self, yaml_parser, invalid_yaml_file):
        with pytest.raises(SystemExit) as exc_info:
            yaml_parser.load_yaml_file(str(invalid_yaml_file))
        assert exc_info.value.code == 1

    def test_nonexistent_file(self, yaml_parser):
        with pytest.raises(SystemExit) as exc_info:
            yaml_parser.load_yaml_file("/nonexistent/path.yaml")
        assert exc_info.value.code == 1


class TestGetNestedValue:
    def test_simple_key(self, yaml_parser):
        data = {"name": "test"}
        assert yaml_parser.get_nested_value(data, "name") == "test"

    def test_nested_path(self, yaml_parser):
        data = {"a": {"b": {"c": "deep"}}}
        assert yaml_parser.get_nested_value(data, "a.b.c") == "deep"

    def test_nonexistent_path(self, yaml_parser):
        data = {"a": {"b": "value"}}
        assert yaml_parser.get_nested_value(data, "a.x.y") is None


class TestGetField:
    def test_string_value(self, yaml_parser, yaml_file, capsys):
        yaml_parser.get_field(str(yaml_file), "name")
        captured = capsys.readouterr()
        assert captured.out.strip() == "test"

    def test_boolean_value(self, yaml_parser, tmp_path, capsys):
        f = tmp_path / "bool.yaml"
        f.write_text(yaml.dump({"enabled": True}))
        yaml_parser.get_field(str(f), "enabled")
        captured = capsys.readouterr()
        assert captured.out.strip() == "true"

    def test_dict_value_as_yaml(self, yaml_parser, yaml_file, capsys):
        yaml_parser.get_field(str(yaml_file), "nested")
        captured = capsys.readouterr()
        assert "key: value" in captured.out


class TestGetKeys:
    def test_root_keys(self, yaml_parser, yaml_file, capsys):
        yaml_parser.get_keys(str(yaml_file), "")
        captured = capsys.readouterr()
        keys = captured.out.strip().split("\n")
        assert "name" in keys
        assert "nested" in keys
        assert "version" in keys

    def test_nested_keys(self, yaml_parser, yaml_file, capsys):
        yaml_parser.get_keys(str(yaml_file), "nested")
        captured = capsys.readouterr()
        keys = captured.out.strip().split("\n")
        assert "key" in keys

    def test_not_dict_exits(self, yaml_parser, yaml_file):
        with pytest.raises(SystemExit) as exc_info:
            yaml_parser.get_keys(str(yaml_file), "name")
        assert exc_info.value.code == 1


class TestGetList:
    def test_string_list(self, yaml_parser, tmp_path, capsys):
        f = tmp_path / "list.yaml"
        f.write_text(yaml.dump({"items": ["a", "b", "c"]}))
        yaml_parser.get_list(str(f), "items")
        captured = capsys.readouterr()
        items = captured.out.strip().split("\n")
        assert items == ["a", "b", "c"]

    def test_dict_list(self, yaml_parser, tmp_path, capsys):
        f = tmp_path / "dictlist.yaml"
        f.write_text(yaml.dump({"items": [{"name": "x"}, {"name": "y"}]}))
        yaml_parser.get_list(str(f), "items")
        captured = capsys.readouterr()
        assert "name: x" in captured.out


class TestIterSection:
    def test_key_value_pairs(self, yaml_parser, tmp_path, capsys):
        f = tmp_path / "section.yaml"
        f.write_text(yaml.dump({"vars": {"A": "1", "B": "2"}}))
        yaml_parser.iter_section(str(f), "vars")
        captured = capsys.readouterr()
        lines = captured.out.strip().split("\n")
        assert "A=1" in lines
        assert "B=2" in lines

    def test_boolean_lowercase(self, yaml_parser, tmp_path, capsys):
        f = tmp_path / "bools.yaml"
        f.write_text(yaml.dump({"vars": {"ENABLED": True, "DISABLED": False}}))
        yaml_parser.iter_section(str(f), "vars")
        captured = capsys.readouterr()
        assert "ENABLED=true" in captured.out
        assert "DISABLED=false" in captured.out

    def test_none_values_skipped(self, yaml_parser, tmp_path, capsys):
        f = tmp_path / "nones.yaml"
        content = "vars:\n  A: hello\n  B: null\n  C: world\n"
        f.write_text(content)
        yaml_parser.iter_section(str(f), "vars")
        captured = capsys.readouterr()
        assert "A=hello" in captured.out
        assert "C=world" in captured.out
        assert "B=" not in captured.out


class TestGetConfigs:
    def test_valid_externals(self, yaml_parser, tmp_path, capsys):
        f = tmp_path / "externals.yaml"
        content = {
            "configs": [
                {"name": "nginx_config", "file": "configs/nginx.conf"},
                {"name": "app_config", "file": "configs/app.json"},
            ]
        }
        f.write_text(yaml.dump(content))
        yaml_parser.get_configs(str(f))
        captured = capsys.readouterr()
        assert "nginx_config\tconfigs/nginx.conf" in captured.out
        assert "app_config\tconfigs/app.json" in captured.out


class TestMain:
    def test_unknown_command(self, yaml_parser, yaml_file, monkeypatch):
        monkeypatch.setattr(
            "sys.argv", ["yaml_parser.py", "unknown_cmd", str(yaml_file)]
        )
        with pytest.raises(SystemExit) as exc_info:
            yaml_parser.main()
        assert exc_info.value.code == 1

    def test_insufficient_args(self, yaml_parser, monkeypatch):
        monkeypatch.setattr("sys.argv", ["yaml_parser.py", "get_field"])
        with pytest.raises(SystemExit) as exc_info:
            yaml_parser.main()
        assert exc_info.value.code == 1
