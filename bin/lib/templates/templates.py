#!/usr/bin/env python3
"""
Jinja2 Template Engine for swarmcli

Renders Jinja2 templates with variables from multiple sources:
- globals.yaml (GLOBAL_* prefix)
- endpoints.yaml (SERVICE_* prefix)
- variables.yaml (deploy section)
- Environment variables (RUNTIME_*, BUILD_*, COMMON_*)

Usage:
    # Initialize templates for a stack (convert docker-stack.yml to .j2)
    python templates.py init <profile_stacks_dir> <stack_dir>
    
    # Render templates
    python templates.py render <profile_stacks_dir> <stack_dir>
    
    # Show variables
    python templates.py vars <profile_stacks_dir> <stack_dir>
"""

import sys
import os
import re
import json
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional


def is_ci() -> bool:
    """Check if running in CI environment."""
    return os.environ.get('EXEC_CONTEXT', '') == 'ci'

# Check Jinja2 availability
try:
    from jinja2 import Environment, FileSystemLoader, StrictUndefined, UndefinedError
    JINJA2_AVAILABLE = True
except ImportError:
    JINJA2_AVAILABLE = False

# Check PyYAML availability
try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False
    print("Error: PyYAML not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


def parse_yaml_simple(content: str) -> dict:
    """Parse YAML content using PyYAML."""
    try:
        return yaml.safe_load(content) or {}
    except yaml.YAMLError as e:
        print(f"Error: YAML parsing failed: {e}", file=sys.stderr)
        return {}


def parse_resources_yaml(content: str) -> dict:
    """
    Parse resources.yaml using PyYAML.
    
    Format:
        stacks:
          <stack-name>:
            <service-name>:
              limits:
                cpus: "X.X"
                memory: "XG"
              reservations:
                cpus: "X.X"
                memory: "XG"
    
    Returns:
        {
            "stack-name": {
                "service-name": {
                    "limits": {"cpus": "1.0", "memory": "512M"},
                    "reservations": {"cpus": "0.5", "memory": "256M"}
                }
            }
        }
    """
    try:
        data = yaml.safe_load(content) or {}
        # Extract stacks section if present
        return data.get('stacks', {})
    except yaml.YAMLError as e:
        print(f"Error: YAML parsing failed: {e}", file=sys.stderr)
        return {}


def load_all_resources(profile_stacks_dir: Path) -> Dict[str, Dict[str, dict]]:
    """
    Load resources.yaml and return all resources.
    
    Args:
        profile_stacks_dir: Path to profiles/*/stacks/
    
    Returns:
        Dict of stack_name -> {service_name -> {limits: {...}, reservations: {...}}}
    """
    resources_file = profile_stacks_dir / 'resources.yaml'
    if not resources_file.exists():
        return {}
    
    try:
        with open(resources_file, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f) or {}
            # Extract stacks section if present
            return data.get('stacks', {})
    except yaml.YAMLError as e:
        print(f"Error: Failed to parse resources.yaml: {e}", file=sys.stderr)
        return {}


def create_deploy_resources_func(all_resources: Dict[str, Dict[str, dict]], current_stack: str):
    """
    Create a Jinja2 global function for rendering deploy resources.
    
    Usage in template:
        {{ deploy_resources('service-name') }}
        {{ deploy_resources('service-name', indent=6) }}
        {{ deploy_resources('service-name', stack='other-stack') }}
    
    Returns YAML block like:
        resources:
          limits:
            cpus: "1.0"
            memory: "512M"
          reservations:
            cpus: "0.5"
            memory: "256M"
    """
    def deploy_resources(service_name: str, indent: int = 6, stack: str = None) -> str:
        """
        Generate YAML resources block for a service.
        
        Args:
            service_name: Name of the service in resources.yaml
            indent: Base indentation (spaces). Default 6 for deploy section.
            stack: Stack name to get resources from. Default is current stack.
        
        Returns:
            Formatted YAML string or empty string if no resources defined
        """
        target_stack = stack if stack else current_stack
        
        if target_stack not in all_resources:
            return ''
        
        stack_resources = all_resources[target_stack]
        
        if service_name not in stack_resources:
            return ''
        
        service_res = stack_resources[service_name]
        if not service_res:
            return ''
        
        lines = []
        base = ' ' * indent
        
        lines.append(f'{base}resources:')
        
        if 'limits' in service_res and service_res['limits']:
            limits = service_res['limits']
            lines.append(f'{base}  limits:')
            if 'cpus' in limits:
                lines.append(f'{base}    cpus: "{limits["cpus"]}"')
            if 'memory' in limits:
                lines.append(f'{base}    memory: "{limits["memory"]}"')
        
        if 'reservations' in service_res and service_res['reservations']:
            reservations = service_res['reservations']
            lines.append(f'{base}  reservations:')
            if 'cpus' in reservations:
                lines.append(f'{base}    cpus: "{reservations["cpus"]}"')
            if 'memory' in reservations:
                lines.append(f'{base}    memory: "{reservations["memory"]}"')
        
        # Return empty if only "resources:" line exists (no actual constraints)
        if len(lines) <= 1:
            return ''
        
        return '\n'.join(lines)
    
    return deploy_resources


def parse_services_yaml(stack_dir: Path) -> Dict[str, dict]:
    """
    Parse services.yaml and extract service metadata.
    
    Returns:
    {
        "api": {"group": "core", "name": "API Service", "image": "local/api"},
        "worker": {"group": "core", "image": "local/worker"}
    }
    """
    services_file = stack_dir / 'services.yaml'
    if not services_file.exists():
        return {}
    
    try:
        content = services_file.read_text(encoding='utf-8')
    except IOError:
        return {}
    
    services_meta = {}
    lines = content.split('\n')
    
    current_service = None
    in_meta = False
    meta_indent = 0
    
    for line in lines:
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        
        # Skip comments and empty lines
        if not stripped or stripped.startswith('#'):
            continue
        
        # Service definition (2 spaces indent under services:)
        if indent == 2 and stripped.endswith(':') and ':' not in stripped[:-1]:
            current_service = stripped[:-1].strip()
            in_meta = False
            services_meta[current_service] = {}
            continue
        
        # Meta section (4 spaces indent under service)
        if current_service and indent == 4 and stripped == 'meta:':
            in_meta = True
            meta_indent = indent
            continue
        
        # Exit meta section when indent decreases
        if in_meta and indent <= meta_indent and stripped:
            in_meta = False
        
        # Service-level properties (4 spaces indent, not in meta section)
        if current_service and indent == 4 and not in_meta and ':' in stripped:
            key, value = stripped.split(':', 1)
            key = key.strip()
            value = value.strip().strip('"\'')
            
            if key == 'image':
                services_meta[current_service]['image'] = value
        
        # Inside meta section - extract group and name
        if in_meta and indent > meta_indent:
            if ':' in stripped:
                key, value = stripped.split(':', 1)
                key = key.strip()
                value = value.strip().strip('"\'')
                
                if key in ('group', 'name'):
                    services_meta[current_service][key] = value
    
    # Filter out services without metadata or image
    # Keep services that have either meta (group/name) or image field
    return {svc: meta for svc, meta in services_meta.items() if meta}


def create_dozzle_labels_func(services_meta: Dict[str, dict]):
    """
    Create a Jinja2 global function for generating Dozzle labels.
    
    Usage in template (container level labels):
        labels:
          {{ dozzle_labels('service-name') }}
    
    Returns YAML block like (dict format):
        dev.dozzle.group: analytics
        dev.dozzle.name: API Service
    """
    def dozzle_labels(service_name: str, indent: int = 6) -> str:
        """
        Generate Dozzle labels for a service at container level.
        
        Args:
            service_name: Name of the service in services.yaml
            indent: Base indentation (spaces). Default 6 for labels dict items.
        
        Returns:
            Formatted YAML string or empty string if no meta defined
        """
        if service_name not in services_meta:
            return ''
        
        meta = services_meta[service_name]
        group = meta.get('group', '')
        
        if not group:
            return ''
        
        name = meta.get('name', service_name)
        
        lines = []
        base = ' ' * indent
        
        lines.append(f'{base}dev.dozzle.group: {group}')
        lines.append(f'{base}dev.dozzle.name: {name}')
        
        return '\n'.join(lines)
    
    return dozzle_labels


def create_service_image_func(services_meta: Dict[str, dict], variables: Dict[str, str]):
    """
    Create a Jinja2 global function for generating service image with tag.
    
    Usage in template:
        image: {{ service_image('service-name') }}
    
    Returns full image string like:
        local/ai-referent-analytics-agregator:server-dev-abc1234
    
    For registry services with tag in image (e.g., postgres:16), returns as-is.
    """
    def service_image(service_name: str) -> str:
        """
        Generate full image string (image:tag) for a service.
        
        Args:
            service_name: Name of the service in services.yaml
        
        Returns:
            Full image string with tag (e.g., "local/api:server-dev-abc1234")
            For images already containing tag, returns as-is (e.g., "postgres:16")
        
        Raises:
            KeyError: If service not found or image not defined in services.yaml
            UndefinedError: If TAG_* variable is missing (handled by Jinja2 StrictUndefined)
        """
        if service_name not in services_meta:
            raise KeyError(f"Service '{service_name}' not found in services.yaml")
        
        meta = services_meta[service_name]
        image = meta.get('image')
        
        if not image:
            raise KeyError(f"Service '{service_name}' does not have 'image' field in services.yaml")
        
        # If image already contains a tag (has ':'), return as-is
        # This handles registry images like "postgres:16", "redis:8-alpine"
        if ':' in image:
            return image
        
        # Generate TAG_* variable name: service_name -> TAG_<UPPERCASE_WITH_UNDERSCORES>
        # Examples: "api" -> "TAG_API", "parsers-gateway" -> "TAG_PARSERS_GATEWAY"
        tag_var = f"TAG_{service_name.upper().replace('-', '_')}"
        
        # Get tag from variables (will raise UndefinedError if missing due to StrictUndefined)
        tag = variables.get(tag_var)
        if tag is None:
            # This should not happen if StrictUndefined is used, but provide helpful error
            raise KeyError(f"TAG variable '{tag_var}' not found for service '{service_name}'. "
                          f"Make sure it's exported before template rendering.")
        
        return f"{image}:{tag}"
    
    return service_image


def create_config_name_func(config_mappings: Dict[str, str]):
    """
    Create a Jinja2 global function for getting actual config name.
    
    For simple strategy: returns same name
    For versioned strategy: returns name with profile and commit SHA suffix
    
    Usage in template:
        {{ config_name('nginx_config') }}
    
    Returns:
        - Simple: "nginx_config"
        - Versioned: "nginx_config_server-dev_abc1234"
    """
    def config_name(base_name: str) -> str:
        """
        Get actual config name for use in docker-stack.yml.
        
        Args:
            base_name: Base config name as defined in externals.yaml
        
        Returns:
            Actual config name (same for simple, versioned for versioned strategy)
        """
        return config_mappings.get(base_name, base_name)
    
    return config_name


def load_config_mappings() -> Dict[str, str]:
    """
    Load config name mappings from environment variables.
    
    Environment variables are set by sync_configs() in management.sh:
    CONFIG_NAME_<UPPER_NAME>=<actual_name>
    
    Returns:
        Dict of base_name -> actual_name
    """
    mappings = {}
    prefix = "CONFIG_NAME_"
    
    for key, value in os.environ.items():
        if key.startswith(prefix):
            # Convert CONFIG_NAME_NGINX_CONFIG back to nginx_config
            base_name = key[len(prefix):].lower().replace('_', '-')
            # Also try with underscores (some names may use underscores)
            base_name_underscore = key[len(prefix):].lower()
            mappings[base_name] = value
            mappings[base_name_underscore] = value
    
    return mappings


def create_inject_env_vars_func(env_vars: Dict[str, str], all_variables: Dict[str, str]):
    """
    Create a Jinja2 global function for injecting environment variables from variables.yaml.
    
    Only injects variables from runtime.env section (not all runtime variables).
    
    Usage in template:
        {{ inject_env_vars() }}
        {{ inject_env_vars(indent=6) }}
        {{ inject_env_vars(indent=6, exclude=['DEBUG_MODE']) }}
    
    Returns YAML block like:
        ENVIRONMENT: "development"
        DEBUG_MODE: "true"
        DATABASE_HOST: "database.example.localhost"
    """
    def inject_env_vars(indent: int = 6, exclude: List[str] = None) -> str:
        """
        Generate YAML environment block from variables.yaml runtime.env section.
        
        Args:
            indent: Base indentation (spaces). Default 6 for environment section.
            exclude: List of variable names to exclude from injection.
        
        Returns:
            Formatted YAML string with resolved variable values
        """
        if not env_vars:
            return ''
        
        exclude_set = set(exclude) if exclude else set()
        lines = []
        base = ' ' * indent
        
        for var_name in sorted(env_vars.keys()):
            # Skip excluded and internal variables
            if var_name in exclude_set or var_name.startswith('_'):
                continue
            
            # Get resolved value from all_variables (with ${VAR} references resolved)
            value = all_variables.get(var_name, env_vars[var_name])
            
            # Quote value for YAML safety
            if value in ('true', 'false', 'null') or value.isdigit():
                lines.append(f'{base}{var_name}: "{value}"')
            elif '"' in value:
                lines.append(f"{base}{var_name}: '{value}'")
            else:
                lines.append(f'{base}{var_name}: "{value}"')
        
        return '\n'.join(lines)
    
    return inject_env_vars


def load_globals(profile_stacks_dir: Path) -> Dict[str, str]:
    """Load globals.yaml and return GLOBAL_* prefixed variables."""
    globals_file = profile_stacks_dir / 'globals.yaml'
    if not globals_file.exists():
        return {}
    
    content = globals_file.read_text(encoding='utf-8')
    data = parse_yaml_simple(content)
    
    result = {}
    # Top-level keys become GLOBAL_*
    for key, value in data.items():
        if isinstance(value, str):
            result[f'GLOBAL_{key}'] = value
    
    return result


def load_endpoints(profile_stacks_dir: Path) -> Dict[str, str]:
    """Load endpoints.yaml and generate SERVICE_* variables."""
    endpoints_file = profile_stacks_dir / 'endpoints.yaml'
    if not endpoints_file.exists():
        return {}
    
    content = endpoints_file.read_text(encoding='utf-8')
    data = parse_yaml_simple(content)
    
    result = {}
    endpoints = data.get('endpoints', {})
    
    for category, services in endpoints.items():
        if not isinstance(services, dict):
            continue
        for service_name, props in services.items():
            if not isinstance(props, dict):
                continue
            
            # Generate prefix: SERVICE_<CATEGORY>_<NAME>_
            prefix = f"SERVICE_{category.upper()}_{service_name.upper()}"
            
            host = props.get('host', '')
            port = props.get('port', '')
            
            if host:
                result[f'{prefix}_HOST'] = host
            if port:
                result[f'{prefix}_PORT'] = str(port)
            if host and port:
                result[f'{prefix}_URL'] = f'http://{host}:{port}'
            
            # Optional fields
            if 'public_host' in props:
                result[f'{prefix}_PUBLIC_HOST'] = props['public_host']
            if 'network' in props:
                result[f'{prefix}_NETWORK'] = props['network']
            if 'database' in props:
                result[f'{prefix}_DATABASE'] = props['database']
    
    return result


def load_variables(stack_dir: Path) -> Tuple[Dict[str, str], Dict[str, str]]:
    """
    Load variables.yaml runtime section.
    
    Returns:
        Tuple of (all_vars, env_vars)
        - all_vars: All variables from runtime section (for template)
        - env_vars: Only variables from runtime.env section (for inject_env_vars)
    """
    variables_file = stack_dir / 'variables.yaml'
    if not variables_file.exists():
        return {}, {}
    
    content = variables_file.read_text(encoding='utf-8')
    data = parse_yaml_simple(content)
    
    result = {}
    env_vars = {}
    
    # Load common section
    common = data.get('common', {})
    if isinstance(common, dict):
        for key, value in common.items():
            if isinstance(value, str):
                result[key] = value
    
    # Load runtime section (higher priority)
    runtime = data.get('runtime', {})
    if isinstance(runtime, dict):
        for key, value in runtime.items():
            if key == 'env' and isinstance(value, dict):
                # runtime.env section — for auto-injection
                for env_key, env_value in value.items():
                    if isinstance(env_value, str):
                        result[env_key] = env_value
                        env_vars[env_key] = env_value
                    elif isinstance(env_value, list):
                        # Convert list to comma-separated string for Docker environment
                        str_value = ','.join(str(v) for v in env_value)
                        result[env_key] = str_value
                        env_vars[env_key] = str_value
            elif isinstance(value, str):
                result[key] = value
    
    return result, env_vars


def load_environment() -> Tuple[Dict[str, str], Dict[str, str]]:
    """
    Load environment variables with prefixes.
    
    Returns:
        Tuple of (all_vars, runtime_vars_only)
        - all_vars: All variables without prefix for template
        - runtime_vars_only: Only RUNTIME_* vars for RUNTIME_VARS dict in template
    
    Note: Only reads variables that are explicitly set in current process environment.
          Does not inherit from parent shell sessions.
    """
    result = {}
    runtime_vars = {}
    
    for key, value in os.environ.items():
        if key.startswith('RUNTIME_'):
            stripped_key = key[8:]  # Remove RUNTIME_ prefix
            result[stripped_key] = value
            runtime_vars[stripped_key] = value
        elif key.startswith('BUILD_'):
            stripped_key = key[6:]  # Remove BUILD_ prefix
            result[stripped_key] = value
        elif key.startswith('COMMON_'):
            stripped_key = key[7:]  # Remove COMMON_ prefix
            result[stripped_key] = value
        elif key.startswith('TAG_'):
            # TAG_* variables are generated during deploy (service image tags)
            result[key] = value
    
    return result, runtime_vars


def resolve_variable_references(variables: Dict[str, str], max_iterations: int = 10) -> Dict[str, str]:
    """
    Resolve ${VAR} references in variable values.
    
    Example:
        If variables = {'A': 'hello', 'B': '${A} world'}
        Result = {'A': 'hello', 'B': 'hello world'}
    """
    result = dict(variables)
    pattern = r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}'
    
    for _ in range(max_iterations):
        changed = False
        for key, value in result.items():
            if not isinstance(value, str):
                continue
            
            def replace(match):
                nonlocal changed
                var_name = match.group(1)
                if var_name in result and isinstance(result[var_name], str):
                    # Don't replace with self (avoid infinite loop)
                    if var_name != key:
                        changed = True
                        return result[var_name]
                return match.group(0)  # Keep original if not found
            
            new_value = re.sub(pattern, replace, value)
            result[key] = new_value
        
        if not changed:
            break
    
    return result


