"""Tests for templates.py module."""

import os
import pytest
import yaml
from pathlib import Path


class TestParseYamlSimple:
    def test_valid_yaml(self, templates_module):
        result = templates_module.parse_yaml_simple("name: test\nversion: 1")
        assert result == {"name": "test", "version": 1}

    def test_invalid_yaml(self, templates_module):
        result = templates_module.parse_yaml_simple("bad: [unclosed")
        assert result == {}


class TestParseResourcesYaml:
    def test_with_stacks_section(self, templates_module):
        content = yaml.dump({
            "stacks": {
                "mystack": {
                    "api": {
                        "limits": {"cpus": "1.0", "memory": "512M"},
                        "reservations": {"cpus": "0.5", "memory": "256M"},
                    }
                }
            }
        })
        result = templates_module.parse_resources_yaml(content)
        assert "mystack" in result
        assert "api" in result["mystack"]


class TestLoadGlobals:
    def test_file_exists(self, templates_module, profile_stacks_dir):
        result = templates_module.load_globals(profile_stacks_dir)
        assert "GLOBAL_TZ" in result
        assert result["GLOBAL_TZ"] == "UTC"

    def test_file_missing(self, templates_module, tmp_path):
        result = templates_module.load_globals(tmp_path)
        assert result == {}


class TestLoadEndpoints:
    def test_full_file(self, templates_module, profile_stacks_dir):
        result = templates_module.load_endpoints(profile_stacks_dir)
        assert "SERVICE_INTERNAL_API_HOST" in result
        assert result["SERVICE_INTERNAL_API_HOST"] == "api.local"
        assert "SERVICE_INTERNAL_API_PORT" in result
        assert "SERVICE_INTERNAL_API_URL" in result

    def test_optional_fields(self, templates_module, profile_stacks_dir):
        result = templates_module.load_endpoints(profile_stacks_dir)
        assert "SERVICE_INTERNAL_DB_DATABASE" in result
        assert result["SERVICE_INTERNAL_DB_DATABASE"] == "mydb"


class TestLoadVariables:
    def test_runtime_section(self, templates_module, stack_dir):
        all_vars, env_vars = templates_module.load_variables(stack_dir)
        assert "ENVIRONMENT" in all_vars
        assert all_vars["ENVIRONMENT"] == "test"

    def test_common_section(self, templates_module, stack_dir):
        all_vars, _ = templates_module.load_variables(stack_dir)
        assert "APP_NAME" in all_vars
        assert all_vars["APP_NAME"] == "testapp"

    def test_env_list_to_csv(self, templates_module, tmp_path):
        stack = tmp_path / "stack"
        stack.mkdir()
        (stack / "variables.yaml").write_text(yaml.dump({
            "runtime": {"env": {"HOSTS": ["a", "b", "c"]}}
        }))
        _, env_vars = templates_module.load_variables(stack)
        assert env_vars["HOSTS"] == "a,b,c"


class TestLoadEnvironment:
    def test_runtime_vars(self, templates_module, monkeypatch):
        monkeypatch.setenv("RUNTIME_DB_HOST", "localhost")
        all_vars, runtime = templates_module.load_environment()
        assert "DB_HOST" in all_vars
        assert "DB_HOST" in runtime

    def test_build_vars(self, templates_module, monkeypatch):
        monkeypatch.setenv("BUILD_VERSION", "1.2.3")
        all_vars, _ = templates_module.load_environment()
        assert "VERSION" in all_vars

    def test_tag_vars_keep_prefix(self, templates_module, monkeypatch):
        monkeypatch.setenv("TAG_API", "abc123")
        all_vars, _ = templates_module.load_environment()
        assert "TAG_API" in all_vars


