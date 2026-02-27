#!/usr/bin/env python3
"""
Generate settings.yaml for all stacks based on resource requirements.

Timeout logic:
- 8G+ RAM → 120s (heavy services: ML models, Spring Boot with migrations)
- 2G-6G RAM → 90s (medium services)
- Multi-service stacks → 90s (dependencies between services)
- 512M-1G RAM → 45s (light services)
- 256M or less / frontend → 30s (very light)

No external dependencies required.
"""

import os
import re
from pathlib import Path


def parse_memory(memory_str: str) -> int:
    """Convert memory string (e.g., '8G', '512M') to MB."""
    if not memory_str:
        return 0
    
    memory_str = memory_str.strip().strip('"\'').upper()
    
    match = re.match(r'^(\d+(?:\.\d+)?)\s*([GM]?)B?$', memory_str)
    if not match:
        return 0
    
    value = float(match.group(1))
    unit = match.group(2) or 'M'
    
    if unit == 'G':
        return int(value * 1024)
    return int(value)


def parse_resources_yaml(file_path: Path) -> dict:
    """
    Simple YAML parser for resources.yaml.
    Returns dict: {stack_name: {service_name: {limits: {memory: str}}}}
    """
    if not file_path.exists():
        return {}
    
    result = {}
    current_stack = None
    current_service = None
    current_section = None  # 'limits' or 'reservations'
    
    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip()
            
            # Skip empty lines and comments
            stripped = line.lstrip()
            if not stripped or stripped.startswith('#'):
                continue
            
            # Calculate indent
            indent = len(line) - len(stripped)
            
            # Remove trailing colon and get key
            if ':' not in stripped:
                continue
            
            key_part = stripped.split(':')[0].strip()
            value_part = stripped.split(':', 1)[1].strip() if ':' in stripped else ''
            
            # stacks: (indent 0)
            if indent == 0 and key_part == 'stacks':
                continue
            
            # Stack name (indent 2)
            if indent == 2 and key_part and not value_part:
                current_stack = key_part
                result[current_stack] = {}
                current_service = None
                current_section = None
                continue
            
            # Service name (indent 4)
            if indent == 4 and current_stack and key_part and not value_part:
                current_service = key_part
                result[current_stack][current_service] = {'limits': {}, 'reservations': {}}
                current_section = None
                continue
            
            # limits/reservations (indent 6)
            if indent == 6 and current_service and key_part in ('limits', 'reservations'):
                current_section = key_part
                continue
            
            # memory/cpus (indent 8)
            if indent == 8 and current_section and key_part in ('memory', 'cpus'):
                if current_stack and current_service:
                    result[current_stack][current_service][current_section][key_part] = value_part.strip('"\'')
    
    return result


def get_max_memory_for_stack(resources: dict, stack_name: str) -> int:
    """Get maximum memory limit for any service in the stack."""
    stack_resources = resources.get(stack_name, {})
    
    max_memory = 0
    for service_name, service_resources in stack_resources.items():
        limits = service_resources.get('limits', {})
        memory = limits.get('memory', '')
        memory_mb = parse_memory(memory)
        max_memory = max(max_memory, memory_mb)
    
    return max_memory


def get_service_count(resources: dict, stack_name: str) -> int:
    """Get number of services in the stack."""
    stack_resources = resources.get(stack_name, {})
    return len(stack_resources)


def determine_timeout(stack_name: str, max_memory_mb: int, service_count: int) -> int:
    """Determine appropriate timeout based on stack characteristics."""
    
    # Frontend/lightweight stacks are always fast
    if 'frontend' in stack_name or 'embed' in stack_name:
        return 30
    
    # Gateway/normalizer stacks are light
    if 'gateway' in stack_name or 'normalizer' in stack_name:
        return 30
    
    # Heavy services (8G+)
    if max_memory_mb >= 8 * 1024:  # 8G
        return 120
    
    # Medium services (2G-6G) or multi-service stacks
    if max_memory_mb >= 2 * 1024 or service_count >= 3:  # 2G or 3+ services
        return 90
    
    # Light services (512M-1G)
    if max_memory_mb >= 512:
        return 45
    
    # Very light services
    return 30