def collect_all_variables(profile_stacks_dir: Path, stack_dir: Path) -> Tuple[Dict[str, str], Dict[str, Tuple[str, str]]]:
    """
    Collect all variables from all sources.
    
    Returns:
        Tuple of (merged_vars, sources)
        - merged_vars: Final merged variables
        - sources: Dict of var_name -> (source, value) for debugging
    """
    sources = {}
    merged = {}
    
    # 1. Globals (lowest priority)
    globals_vars = load_globals(profile_stacks_dir)
    for key, value in globals_vars.items():
        merged[key] = value
        sources[key] = ('globals.yaml', value)
    
    # 2. Endpoints
    endpoints_vars = load_endpoints(profile_stacks_dir)
    for key, value in endpoints_vars.items():
        merged[key] = value
        sources[key] = ('endpoints.yaml', value)
    
    # 3. Variables.yaml (all_vars includes both runtime.* and runtime.env.*)
    variables_vars, _ = load_variables(stack_dir)
    for key, value in variables_vars.items():
        merged[key] = value
        sources[key] = ('variables.yaml', value)
    
    # 4. Environment (highest priority)
    env_vars, runtime_vars = load_environment()
    for key, value in env_vars.items():
        merged[key] = value
        sources[key] = ('environment', value)
    
    # Resolve ${VAR} references in values
    merged = resolve_variable_references(merged)
    
    # Add RUNTIME_VARS dict for iteration in templates
    merged['RUNTIME_VARS'] = runtime_vars
    
    # Add metadata
    merged['_generated_at'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    merged['_stack_name'] = stack_dir.name
    
    return merged, sources


def find_used_variables_in_template(template_content: str) -> set:
    """
    Find all variable names used in a Jinja2 template.
    
    Detects:
    - {{ VAR }}
    - {{ VAR | filter }}
    - {{ VAR.attribute }}
    - {% if VAR %}
    - {% for x in VAR %}
    - {{ func(VAR) }}
    
    Returns:
        Set of variable names found in template
    """
    used_vars = set()
    
    # Pattern for {{ VAR }} or {{ VAR | filter }} or {{ VAR.attr }}
    # Matches: VAR_NAME at start of expression
    pattern_expr = r'\{\{\s*([A-Z][A-Z0-9_]*)'
    
    # Pattern for {% if VAR %} or {% elif VAR %}
    pattern_if = r'\{%\s*(?:if|elif)\s+([A-Z][A-Z0-9_]*)'
    
    # Pattern for {% for x in VAR %}
    pattern_for = r'\{%\s*for\s+\w+\s+in\s+([A-Z][A-Z0-9_]*)'
    
    # Pattern for function calls with VAR as argument: func(VAR) or func('x', VAR)
    pattern_func_arg = r'\(\s*[^)]*?([A-Z][A-Z0-9_]*)\s*[,)]'
    
    # Pattern for VAR in any Jinja2 context (broader catch)
    # Matches uppercase identifiers that look like env vars
    pattern_general = r'(?<![A-Za-z_])([A-Z][A-Z0-9_]{2,})(?![A-Za-z0-9_])'
    
    for pattern in [pattern_expr, pattern_if, pattern_for, pattern_func_arg]:
        for match in re.finditer(pattern, template_content):
            var_name = match.group(1)
            # Skip Jinja2 keywords and common non-variables
            if var_name not in {'RUNTIME_VARS', 'True', 'False', 'None'}:
                used_vars.add(var_name)
    
    # Also check for variables used in default() filter: {{ X | default(VAR) }}
    pattern_default = r'\|\s*default\s*\(\s*([A-Z][A-Z0-9_]*)\s*[,)]'
    for match in re.finditer(pattern_default, template_content):
        used_vars.add(match.group(1))
    
    return used_vars


def validate_variables_usage(
    variables_yaml_vars: Dict[str, str],
    env_vars_to_inject: Dict[str, str],
    template_content: str,
    stack_name: str
) -> List[str]:
    """
    Validate that variables from variables.yaml are used in template.
    
    Variables in runtime.env section are excluded from validation because
    they are auto-injected via inject_env_vars().
    
    Args:
        variables_yaml_vars: All variables from variables.yaml deploy section
        env_vars_to_inject: Variables from runtime.env section (auto-injected)
        template_content: Content of the Jinja2 template
        stack_name: Name of the stack (for error messages)
    
    Returns:
        List of warning messages for unused variables
    """
    if not variables_yaml_vars:
        return []
    
    used_vars = find_used_variables_in_template(template_content)
    warnings = []
    
    for var_name in sorted(variables_yaml_vars.keys()):
        # Skip internal/meta variables
        if var_name.startswith('_'):
            continue
        
        # Skip env vars — they are auto-injected via inject_env_vars()
        if var_name in env_vars_to_inject:
            continue
        
        if var_name not in used_vars:
            warnings.append(f"  - {var_name}")
    
    return warnings


def convert_docker_compose_to_jinja(content: str) -> str:
    """
    Convert Docker Compose ${VAR} syntax to Jinja2 {{ VAR }}.
    
    Handles:
    - ${VAR} -> {{ VAR }}
    - ${VAR:-default} -> {{ VAR }} (default moved to variables.yaml)
    - ${VAR:-${OTHER}} -> {{ VAR }} (nested vars simplified)
    """
    # Pattern for ${VAR} or ${VAR:-...} (non-greedy, handles nested)
    # Use a function to handle nested ${} in defaults
    def replace_var(match):
        var_name = match.group(1)
        return '{{ ' + var_name + ' }}'
    
    # First pass: replace simple ${VAR}
    result = content
    
    # Handle ${VAR:-default} including nested ${} in default
    # Match ${VAR:- followed by anything until the matching }
    pattern_with_default = r'\$\{([A-Za-z_][A-Za-z0-9_]*):-[^}]*(?:\$\{[^}]*\}[^}]*)?\}'
    result = re.sub(pattern_with_default, replace_var, result)
    
    # Handle simple ${VAR}
    pattern_simple = r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}'
    result = re.sub(pattern_simple, replace_var, result)
    
    # Cleanup: fix }}} artifacts from nested ${VAR:-${OTHER}} patterns
    result = re.sub(r'\}\}\}+', '}}', result)
    
    # Add header comment
    header = """# =============================================================================
# JINJA2 TEMPLATE - Automatically generated from docker-stack.yml
# =============================================================================
# DO NOT edit .build/docker-stack.yml directly!
# Make changes in this file or in variables.yaml
#
# Rendering: swarmcli template render <stack>
# Variables preview: swarmcli template vars <stack>
# =============================================================================

"""
    
    return header + result