class TestResolveVariableReferences:
    def test_simple_reference(self, templates_module):
        variables = {"A": "hello", "B": "${A} world"}
        result = templates_module.resolve_variable_references(variables)
        assert result["B"] == "hello world"

    def test_nested_reference(self, templates_module):
        variables = {"A": "1", "B": "${A}2", "C": "${B}3"}
        result = templates_module.resolve_variable_references(variables)
        assert result["C"] == "123"

    def test_unresolved_stays(self, templates_module):
        variables = {"A": "${MISSING}"}
        result = templates_module.resolve_variable_references(variables)
        assert result["A"] == "${MISSING}"

    def test_self_reference_no_loop(self, templates_module):
        variables = {"A": "${A}_suffix"}
        result = templates_module.resolve_variable_references(variables)
        assert "${A}" in result["A"]


class TestConvertDockerComposeToJinja:
    def test_simple_var(self, templates_module):
        result = templates_module.convert_docker_compose_to_jinja("image: ${IMAGE}")
        assert "{{ IMAGE }}" in result

    def test_var_with_default(self, templates_module):
        result = templates_module.convert_docker_compose_to_jinja(
            "port: ${PORT:-8080}"
        )
        assert "{{ PORT }}" in result

    def test_header_added(self, templates_module):
        result = templates_module.convert_docker_compose_to_jinja("test: content")
        assert "JINJA2 TEMPLATE" in result


class TestFindUsedVariablesInTemplate:
    def test_expression_var(self, templates_module):
        content = "image: {{ IMAGE_NAME }}"
        result = templates_module.find_used_variables_in_template(content)
        assert "IMAGE_NAME" in result

    def test_if_var(self, templates_module):
        content = "{% if DEBUG_MODE %}debug{% endif %}"
        result = templates_module.find_used_variables_in_template(content)
        assert "DEBUG_MODE" in result


class TestValidateVariablesUsage:
    def test_all_used(self, templates_module):
        variables = {"IMAGE": "test"}
        template = "{{ IMAGE }}"
        result = templates_module.validate_variables_usage(
            variables, {}, template, "stack"
        )
        assert result == []

    def test_unused_produces_warnings(self, templates_module):
        variables = {"IMAGE": "test", "UNUSED_VAR": "val"}
        template = "{{ IMAGE }}"
        result = templates_module.validate_variables_usage(
            variables, {}, template, "stack"
        )
        assert len(result) > 0

    def test_env_vars_excluded(self, templates_module):
        variables = {"IMAGE": "test", "DB_HOST": "localhost"}
        env_vars = {"DB_HOST": "localhost"}
        template = "{{ IMAGE }}"
        result = templates_module.validate_variables_usage(
            variables, env_vars, template, "stack"
        )
        assert not any("DB_HOST" in w for w in result)


class TestCollectAllVariables:
    def test_priority_order(self, templates_module, profile_stacks_dir, stack_dir):
        merged, sources = templates_module.collect_all_variables(
            profile_stacks_dir, stack_dir
        )
        assert "GLOBAL_TZ" in merged
        assert "SERVICE_INTERNAL_API_HOST" in merged
        assert "ENVIRONMENT" in merged


class TestDeployResources:
    def test_with_resources(self, templates_module):
        resources = {
            "mystack": {
                "api": {
                    "limits": {"cpus": "1.0", "memory": "512M"},
                    "reservations": {"cpus": "0.5", "memory": "256M"},
                }
            }
        }
        func = templates_module.create_deploy_resources_func(resources, "mystack")
        result = func("api")
        assert "resources:" in result
        assert "limits:" in result
        assert '"1.0"' in result

    def test_no_resources(self, templates_module):
        func = templates_module.create_deploy_resources_func({}, "mystack")
        result = func("api")
        assert result == ""


class TestDozzleLabels:
    def test_with_meta(self, templates_module):
        meta = {"api": {"group": "core", "name": "API Service"}}
        func = templates_module.create_dozzle_labels_func(meta)
        result = func("api")
        assert "dev.dozzle.group: core" in result
        assert "dev.dozzle.name: API Service" in result