def get_all_stacks(profile_path: Path) -> list:
    """Get all stack directories in a profile."""
    stacks_dir = profile_path / 'stacks'
    if not stacks_dir.exists():
        return []
    
    stacks = []
    for item in stacks_dir.iterdir():
        if item.is_dir() and not item.name.startswith('.'):
            # Check if it's a valid stack (has docker-stack.yml or services.yaml)
            if (item / 'docker-stack.yml').exists() or (item / 'services.yaml').exists():
                stacks.append(item.name)
    
    return sorted(stacks)


def generate_settings_yaml(stack_path: Path, timeout: int, dry_run: bool = False) -> bool:
    """Generate settings.yaml for a stack."""
    settings_file = stack_path / 'settings.yaml'
    
    content = f"""# Stack-specific settings
# Overrides profile defaults

# Timeout for services to become ready after deploy (seconds)
services_ready_timeout: {timeout}
"""
    
    if dry_run:
        print(f"    Would create: settings.yaml")
        return True
    
    with open(settings_file, 'w', encoding='utf-8') as f:
        f.write(content)
    
    return True


def process_profile(profile_path: Path, dry_run: bool = False) -> dict:
    """Process all stacks in a profile."""
    profile_name = profile_path.name
    print(f"\n{'='*60}")
    print(f"Profile: {profile_name}")
    print(f"{'='*60}")
    
    resources_file = profile_path / 'stacks' / 'resources.yaml'
    resources = parse_resources_yaml(resources_file)
    stacks = get_all_stacks(profile_path)
    
    results = {
        'created': 0,
        'skipped': 0,
        'stacks': {}
    }
    
    for stack_name in stacks:
        stack_path = profile_path / 'stacks' / stack_name
        
        max_memory = get_max_memory_for_stack(resources, stack_name)
        service_count = get_service_count(resources, stack_name)
        timeout = determine_timeout(stack_name, max_memory, service_count)
        
        memory_str = f"{max_memory}M" if max_memory < 1024 else f"{max_memory/1024:.1f}G"
        
        print(f"\n  {stack_name}:")
        print(f"    Max memory: {memory_str if max_memory > 0 else 'not defined'}")
        print(f"    Services in resources.yaml: {service_count}")
        print(f"    Timeout: {timeout}s")
        
        if generate_settings_yaml(stack_path, timeout, dry_run):
            results['created'] += 1
            results['stacks'][stack_name] = timeout
        else:
            results['skipped'] += 1
    
    return results


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Generate settings.yaml for all stacks')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without making changes')
    parser.add_argument('--profiles', nargs='+', default=None,
                        help='Profiles to process (default: all in profiles-dir)')
    parser.add_argument('--profiles-dir', default='profiles',
                        help='Base directory for profiles (default: profiles)')
    args = parser.parse_args()
    
    # Find project root
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    profiles_dir = project_root / args.profiles_dir
    
    if not profiles_dir.exists():
        print(f"Error: profiles directory not found: {profiles_dir}")
        return 1
    
    if args.profiles:
        profile_names = args.profiles
    else:
        profile_names = sorted(
            d.name for d in profiles_dir.iterdir()
            if d.is_dir() and (d / 'stacks').exists()
        )
    
    print("="*60)
    print("Generate settings.yaml for all stacks")
    print("="*60)
    
    if args.dry_run:
        print("\n*** DRY RUN MODE - No changes will be made ***\n")
    
    total_created = 0
    
    for profile_name in profile_names:
        profile_path = profiles_dir / profile_name
        if not profile_path.exists():
            print(f"\nWarning: Profile not found: {profile_name}")
            continue
        
        results = process_profile(profile_path, args.dry_run)
        total_created += results['created']
    
    print(f"\n{'='*60}")
    print(f"Summary: {total_created} settings.yaml files {'would be ' if args.dry_run else ''}created")
    print(f"{'='*60}")
    
    return 0


if __name__ == '__main__':
    exit(main())