def init_templates(profile_stacks_dir: Path, stack_dir: Path) -> bool:
    """
    Initialize templates for a stack.
    
    Creates:
    - templates.yaml config
    - templates/ directory
    - templates/docker-stack.j2 from docker-stack.yml
    """
    docker_stack_file = stack_dir / 'docker-stack.yml'
    templates_yaml = stack_dir / 'templates.yaml'
    templates_dir = stack_dir / 'templates'
    template_file = templates_dir / 'docker-stack.j2'
    build_dir = stack_dir / '.build'
    
    # Check if docker-stack.yml exists
    if not docker_stack_file.exists():
        print(f"Error: docker-stack.yml not found in {stack_dir}", file=sys.stderr)
        return False
    
    # Check if already initialized
    if templates_yaml.exists():
        print(f"Warning: templates.yaml already exists in {stack_dir}", file=sys.stderr)
        print("Use --force to reinitialize", file=sys.stderr)
        return False
    
    # Create directories
    templates_dir.mkdir(exist_ok=True)
    build_dir.mkdir(exist_ok=True)
    
    # Convert docker-stack.yml to Jinja2 template
    original_content = docker_stack_file.read_text(encoding='utf-8')
    jinja_content = convert_docker_compose_to_jinja(original_content)
    template_file.write_text(jinja_content, encoding='utf-8')
    
    # Create templates.yaml
    templates_config = """# Templating configuration
# Documentation: docs/02-guides/templates/

engine: jinja2

templates:
  docker-stack:
    source: templates/docker-stack.j2
    output: .build/docker-stack.yml

# Variable sources (order = priority, last wins)
variable_sources:
  - globals        # GLOBAL_* from profiles/*/stacks/globals.yaml
  - endpoints      # SERVICE_* from profiles/*/stacks/endpoints.yaml
  - variables      # from ./variables.yaml (common and deploy sections)
  - environment    # DEPLOY_*, BUILD_*, COMMON_* from environment (GitLab CI)

# Optional: required variables (deploy will fail if missing)
# required_vars:
#   - GLOBAL_TZ
#   - DATABASE_URL
"""
    templates_yaml.write_text(templates_config, encoding='utf-8')
    
    # Create .gitkeep in .build
    (build_dir / '.gitkeep').write_text('# Keep this directory\n', encoding='utf-8')
    
    print(f"[template] Initialized templates for {stack_dir.name}")
    print(f"[template] Created: templates.yaml")
    print(f"[template] Created: templates/docker-stack.j2")
    print(f"[template] Created: .build/")
    print()
    print(f"[template] Next steps:")
    print(f"  1. Review templates/docker-stack.j2")
    print(f"  2. Run: swarmcli template render {stack_dir.name}")
    print(f"  3. Check: .build/docker-stack.yml")
    
    return True


