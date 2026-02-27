#!/usr/bin/env python3
"""
Validate all stacks in SwarmCLI profiles.
Checks YAML syntax and required fields.

Usage:
  python validate_stacks.py [--profiles PROFILES] [--profiles-dir DIR]
  --profiles: comma-separated profile names (default: all in profiles-dir)
  --profiles-dir: base dir for profiles (default: profiles)
"""

import argparse
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip install pyyaml")
    sys.exit(1)


def validate_yaml_file(filepath):
    """Validate YAML syntax"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            yaml.safe_load(f)
        return None
    except yaml.YAMLError as e:
        return str(e)
    except Exception as e:
        return str(e)


def check_services_yaml(filepath):
    """Check services.yaml for required fields"""
    errors = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
        
        if not data or 'services' not in data:
            errors.append('Missing services section')
            return errors
            
        services = data.get('services', {})
        if not services:
            errors.append('No services defined')
            return errors
            
        for svc_name, svc_config in services.items():
            if not svc_config:
                errors.append(f'{svc_name}: empty config')
                continue
                
            svc_type = svc_config.get('type')
            if not svc_type:
                errors.append(f'{svc_name}: missing type field')
            elif svc_type not in ['git', 'registry', 'none']:
                errors.append(f'{svc_name}: invalid type "{svc_type}" (must be git, registry or none)')
            
            # type: none - metadata-only, inherits image from parent
            if svc_type != 'none':
                if not svc_config.get('image'):
                    errors.append(f'{svc_name}: missing image field')
            
            if svc_type == 'git':
                if not svc_config.get('repo'):
                    errors.append(f'{svc_name}: missing repo field (required for type: git)')
                if not svc_config.get('default_branch'):
                    errors.append(f'{svc_name}: missing default_branch field')
    except Exception as e:
        errors.append(f'Parse error: {e}')
    
    return errors


def check_docker_stack(filepath):
    """Check docker-stack.yml for basic structure"""
    errors = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
        
        if not data:
            errors.append('Empty file')
            return errors
        
        if 'services' not in data:
            errors.append('Missing services section')
    except Exception as e:
        errors.append(f'Parse error: {e}')
    
    return errors


def check_externals_yaml(filepath, stack_dir):
    """Check externals.yaml for valid structure and config file existence"""
    errors = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
        
        if not data:
            return errors  # Empty is OK
        
        # Check secrets format (list of strings)
        secrets = data.get('secrets', [])
        if secrets:
            if not isinstance(secrets, list):
                errors.append('secrets must be a list')
            else:
                for i, secret in enumerate(secrets):
                    if not isinstance(secret, str):
                        errors.append(f'secrets[{i}]: must be a string')
        
        # Check configs format (list of dicts with name and file)
        configs = data.get('configs', [])
        if configs:
            if not isinstance(configs, list):
                errors.append('configs must be a list')
            else:
                for i, config in enumerate(configs):
                    if not isinstance(config, dict):
                        errors.append(f'configs[{i}]: must be an object with name and file')
                        continue
                    
                    name = config.get('name')
                    file = config.get('file')
                    
                    if not name:
                        errors.append(f'configs[{i}]: missing name field')
                    if not file:
                        errors.append(f'configs[{i}]: missing file field')
                    
                    # Check config file exists
                    if file:
                        config_path = stack_dir / file
                        if not config_path.exists():
                            errors.append(f'configs[{i}]: file not found: {file}')
                        elif not config_path.is_file():
                            errors.append(f'configs[{i}]: not a file: {file}')
                        elif config_path.stat().st_size == 0:
                            errors.append(f'configs[{i}]: file is empty: {file}')
    except Exception as e:
        errors.append(f'Parse error: {e}')
    
    return errors


def check_settings_yaml(filepath):
    """Check settings.yaml for valid values"""
    errors = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
        
        if not data:
            return errors  # Empty is OK
        
        # Check config_strategy if present
        config_strategy = data.get('config_strategy')
        if config_strategy and config_strategy not in ['simple', 'versioned']:
            errors.append(f'config_strategy: invalid value "{config_strategy}" (must be simple or versioned)')
    except Exception as e:
        errors.append(f'Parse error: {e}')
    
    return errors


def main():
    parser = argparse.ArgumentParser(
        description='Validate all stacks in SwarmCLI profiles'
    )
    parser.add_argument(
        '--profiles',
        default=None,
        help='Comma-separated profile names (default: all in profiles-dir)'
    )
    parser.add_argument(
        '--profiles-dir',
        default='profiles',
        help='Base directory for profiles (default: profiles)'
    )
    args = parser.parse_args()
    
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    base_path = project_root / args.profiles_dir
    
    if not base_path.exists():
        print(f"ERROR: Profiles directory not found: {base_path}")
        sys.exit(1)
    
    if args.profiles:
        profiles = [p.strip() for p in args.profiles.split(',') if p.strip()]
    else:
        profiles = sorted(
            d.name for d in base_path.iterdir()
            if d.is_dir() and (d / 'stacks').exists()
        )
    
    all_errors = []
    stacks_checked = 0
    stacks_valid = 0
    
    for profile in profiles:
        stacks_dir = base_path / profile / 'stacks'
        if not stacks_dir.exists():
            print(f"WARNING: Stacks directory not found: {stacks_dir}")
            continue
        
        print(f"\n=== Profile: {profile} ===")
        
        for stack_dir in sorted(stacks_dir.iterdir()):
            if not stack_dir.is_dir():
                continue
            
            stacks_checked += 1
            stack_name = stack_dir.name
            stack_errors = []
            
            # Check services.yaml
            services_yaml = stack_dir / 'services.yaml'
            if services_yaml.exists():
                yaml_err = validate_yaml_file(services_yaml)
                if yaml_err:
                    stack_errors.append(f'services.yaml: YAML syntax error')
                else:
                    svc_errors = check_services_yaml(services_yaml)
                    for err in svc_errors:
                        stack_errors.append(f'services.yaml: {err}')
            else:
                stack_errors.append('missing services.yaml')
            
            # Check docker-stack: either docker-stack.yml or templates/docker-stack.j2
            docker_stack = stack_dir / 'docker-stack.yml'
            templates_yaml = stack_dir / 'templates.yaml'
            template_stack = None
            if templates_yaml.exists():
                try:
                    with open(templates_yaml, 'r', encoding='utf-8') as f:
                        tpl = yaml.safe_load(f)
                    if tpl and 'templates' in tpl and 'docker-stack' in tpl.get('templates', {}):
                        src = tpl['templates']['docker-stack'].get('source')
                        if src:
                            template_stack = stack_dir / src
                except Exception:
                    pass
            if docker_stack.exists():
                yaml_err = validate_yaml_file(docker_stack)
                if yaml_err:
                    stack_errors.append(f'docker-stack.yml: YAML syntax error')
                else:
                    ds_errors = check_docker_stack(docker_stack)
                    for err in ds_errors:
                        stack_errors.append(f'docker-stack.yml: {err}')
            elif template_stack and template_stack.exists():
                # Jinja2 stack: template exists, skip docker-stack structure check
                pass
            else:
                stack_errors.append('missing docker-stack.yml or templates/docker-stack.j2')
            
            # Check variables.yaml syntax
            variables_yaml = stack_dir / 'variables.yaml'
            if variables_yaml.exists():
                yaml_err = validate_yaml_file(variables_yaml)
                if yaml_err:
                    stack_errors.append(f'variables.yaml: YAML syntax error')
            
            # Check externals.yaml syntax and structure
            externals_yaml = stack_dir / 'externals.yaml'
            if externals_yaml.exists():
                yaml_err = validate_yaml_file(externals_yaml)
                if yaml_err:
                    stack_errors.append(f'externals.yaml: YAML syntax error')
                else:
                    ext_errors = check_externals_yaml(externals_yaml, stack_dir)
                    for err in ext_errors:
                        stack_errors.append(f'externals.yaml: {err}')
            
            # Check settings.yaml syntax and values
            settings_yaml = stack_dir / 'settings.yaml'
            if settings_yaml.exists():
                yaml_err = validate_yaml_file(settings_yaml)
                if yaml_err:
                    stack_errors.append(f'settings.yaml: YAML syntax error')
                else:
                    set_errors = check_settings_yaml(settings_yaml)
                    for err in set_errors:
                        stack_errors.append(f'settings.yaml: {err}')
            
            # Report
            if stack_errors:
                print(f"  [FAIL] {stack_name}")
                for err in stack_errors:
                    print(f"      - {err}")
                    all_errors.append(f'{profile}/{stack_name}: {err}')
            else:
                print(f"  [OK] {stack_name}")
                stacks_valid += 1
    
    # Summary
    print(f"\n{'='*50}")
    print(f"SUMMARY: Checked {stacks_checked} stacks")
    print(f"  Valid: {stacks_valid}")
    print(f"  Errors: {len(all_errors)}")
    
    if all_errors:
        print(f"\nAll errors:")
        for err in all_errors:
            print(f"  - {err}")
        return 1
    else:
        print(f"\n[OK] All stacks are valid!")
        return 0


if __name__ == '__main__':
    sys.exit(main())
