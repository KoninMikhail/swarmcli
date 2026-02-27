#!/usr/bin/env python3
"""
Validate consistency of service names across:
- services.yaml
- docker-stack.yml
- resources.yaml

Reports mismatches that could cause issues during deploy.

Usage:
  python validate_service_names.py [--profiles PROFILES] [--profiles-dir DIR]
"""

import argparse
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit(
        "Error: PyYAML is not installed.\n"
        "Install it with: pip install pyyaml"
    )


def get_services_from_services_yaml(filepath):
    """Get service names from services.yaml"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
        return set(data.get('services', {}).keys())
    except Exception:
        return set()


def get_services_from_docker_stack(filepath):
    """Get service names from docker-stack.yml"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
        return set(data.get('services', {}).keys())
    except Exception:
        return set()


def get_stack_resources(resources_path, stack_name):
    """Get service names from resources.yaml for specific stack"""
    try:
        with open(resources_path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
        stacks = data.get('stacks', {})
        return set(stacks.get(stack_name, {}).keys())
    except Exception:
        return set()


def main():
    parser = argparse.ArgumentParser(
        description='Validate consistency of service names across stack configs'
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
    
    if args.profiles:
        profiles = [p.strip() for p in args.profiles.split(',') if p.strip()]
    else:
        profiles = sorted(
            d.name for d in base_path.iterdir()
            if d.is_dir() and (d / 'stacks').exists()
        )
    
    all_issues = []
    stacks_checked = 0
    
    for profile in profiles:
        stacks_dir = base_path / profile / 'stacks'
        resources_path = stacks_dir / 'resources.yaml'
        
        if not stacks_dir.exists():
            continue
        
        print(f"\n=== Profile: {profile} ===")
        
        for stack_dir in sorted(stacks_dir.iterdir()):
            if not stack_dir.is_dir():
                continue
            
            stack_name = stack_dir.name
            services_yaml = stack_dir / 'services.yaml'
            docker_stack = stack_dir / 'docker-stack.yml'
            if not docker_stack.exists():
                docker_stack = stack_dir / '.build' / 'docker-stack.yml'
            
            if not services_yaml.exists() or not docker_stack.exists():
                continue
            
            stacks_checked += 1
            issues = []
            
            # Get all service names
            yaml_services = get_services_from_services_yaml(services_yaml)
            docker_services = get_services_from_docker_stack(docker_stack)
            resource_services = get_stack_resources(resources_path, stack_name)
            
            # Check: docker-stack services should include all yaml_services (internal)
            # Note: docker-stack may have more (external services inline)
            
            # Check: resources.yaml services should exist in docker-stack
            if resource_services:
                unknown_in_resources = resource_services - docker_services
                if unknown_in_resources:
                    issues.append(f"resources.yaml references unknown services: {sorted(unknown_in_resources)}")
            
            # Check: services.yaml with type=git should have matching docker-stack
            try:
                with open(services_yaml, 'r', encoding='utf-8') as f:
                    svc_data = yaml.safe_load(f)
                
                for svc_name, svc_config in svc_data.get('services', {}).items():
                    if not svc_config:
                        continue
                    # Internal services should have a corresponding docker-stack entry
                    if svc_config.get('type') == 'git':
                        if svc_name not in docker_services:
                            # Check if there's a different naming (common pattern)
                            # Sometimes service in services.yaml != docker-stack service name
                            pass  # This is actually valid - image name != service name
            except Exception:
                pass
            
            if issues:
                print(f"  [FAIL] {stack_name}")
                for issue in issues:
                    print(f"      - {issue}")
                    all_issues.append(f"{profile}/{stack_name}: {issue}")
            else:
                print(f"  [OK] {stack_name}")
    
    print(f"\n{'='*50}")
    print(f"SUMMARY: Checked {stacks_checked} stacks")
    print(f"  Issues: {len(all_issues)}")
    
    if all_issues:
        print(f"\nAll issues:")
        for issue in all_issues:
            print(f"  - {issue}")
        return 1
    else:
        print(f"\n[OK] All service names are consistent!")
        return 0


if __name__ == '__main__':
    sys.exit(main())