def render_templates(profile_stacks_dir: Path, stack_dir: Path, verbose: bool = False) -> bool:
    """Render all templates defined in templates.yaml."""
    if not JINJA2_AVAILABLE:
        print("Error: Jinja2 not installed. Run: pip install jinja2", file=sys.stderr)
        return False
    
    templates_yaml = stack_dir / 'templates.yaml'
    if not templates_yaml.exists():
        print(f"Error: templates.yaml not found in {stack_dir}", file=sys.stderr)
        print(f"Run: swarmcli template init {stack_dir.name}", file=sys.stderr)
        return False
    
    # Parse templates.yaml
    config = parse_yaml_simple(templates_yaml.read_text(encoding='utf-8'))
    
    # Collect variables
    variables, sources = collect_all_variables(profile_stacks_dir, stack_dir)
    
    # Load all resources (for cross-stack resource lookups)
    stack_name = stack_dir.name
    all_resources = load_all_resources(profile_stacks_dir)
    stack_resources = all_resources.get(stack_name, {})
    
    if verbose:
        print(f"[template] Variables loaded: {len(variables) - 2}")  # -2 for metadata
        for source_name in ['globals.yaml', 'endpoints.yaml', 'variables.yaml', 'environment']:
            count = sum(1 for s, _ in sources.values() if s == source_name)
            if count > 0:
                print(f"  - {source_name}: {count} vars")
        if stack_resources:
            print(f"[template] Resources loaded for {len(stack_resources)} service(s)")
        if len(all_resources) > 1:
            print(f"[template] Cross-stack resources available: {len(all_resources)} stack(s)")
    
    # Validate required variables
    required_vars = config.get('required_vars', [])
    if isinstance(required_vars, dict):
        # Handle case where required_vars is parsed as dict (shouldn't happen with list)
        required_vars = list(required_vars.keys())
    
    missing_vars = []
    for var_name in required_vars:
        if var_name not in variables or variables.get(var_name) is None:
            missing_vars.append(var_name)
    
    if missing_vars:
        print(f"Error: Missing required variables:", file=sys.stderr)
        for var in missing_vars:
            print(f"  - {var}", file=sys.stderr)
        print(f"\nCheck: templates.yaml → required_vars", file=sys.stderr)
        return False
    
    # Setup Jinja2 environment
    env = Environment(
        loader=FileSystemLoader(str(stack_dir)),
        undefined=StrictUndefined,
        keep_trailing_newline=True
    )
    
    # Load variables.yaml for validation and inject_env_vars function
    variables_yaml_vars, env_vars_to_inject = load_variables(stack_dir)
    
    # Add ENV_VARS dict to template context (for x-anchor generation, like RUNTIME_VARS)
    # Resolve ${VAR} references in env_vars values
    resolved_env_vars = {}
    for key, value in env_vars_to_inject.items():
        resolved_env_vars[key] = variables.get(key, value)
    variables['ENV_VARS'] = resolved_env_vars
    
    # Load services metadata for Dozzle labels and service images
    services_meta = parse_services_yaml(stack_dir)
    
    # Register deploy_resources() global function
    env.globals['deploy_resources'] = create_deploy_resources_func(all_resources, stack_name)
    
    # Register inject_env_vars() global function (uses only runtime.env section)
    env.globals['inject_env_vars'] = create_inject_env_vars_func(env_vars_to_inject, variables)
    
    # Register dozzle_labels() global function
    env.globals['dozzle_labels'] = create_dozzle_labels_func(services_meta)
    
    # Register service_image() global function
    env.globals['service_image'] = create_service_image_func(services_meta, variables)
    
    # Register config_name() global function
    config_mappings = load_config_mappings()
    env.globals['config_name'] = create_config_name_func(config_mappings)
    
    # Render templates
    templates_config = config.get('templates', {})
    if not templates_config:
        # Fallback to default
        templates_config = {
            'docker-stack': {
                'source': 'templates/docker-stack.j2',
                'output': '.build/docker-stack.yml'
            }
        }
    
    success = True
    for name, tpl_config in templates_config.items():
        if not isinstance(tpl_config, dict):
            continue
        
        source = tpl_config.get('source', f'templates/{name}.j2')
        output = tpl_config.get('output', f'.build/{name}.yml')
        
        source_path = stack_dir / source
        output_path = stack_dir / output
        
        if not source_path.exists():
            print(f"Error: Template not found: {source_path}", file=sys.stderr)
            success = False
            continue
        
        # Read template content for validation
        template_content = source_path.read_text(encoding='utf-8')
        
        # Validate variables usage (env vars are excluded — they're auto-injected)
        unused_warnings = validate_variables_usage(
            variables_yaml_vars,
            env_vars_to_inject,
            template_content,
            stack_name
        )
        
        if unused_warnings:
            print(f"[template] ⚠️  Unused variables from variables.yaml ({stack_name}):")
            for warning in unused_warnings:
                print(warning)
            print(f"[template] ℹ️  These variables are defined but not used in {source}")
            print()
        
        # Ensure output directory exists
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        try:
            template = env.get_template(source)
            rendered = template.render(**variables)
            output_path.write_text(rendered, encoding='utf-8')
            if not is_ci():
                print(f"[template] Rendered: {output}")
        except UndefinedError as e:
            print(f"Error: Undefined variable in template: {e}", file=sys.stderr)
            success = False
        except Exception as e:
            print(f"Error rendering {source}: {e}", file=sys.stderr)
            success = False
    
    return success