class TestServiceImage:
    def test_internal_service(self, templates_module):
        meta = {"api": {"image": "local/api"}}
        variables = {"TAG_API": "dev-abc123"}
        func = templates_module.create_service_image_func(meta, variables)
        result = func("api")
        assert result == "local/api:dev-abc123"

    def test_external_with_tag(self, templates_module):
        meta = {"postgres": {"image": "postgres:16"}}
        func = templates_module.create_service_image_func(meta, {})
        result = func("postgres")
        assert result == "postgres:16"

    def test_unknown_service_raises(self, templates_module):
        func = templates_module.create_service_image_func({}, {})
        with pytest.raises(KeyError):
            func("nonexistent")


class TestConfigName:
    def test_simple_strategy(self, templates_module):
        mappings = {"nginx_config": "nginx_config"}
        func = templates_module.create_config_name_func(mappings)
        assert func("nginx_config") == "nginx_config"

    def test_versioned_strategy(self, templates_module):
        mappings = {"nginx_config": "nginx_config_dev_abc123"}
        func = templates_module.create_config_name_func(mappings)
        assert func("nginx_config") == "nginx_config_dev_abc123"


class TestInjectEnvVars:
    def test_with_variables(self, templates_module):
        env_vars = {"DEBUG": "true", "HOST": "localhost"}
        all_vars = {"DEBUG": "true", "HOST": "localhost"}
        func = templates_module.create_inject_env_vars_func(env_vars, all_vars)
        result = func()
        assert "DEBUG" in result
        assert "HOST" in result

    def test_with_exclude(self, templates_module):
        env_vars = {"DEBUG": "true", "SECRET": "hidden"}
        all_vars = {"DEBUG": "true", "SECRET": "hidden"}
        func = templates_module.create_inject_env_vars_func(env_vars, all_vars)
        result = func(exclude=["SECRET"])
        assert "SECRET" not in result
        assert "DEBUG" in result

    def test_empty(self, templates_module):
        func = templates_module.create_inject_env_vars_func({}, {})
        result = func()
        assert result == ""


class TestParseServicesYaml:
    def test_full_file(self, templates_module, tmp_path):
        stack = tmp_path / "stack"
        stack.mkdir()
        (stack / "services.yaml").write_text(
            "services:\n"
            "  api:\n"
            "    image: local/api\n"
            "    meta:\n"
            "      group: core\n"
            "      name: API Service\n"
        )
        result = templates_module.parse_services_yaml(stack)
        assert "api" in result
        assert result["api"]["group"] == "core"

    def test_no_file(self, templates_module, tmp_path):
        result = templates_module.parse_services_yaml(tmp_path)
        assert result == {}


class TestInitTemplates:
    def test_new_stack(self, templates_module, tmp_path):
        stacks_dir = tmp_path / "stacks"
        stacks_dir.mkdir()
        stack = tmp_path / "stack"
        stack.mkdir()
        (stack / "docker-stack.yml").write_text(
            "version: '3.8'\nservices:\n  api:\n    image: ${IMAGE}\n"
        )
        result = templates_module.init_templates(stacks_dir, stack)
        assert result is True
        assert (stack / "templates.yaml").exists()
        assert (stack / "templates" / "docker-stack.j2").exists()

    def test_already_initialized(self, templates_module, tmp_path):
        stacks_dir = tmp_path / "stacks"
        stacks_dir.mkdir()
        stack = tmp_path / "stack"
        stack.mkdir()
        (stack / "docker-stack.yml").write_text("test")
        (stack / "templates.yaml").write_text("existing")
        result = templates_module.init_templates(stacks_dir, stack)
        assert result is False


class TestLoadConfigMappings:
    def test_env_to_dict(self, templates_module, monkeypatch):
        monkeypatch.setenv("CONFIG_NAME_NGINX_CONF", "nginx_conf_v2")
        result = templates_module.load_config_mappings()
        assert "nginx-conf" in result or "nginx_conf" in result