def show_variables(profile_stacks_dir: Path, stack_dir: Path) -> bool:
    """Show all variables and their sources."""
    variables, sources = collect_all_variables(profile_stacks_dir, stack_dir)
    
    # Group by source
    by_source = {}
    for var_name, (source, value) in sources.items():
        if source not in by_source:
            by_source[source] = []
        by_source[source].append((var_name, value))
    
    print(f"[template] Variables for {stack_dir.name}")
    print(f"[template] Total: {len(sources)}")
    print()
    
    for source in ['globals.yaml', 'endpoints.yaml', 'variables.yaml', 'environment']:
        if source not in by_source:
            continue
        
        vars_list = sorted(by_source[source], key=lambda x: x[0])
        print(f"=== {source} ({len(vars_list)} vars) ===")
        for var_name, value in vars_list:
            # Truncate long values
            display_value = value if len(value) <= 50 else value[:47] + '...'
            print(f"  {var_name}={display_value}")
        print()
    
    return True


def main():
    if len(sys.argv) < 4:
        print("Usage: templates.py <command> <profile_stacks_dir> <stack_dir> [options]", file=sys.stderr)
        print("Commands: init, render, vars", file=sys.stderr)
        sys.exit(1)
    
    command = sys.argv[1]
    profile_stacks_dir = Path(sys.argv[2])
    stack_dir = Path(sys.argv[3])
    
    verbose = '--verbose' in sys.argv or '-v' in sys.argv
    
    if command == 'init':
        success = init_templates(profile_stacks_dir, stack_dir)
    elif command == 'render':
        success = render_templates(profile_stacks_dir, stack_dir, verbose)
    elif command == 'vars':
        success = show_variables(profile_stacks_dir, stack_dir)
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()

